const std = @import("std");
const coinbase = @import("coinbase_match.zig");
const kraken = @import("kraken_match.zig");
const lcx = @import("lcx_match.zig");
const ws_types = @import("ws_types.zig");

pub const Tick = coinbase.Tick;
pub const TickCallback = *const fn (?*const Tick) void;

pub const Exchange = enum(u32) {
    coinbase = 0,
    kraken = 1,
    lcx = 2,
};

const WsFrameType = ws_types.WsFrameType;

// Global state
var global_running = std.atomic.Value(bool).init(false);
var global_allocator: ?std.mem.Allocator = null;
var global_callback: ?TickCallback = null;
var global_stream: ?std.net.Stream = null;
var global_thread: ?std.Thread = null;
var global_exchange: Exchange = .coinbase;

/// Parse URL into host, port, and path
fn parseUrl(allocator: std.mem.Allocator, url: [*:0]const u8) ![3][]const u8 {
    _ = allocator; // Not used, but kept for potential future enhancements
    const url_slice = std.mem.sliceTo(url, 0);
    var host: []const u8 = "";
    var port_str: []const u8 = "443";
    var path: []const u8 = "";

    // Skip scheme (wss:// or ws://)
    var offset: usize = 0;
    if (std.mem.startsWith(u8, url_slice, "wss://")) {
        offset = 6;
    } else if (std.mem.startsWith(u8, url_slice, "ws://")) {
        offset = 5;
    }

    const remainder = url_slice[offset..];

    // Find path separator
    const path_idx = std.mem.indexOf(u8, remainder, "/") orelse remainder.len;
    const host_port = remainder[0..path_idx];

    // Find port separator
    if (std.mem.indexOf(u8, host_port, ":")) |colon_idx| {
        host = host_port[0..colon_idx];
        port_str = host_port[colon_idx + 1 ..];
    } else {
        host = host_port;
    }

    if (path_idx < remainder.len) {
        path = remainder[path_idx..];
    } else {
        path = "/";
    }

    return [3][]const u8{ host, port_str, path };
}

/// Base64 encode for WebSocket key
fn base64Encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const Encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, Encoder.calcSize(data.len));
    _ = Encoder.encode(encoded, data);
    return encoded;
}

/// Send WebSocket text frame
fn sendWsFrame(stream: std.net.Stream, allocator: std.mem.Allocator, message: []const u8) !void {
    _ = allocator; // Not used currently
    var frame_buf: [4096]u8 = undefined;
    var frame_len: usize = 0;

    // FIN + opcode (text = 0x1)
    frame_buf[frame_len] = 0x81;
    frame_len += 1;

    const len = message.len;
    if (len < 126) {
        frame_buf[frame_len] = @as(u8, @intCast(len));
        frame_len += 1;
    } else if (len < 65536) {
        frame_buf[frame_len] = 126;
        frame_len += 1;
        frame_buf[frame_len] = @as(u8, @intCast((len >> 8) & 0xFF));
        frame_len += 1;
        frame_buf[frame_len] = @as(u8, @intCast(len & 0xFF));
        frame_len += 1;
    } else {
        frame_buf[frame_len] = 127;
        frame_len += 1;
        var j: i32 = 56;
        while (j > 0) : (j -= 8) {
            frame_buf[frame_len] = @as(u8, @intCast((len >> @as(u5, @intCast(j))) & 0xFF));
            frame_len += 1;
        }
        frame_buf[frame_len] = @as(u8, @intCast(len & 0xFF));
        frame_len += 1;
    }

    @memcpy(frame_buf[frame_len..][0..message.len], message);
    frame_len += message.len;

    _ = try stream.writeAll(frame_buf[0..frame_len]);
}

