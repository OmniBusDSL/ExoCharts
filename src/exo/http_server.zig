const std = @import("std");
const coinbase = @import("coinbase_match.zig");

pub const Tick = coinbase.Tick;

/// HTTP server serving frontend and market matrix API
/// Listens on :8080, serves index.html and /api/matrix endpoint
pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    server: ?std.net.Server = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
    matrix_data: ?*anyopaque = null, // Opaque pointer to MarketMatrix
    matrix_getter: ?*const fn (?*anyopaque) MatrixSnapshot = null, // Function to get snapshot

    const PORT = 8080;
    const BACKLOG = 128;

    pub const MatrixSnapshot = struct {
        price_min: f32,
        price_max: f32,
        price_step: f32,
        time_buckets: u32,
        price_rows: u32,
        data: []const u64, // Flat array of volume values
        buy_data: []const u64 = &[_]u64{},  // Buy volume per cell
        sell_data: []const u64 = &[_]u64{}, // Sell volume per cell
        ticks_processed: u64,
        total_volume: u64,
        poc_price: f32,
        poc_volume: u64,
        current_time_bucket: u32,
    };

    pub fn init(allocator: std.mem.Allocator) HttpServer {
        return HttpServer{
            .allocator = allocator,
        };
    }

    pub fn set_matrix(self: *HttpServer, matrix_ptr: ?*anyopaque, getter: ?*const fn (?*anyopaque) MatrixSnapshot) void {
        self.matrix_data = matrix_ptr;
        self.matrix_getter = getter;
    }

    pub fn start(self: *HttpServer) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", PORT);
        self.server = try address.listen(.{
            .reuse_address = true,
        });

        std.debug.print("[server] Listening on http://127.0.0.1:{d}\n", .{PORT});

        while (self.running.load(.acquire)) {
            var client = self.server.?.accept() catch |err| {
                if (err == error.OperationAborted) break;
                continue;
            };
            defer client.stream.close();

            self.handleConnection(client.stream) catch |err| {
                std.debug.print("[server] Connection error: {}\n", .{err});
            };
        }
    }

    fn handleConnection(self: *HttpServer, connection: std.net.Stream) !void {
        var buffer: [4096]u8 = undefined;
        const bytes_read = try connection.readAll(&buffer);

        if (bytes_read == 0) return;

        const request = buffer[0..bytes_read];

        // Parse HTTP request line
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = lines.next() orelse "";

        // Parse method and path
        var parts = std.mem.splitSequence(u8, request_line, " ");
        const method = parts.next() orelse "GET";
        const path = parts.next() orelse "/";

        // Route requests
        if (std.mem.eql(u8, method, "GET")) {
            if (std.mem.eql(u8, path, "/")) {
                try self.serveFile(connection, "frontend/index.html", "text/html");
            } else if (std.mem.eql(u8, path, "/api/matrix")) {
                try self.serveMatrixJson(connection);
            } else if (std.mem.eql(u8, path, "/ws")) {
                try self.handleWebSocket(connection, request);
            } else {
                try self.serveNotFound(connection);
            }
        } else {
            try self.serveNotFound(connection);
        }
    }

    fn serveFile(self: *HttpServer, connection: std.net.Stream, file_path: []const u8, content_type: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            std.debug.print("[server] File not found: {s}: {}\n", .{ file_path, err });
            try self.serveNotFound(connection);
            return;
        };
        defer file.close();

        var buf: [4096]u8 = undefined;
        const content = try file.readAll(&buf);

        var header: [512]u8 = undefined;
        const header_len = try std.fmt.bufPrint(&header,
            "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ content_type, content.len }
        );

        _ = try connection.writeAll(header[0..header_len]);
        _ = try connection.writeAll(content);
    }

    fn serveMatrixJson(self: *HttpServer, connection: std.net.Stream) !void {
        if (self.matrix_getter == null) {
            try self.serveNotFound(connection);
            return;
        }

        const snapshot = self.matrix_getter.?(self.matrix_data);

        // Build JSON response
        var json_buf: [65536]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&json_buf);
        const writer = fbs.writer();

        try writer.print(
            "{{\"price_min\":{d},\"price_max\":{d},\"price_step\":{d},\"time_buckets\":{d},\"price_rows\":{d},\"ticks_processed\":{d},\"total_volume\":{d},\"poc_price\":{d},\"poc_volume\":{d},\"current_time_bucket\":{d},\"data\":[",
            .{
                snapshot.price_min,
                snapshot.price_max,
                snapshot.price_step,
                snapshot.time_buckets,
                snapshot.price_rows,
                snapshot.ticks_processed,
                snapshot.total_volume,
                snapshot.poc_price,
                snapshot.poc_volume,
                snapshot.current_time_bucket,
            }
        );

        for (snapshot.data, 0..) |val, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{d}", .{val});
        }

        try writer.writeAll("]}");

        const json_content = fbs.getWritten();

        var header: [512]u8 = undefined;
        const header_len = try std.fmt.bufPrint(&header,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
            .{json_content.len}
        );

        _ = try connection.writeAll(header[0..header_len]);
        _ = try connection.writeAll(json_content);
    }

    fn handleWebSocket(self: *HttpServer, connection: std.net.Stream, request: []const u8) !void {
        // Simple WebSocket upgrade (RFC 6455)
        // Extract Sec-WebSocket-Key from request
        var key: [24]u8 = undefined;
        var key_found = false;

        var lines = std.mem.splitSequence(u8, request, "\r\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "Sec-WebSocket-Key: ")) {
                const key_start = 19; // Length of "Sec-WebSocket-Key: "
                if (line.len >= key_start + 24) {
                    @memcpy(&key, line[key_start .. key_start + 24]);
                    key_found = true;
                    break;
                }
            }
        }

        if (!key_found) {
            try self.serveNotFound(connection);
            return;
        }

        // Calculate Sec-WebSocket-Accept
        var sha1_buf: [20]u8 = undefined;
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(&key);
        hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
        hasher.final(&sha1_buf);

        // Base64 encode
        var accept_buf: [28]u8 = undefined;
        const accept_b64 = std.base64.standard.Encoder.encode(&accept_buf, &sha1_buf);

        // Send upgrade response
        var response: [512]u8 = undefined;
        const response_len = try std.fmt.bufPrint(&response,
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
            .{accept_b64}
        );

        _ = try connection.writeAll(response[0..response_len]);

        // Send initial matrix snapshot
        if (self.matrix_getter != null) {
            const snapshot = self.matrix_getter.?(self.matrix_data);
            try self.sendWebSocketFrame(connection, snapshot);

            // Keep-alive: send updates every 1 second until error or server stop
            while (self.running.load(.acquire)) {
                std.time.sleep(1_000_000_000);  // 1 second in nanoseconds
                const updated = self.matrix_getter.?(self.matrix_data);
                try self.sendWebSocketFrame(connection, updated) catch |err| {
                    std.debug.print("[server] WebSocket send error: {}\n", .{err});
                    break;
                };
            }
        }
    }

    fn sendWebSocketFrame(_: *HttpServer, connection: std.net.Stream, snapshot: MatrixSnapshot) !void {
        // Build JSON payload
        var json_buf: [65536]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&json_buf);
        const writer = fbs.writer();

        try writer.print(
            "{{\"price_min\":{d},\"price_max\":{d},\"price_step\":{d},\"time_buckets\":{d},\"price_rows\":{d},\"ticks_processed\":{d},\"total_volume\":{d},\"poc_price\":{d},\"poc_volume\":{d},\"current_time_bucket\":{d},\"data\":[",
            .{
                snapshot.price_min,
                snapshot.price_max,
                snapshot.price_step,
                snapshot.time_buckets,
                snapshot.price_rows,
                snapshot.ticks_processed,
                snapshot.total_volume,
                snapshot.poc_price,
                snapshot.poc_volume,
                snapshot.current_time_bucket,
            }
        );

        for (snapshot.data, 0..) |val, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{d}", .{val});
            // Avoid buffer overflow on very large data arrays
            if (fbs.getPos().? > 60000) {
                try writer.writeAll("...truncated...");
                break;
            }
        }

        try writer.writeAll("],\"delta\":[");

        // Include delta (buy - sell) for each cell
        if (snapshot.buy_data.len > 0 and snapshot.sell_data.len > 0) {
            for (0..snapshot.buy_data.len) |i| {
                if (i > 0) try writer.writeAll(",");
                const buy_vol: i64 = @intCast(snapshot.buy_data[i]);
                const sell_vol: i64 = @intCast(snapshot.sell_data[i]);
                try writer.print("{d}", .{buy_vol - sell_vol});
                // Avoid buffer overflow
                if (fbs.getPos().? > 100000) {
                    try writer.writeAll("...truncated...");
                    break;
                }
            }
        }

        try writer.writeAll("]}");

        const json_content = fbs.getWritten();

        // WebSocket frame header (FIN=1, opcode=1 text, no mask)
        // First byte: FIN(1) + RSV(3) + opcode(4) = 0x81
        var frame: [2]u8 = undefined;
        frame[0] = 0x81; // FIN + text opcode

        if (json_content.len < 126) {
            frame[1] = @as(u8, @intCast(json_content.len));
            _ = try connection.writeAll(&frame);
        } else if (json_content.len < 65536) {
            frame[1] = 126;
            _ = try connection.writeAll(&frame);
            var len_bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &len_bytes, @as(u16, @intCast(json_content.len)), .big);
            _ = try connection.writeAll(&len_bytes);
        } else {
            frame[1] = 127;
            _ = try connection.writeAll(&frame);
            var len_bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &len_bytes, @as(u64, json_content.len), .big);
            _ = try connection.writeAll(&len_bytes);
        }

        _ = try connection.writeAll(json_content);
    }

    fn serveNotFound(_: *HttpServer, connection: std.net.Stream) !void {
        const response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found";
        _ = try connection.writeAll(response);
    }

    pub fn stop(self: *HttpServer) void {
        self.running.store(false, .release);
        // Note: Server deinit is not strictly necessary for this MVP
        // The OS will clean up the socket when the process exits
    }

    pub fn deinit(self: *HttpServer) void {
        self.stop();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = HttpServer.init(allocator);
    defer server.deinit();

    std.debug.print("✓ HTTP server initialized\n", .{});

    try server.start();
}
