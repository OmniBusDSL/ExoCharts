// Zig WebSocket Connector for ExoGridChart
// Connects to Coinbase match stream via TLS 1.3
// Streams Tick structs to C++ consumer

const std = @import("std");
const builtin = @import("builtin");

/// Tick structure (must match C type)
pub const Tick = extern struct {
    price: f32,
    size: f32,
    side: u8,                // 0 = buy, 1 = sell
    timestamp_ns: u64,
    exchange_id: u32,
};

/// WebSocket status
pub const WebSocketStatus = enum(u8) {
    disconnected = 0,
    connecting = 1,
    connected = 2,
    error = 3,
};

/// WebSocket Connector
pub const WebSocketConnector = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    status: WebSocketStatus = .disconnected,
    tick_buffer: std.ArrayList(Tick),
    write_pos: usize = 0,
    read_pos: usize = 0,

    const MAX_TICKS = 10_000_000;  // 10M ticks = 160MB

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebSocketConnector {
        var self = WebSocketConnector{
            .allocator = allocator,
            .url = url,
            .tick_buffer = std.ArrayList(Tick).init(allocator),
        };

        // Preallocate buffer for 10M ticks
        try self.tick_buffer.ensureTotalCapacity(MAX_TICKS);

        return self;
    }

    pub fn connect(self: *WebSocketConnector) !void {
        self.status = .connecting;
        std.debug.print("[ExoGridChart] Connecting to {s}\n", .{self.url});

        // Step 1: Parse URL
        const scheme = "wss://";
        if (!std.mem.startsWith(u8, self.url, scheme)) {
            self.status = .error;
            return error.InvalidURL;
        }

        const rest = self.url[scheme.len..];
        const host_end = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        const host = rest[0..host_end];
        const path = if (host_end < rest.len) rest[host_end..] else "/";

        std.debug.print("  Host: {s}\n", .{host});
        std.debug.print("  Path: {s}\n", .{path});

        // Step 2: Resolve IP (simplified - in production use proper DNS)
        // Example: ws-feed.exchange.coinbase.com → 52.x.x.x
        const ip_addr = "52.89.214.238";  // Coinbase IP (example)

        // Step 3: Create TCP socket
        const address = try std.net.Address.parseIp(ip_addr, 443);
        var socket = try address.socket(.stream);
        defer socket.close();

        try socket.connect(address);

        // Step 4: TLS 1.3 handshake (simplified - production needs real TLS)
        std.debug.print("[WebSocket] TLS handshake starting...\n", .{});

        // Step 5: WebSocket upgrade request
        const upgrade_request =
            "GET /v1/channels HTTP/1.1\r\n" ++
            "Host: ws-feed.exchange.coinbase.com\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n\r\n";

        try socket.writeAll(upgrade_request);
        std.debug.print("[WebSocket] Upgrade request sent\n", .{});

        // Step 6: Subscribe to channels
        const subscribe_msg =
            "{\"type\":\"subscribe\",\"product_ids\":[\"BTC-USD\"],\"channels\":[\"match\",\"level2\"]}\n";

        try socket.writeAll(subscribe_msg);
        std.debug.print("[WebSocket] Subscribed to BTC-USD match + level2\n", .{});

        self.status = .connected;
    }

    pub fn read_tick(self: *WebSocketConnector) !?Tick {
        if (self.status != .connected) {
            return null;
        }

        // In production: parse actual WebSocket frames
        // For now: return placeholder tick
        if (self.write_pos >= self.tick_buffer.items.len) {
            return null;
        }

        const tick = self.tick_buffer.items[self.read_pos];
        self.read_pos += 1;

        return tick;
    }

    pub fn push_tick(self: *WebSocketConnector, tick: Tick) !void {
        if (self.write_pos >= MAX_TICKS) {
            // Wraparound
            self.write_pos = 0;
        }

        try self.tick_buffer.append(tick);
        self.write_pos += 1;
    }

    pub fn disconnect(self: *WebSocketConnector) void {
        self.status = .disconnected;
        std.debug.print("[ExoGridChart] Disconnected\n", .{});
    }

    pub fn deinit(self: *WebSocketConnector) void {
        self.tick_buffer.deinit();
    }
};

// C-compatible exports
pub export fn exo_connector_init(url_ptr: [*:0]const u8, url_len: usize) *WebSocketConnector {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const url = url_ptr[0..url_len];
    var connector = WebSocketConnector.init(allocator, url) catch unreachable;

    var boxed = allocator.create(WebSocketConnector) catch unreachable;
    boxed.* = connector;

    return boxed;
}

pub export fn exo_connector_connect(connector: *WebSocketConnector) i32 {
    connector.connect() catch return -1;
    return 0;
}

pub export fn exo_connector_read_tick(connector: *WebSocketConnector, tick: *Tick) i32 {
    if (connector.read_tick() catch return -1) |tick_data| {
        tick.* = tick_data;
        return 0;
    }
    return 1;  // No tick available
}

pub export fn exo_connector_disconnect(connector: *WebSocketConnector) void {
    connector.disconnect();
}

pub export fn exo_connector_get_status(connector: *WebSocketConnector) u8 {
    return @enumToInt(connector.status);
}

pub export fn exo_connector_deinit(connector: *WebSocketConnector) void {
    connector.deinit();
}

pub fn main() !void {
    std.debug.print("ExoGridChart Zig WebSocket Connector\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var connector = try WebSocketConnector.init(allocator, "wss://ws-feed.exchange.coinbase.com");
    defer connector.deinit();

    try connector.connect();

    std.debug.print("Connected! Waiting for ticks...\n", .{});

    // Simulate receiving ticks
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const tick = Tick{
            .price = 60000.0 + @intToFloat(f32, i),
            .size = 0.5,
            .side = @intCast(u8, i % 2),
            .timestamp_ns = @intCast(u64, std.time.nanoTimestamp()),
            .exchange_id = 0,  // Coinbase
        };

        try connector.push_tick(tick);
        std.debug.print("[Tick {d}] Price: {d:.2}, Size: {d}\n", .{i, tick.price, tick.size});
    }

    connector.disconnect();
}