/// WebSocket handshake
fn handshake(stream: std.net.Stream, allocator: std.mem.Allocator, host: []const u8, path: []const u8) !void {
    // Generate random key
    var key_bytes: [16]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    rng.random().bytes(&key_bytes);

    const key = try base64Encode(allocator, &key_bytes);
    defer allocator.free(key);

    // Build handshake request (static buffer to avoid ArrayList issues)
    var request_buf: [1024]u8 = undefined;
    var request_pos: usize = 0;

    var remaining = request_buf[request_pos..];
    var written = try std.fmt.bufPrint(remaining, "GET {s} HTTP/1.1\r\n", .{path});
    request_pos += written.len;

    remaining = request_buf[request_pos..];
    written = try std.fmt.bufPrint(remaining, "Host: {s}\r\n", .{host});
    request_pos += written.len;

    const upgrade_str = "Upgrade: websocket\r\n";
    @memcpy(request_buf[request_pos..][0..upgrade_str.len], upgrade_str);
    request_pos += upgrade_str.len;

    const conn_str = "Connection: Upgrade\r\n";
    @memcpy(request_buf[request_pos..][0..conn_str.len], conn_str);
    request_pos += conn_str.len;

    remaining = request_buf[request_pos..];
    written = try std.fmt.bufPrint(remaining, "Sec-WebSocket-Key: {s}\r\n", .{key});
    request_pos += written.len;

    const version_str = "Sec-WebSocket-Version: 13\r\n";
    @memcpy(request_buf[request_pos..][0..version_str.len], version_str);
    request_pos += version_str.len;

    const crlf = "\r\n";
    @memcpy(request_buf[request_pos..][0..crlf.len], crlf);
    request_pos += crlf.len;

    _ = try stream.writeAll(request_buf[0..request_pos]);

    // Read response (check for 101)
    var response_buf: [4096]u8 = undefined;
    const bytes_read = try stream.read(&response_buf);

    if (bytes_read == 0) return error.ConnectionClosed;

    const response = response_buf[0..bytes_read];
    if (!std.mem.containsAtLeast(u8, response, 1, "101")) {
        std.debug.print("[exo_ws] Handshake failed:\n{s}\n", .{response});
        return error.HandshakeFailed;
    }
}

/// Get subscription message for exchange
fn getSubscriptionMessage(exchange: Exchange) []const u8 {
    return switch (exchange) {
        .coinbase => "{\"type\":\"subscribe\",\"product_ids\":[\"BTC-USD\",\"ETH-USD\"],\"channels\":[\"match\"]}",
        .kraken => "{\"event\":\"subscribe\",\"pair\":[\"XBTUSDT\",\"ETHUSD\"],\"subscription\":{\"name\":\"trade\"}}",
        .lcx => "{\"event\":\"subscribe\",\"channel\":\"trades\",\"pair\":[\"BTC-USD\",\"ETH-USD\"]}",
    };
}

/// Thread entry point for reading WebSocket frames
fn readThreadEntry(allocator: std.mem.Allocator, stream: std.net.Stream, callback: TickCallback) void {
    readLoop(allocator, stream, callback);
}

/// Read WebSocket frames and parse messages
fn readLoop(allocator: std.mem.Allocator, stream: std.net.Stream, callback: TickCallback) void {
    var header_buf: [2]u8 = undefined;

    while (global_running.load(.acquire)) {
        // Read frame header
        const bytes_read = stream.read(&header_buf) catch |err| {
            std.debug.print("[exo_ws] Read error: {}\n", .{err});
            break;
        };

        if (bytes_read < 2) break;

        const opcode_byte = header_buf[0] & 0x0F;
        var payload_len: u64 = @intCast(header_buf[1] & 0x7F);

        // Convert opcode
        const opcode: WsFrameType = switch (opcode_byte) {
            0x0 => .continuation,
            0x1 => .text,
            0x2 => .binary,
            0x8 => .close,
            0x9 => .ping,
            0xA => .pong,
            else => break,
        };

        // Read extended payload length
        if (payload_len == 126) {
            var len_buf: [2]u8 = undefined;
            _ = stream.read(&len_buf) catch break;
            payload_len = (@as(u64, len_buf[0]) << 8) | @as(u64, len_buf[1]);
        } else if (payload_len == 127) {
            var len_buf: [8]u8 = undefined;
            _ = stream.read(&len_buf) catch break;
            var idx: u32 = 0;
            while (idx < 8) : (idx += 1) {
                payload_len = (payload_len << 8) | @as(u64, len_buf[idx]);
            }
        }

        // Read payload
        const payload = allocator.alloc(u8, payload_len) catch break;
        var total_read: u64 = 0;

        while (total_read < payload_len) {
            const read = stream.read(payload[total_read..]) catch {
                allocator.free(payload);
                return;
            };
            if (read == 0) {
                allocator.free(payload);
                return;
            }
            total_read += read;
        }

        // Handle frame
        switch (opcode) {
            .text => {
                // Parse exchange-specific message
                switch (global_exchange) {
                    .coinbase => {
                        if ((coinbase.parseMatch(allocator, payload) catch null)) |match| {
                            const tick = coinbase.matchToTick(match);
                            callback(&tick);
                            match.deinit();
                        }
                    },
                    .kraken => {
                        if ((kraken.parseTrade(allocator, payload) catch null)) |trade| {
                            const tick = kraken.tradeToTick(trade);
                            callback(&tick);
                            trade.deinit();
                        }
                    },
                    .lcx => {
                        if ((lcx.parseTrade(allocator, payload) catch null)) |trade| {
                            const tick = lcx.tradeToTick(trade);
                            callback(&tick);
                            trade.deinit();
                        }
                    },
                }
                allocator.free(payload);
            },
            .close => {
                allocator.free(payload);
                global_running.store(false, .release);
                break;
            },
            else => {
                allocator.free(payload);
            },
        }
    }
}

export fn exo_ws_connect(url: [*:0]const u8) i32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse URL
    const parts = parseUrl(allocator, url) catch {
        std.debug.print("[exo_ws] Failed to parse URL\n", .{});
        return -1;
    };

    const host = parts[0];
    const port_str = parts[1];
    const path = parts[2];

    // Parse port
    const port = std.fmt.parseInt(u16, port_str, 10) catch 443;

    std.debug.print("[exo_ws] Connecting to {s}:{d}{s}\n", .{ host, port, path });

    // Create TCP socket and connect
    const address = std.net.Address.resolveIp(host, port) catch |err| {
        std.debug.print("[exo_ws] Failed to resolve {s}: {}\n", .{ host, err });
        return -1;
    };

    // Create socket file descriptor
    const socket_flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC;
    const socket_fd = std.posix.socket(address.any.family, socket_flags, std.posix.IPPROTO.TCP) catch |err| {
        std.debug.print("[exo_ws] Failed to create socket: {}\n", .{err});
        return -1;
    };

    // Connect to address
    std.posix.connect(socket_fd, &address.any, address.getOsSockLen()) catch |err| {
        std.debug.print("[exo_ws] Failed to connect: {}\n", .{err});
        std.posix.close(socket_fd);
        return -1;
    };

    const stream = std.net.Stream{ .handle = socket_fd };

    global_stream = stream;

    // WebSocket handshake
    handshake(stream, allocator, host, path) catch |err| {
        std.debug.print("[exo_ws] Handshake failed: {}\n", .{err});
        stream.close();
        return -1;
    };

    std.debug.print("[exo_ws] Connected successfully\n", .{});
    return 0;
}

export fn exo_ws_set_exchange(exchange_id: u32) i32 {
    if (exchange_id > 2) return -1;
    global_exchange = @enumFromInt(exchange_id);
    std.debug.print("[exo_ws] Exchange set to: {d}\n", .{exchange_id});
    return 0;
}

export fn exo_ws_start_streaming(_callback: ?TickCallback) i32 {
    if (_callback == null or global_stream == null) return -1;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    global_callback = _callback;
    global_allocator = allocator;
    global_running.store(true, .release);

    // Send subscription as WebSocket frame (exchange-specific)
    const subscribe_msg = getSubscriptionMessage(global_exchange);
    if (global_stream) |stream| {
        sendWsFrame(stream, allocator, subscribe_msg) catch |err| {
            std.debug.print("[exo_ws] Failed to send subscription: {}\n", .{err});
            return -1;
        };
    }

    // Spawn background thread for read loop
    const thread = std.Thread.spawn(.{}, readThreadEntry, .{ allocator, global_stream.?, _callback.? }) catch |err| {
        std.debug.print("[exo_ws] Failed to spawn thread: {}\n", .{err});
        return -1;
    };

    global_thread = thread;
    std.debug.print("[exo_ws] Streaming started in background thread\n", .{});
    return 0;
}

export fn exo_ws_stop() void {
    global_running.store(false, .release);

    // Wait for thread to finish if spawned
    if (global_thread) |thread| {
        thread.join();
        global_thread = null;
    }

    // Close socket
    if (global_stream) |stream| {
        stream.close();
        global_stream = null;
    }
}

export fn exo_ws_get_status() i32 {
    return if (global_running.load(.acquire)) 1 else 0;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n✓ ExoGridChart Zig WebSocket - REAL DATA READY\n\n", .{});

    const json = "{\"type\":\"match\",\"side\":\"buy\",\"product_id\":\"BTC-USD\"}";
    if (try coinbase.parseMatch(allocator, json)) |match| {
        const tick = coinbase.matchToTick(match);
        std.debug.print("✓ Tick: {s} price={d} size={d}\n\n", .{match.product_id, tick.price, tick.size});
        match.deinit();
    }
}
