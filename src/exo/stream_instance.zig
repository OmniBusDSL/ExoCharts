const std = @import("std");
const coinbase = @import("coinbase_match.zig");
const kraken = @import("kraken_match.zig");
const lcx = @import("lcx_match.zig");
const ws_types = @import("ws_types.zig");
const tls = @import("tls.zig");

pub const Tick = coinbase.Tick;
pub const TickCallback = *const fn (?*const Tick) void;

pub const Exchange = enum(u32) {
    coinbase = 0,
    kraken = 1,
    lcx = 2,
};

const WsFrameType = ws_types.WsFrameType;

/// Independent WebSocket stream instance (allows parallel connections)
pub const StreamInstance = struct {
    allocator: std.mem.Allocator,
    exchange: Exchange,
    stream: ?std.net.Stream = null,
    tls_ctx: ?tls.TlsContext = null,
    callback: ?TickCallback = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    is_wss: bool = false,
    ws_path: []const u8 = "/",

    pub fn init(allocator: std.mem.Allocator, exchange: Exchange) StreamInstance {
        return StreamInstance{
            .allocator = allocator,
            .exchange = exchange,
        };
    }

    fn parseUrl(url: [*:0]const u8) ![3][]const u8 {
        const url_slice = std.mem.sliceTo(url, 0);
        var host: []const u8 = "";
        var port_str: []const u8 = "443";
        var path: []const u8 = "";

        var offset: usize = 0;
        if (std.mem.startsWith(u8, url_slice, "wss://")) {
            offset = 6;
        } else if (std.mem.startsWith(u8, url_slice, "ws://")) {
            offset = 5;
        }

        const remainder = url_slice[offset..];
        const path_idx = std.mem.indexOf(u8, remainder, "/") orelse remainder.len;
        const host_port = remainder[0..path_idx];

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

    fn getSubscriptionMessage(self: *StreamInstance) []const u8 {
        return switch (self.exchange) {
            // Coinbase: matches the official API format
            .coinbase => "{\"type\":\"subscribe\",\"product_ids\":[\"BTC-USD\",\"ETH-USD\"],\"channels\":[\"matches\"]}",
            // Kraken: XBTUSD not XBTUSDT (no ETHUSD, use ETHUSD or skip)
            .kraken => "{\"event\":\"subscribe\",\"pair\":[\"XBT/USD\",\"ETH/USD\"],\"subscription\":{\"name\":\"trade\"}}",
            // LCX: correct format from Zig-toolz-Assembly reference implementation
            .lcx => "{\"Topic\":\"subscribe\",\"Type\":\"ticker\"}",
        };
    }

    /// Send data (auto-routes through TLS if WSS)
    fn sendData(self: *StreamInstance, data: []const u8) !usize {
        // Try TLS first if available (Coinbase, Kraken)
        if (self.tls_ctx) |*ctx| {
            return try ctx.send(data);
        }
        // Fall back to raw socket (LCX raw mode or non-TLS)
        if (self.stream) |stream| {
            try stream.writeAll(data);
            return data.len;
        }
        return error.NotConnected;
    }

    /// Receive data (auto-routes through TLS if available)
    fn recvData(self: *StreamInstance, buffer: []u8) !usize {
        // Try TLS first if available (Coinbase, Kraken)
        if (self.tls_ctx) |*ctx| {
            return try ctx.recv(buffer);
        }
        // Fall back to raw socket (LCX raw mode or non-TLS)
        if (self.stream) |stream| {
            return try stream.read(buffer);
        }
        return error.NotConnected;
    }

    pub fn connect(self: *StreamInstance, url: [*:0]const u8) !void {
        const url_str = std.mem.sliceTo(url, 0);
        self.is_wss = std.mem.startsWith(u8, url_str, "wss://");

        const parts = try parseUrl(url);
        const host = parts[0];
        const port_str = parts[1];
        const path = parts[2];
        self.ws_path = if (path.len > 0) path else "/";

        const port = std.fmt.parseInt(u16, port_str, 10) catch 443;

        // Resolve hostname via C library getaddrinfo
        var hints: std.c.addrinfo = undefined;
        @memset(std.mem.asBytes(&hints), 0);
        hints.family = std.posix.AF.INET;
        hints.socktype = std.posix.SOCK.STREAM;
        hints.protocol = 0;  // Let system choose

        var result_ptr: ?*std.c.addrinfo = null;
        const port_z = try self.allocator.dupeZ(u8, port_str);
        defer self.allocator.free(port_z);

        const host_z = try self.allocator.dupeZ(u8, host);
        defer self.allocator.free(host_z);

        const gai_res = std.c.getaddrinfo(host_z, port_z, &hints, &result_ptr);
        const gai_ok: c_int = 0;
        if (@intFromEnum(gai_res) != gai_ok) {
            std.debug.print("[stream] DNS resolution failed for {s}\n", .{host});
            return error.HostNameResolutionFailed;
        }
        defer if (result_ptr) |p| std.c.freeaddrinfo(p);

        if (result_ptr) |res| {
            const address = std.net.Address.initPosix(@as(*align(4) const std.posix.sockaddr, @ptrCast(@alignCast(res.addr))));
            const socket_fd = try std.posix.socket(address.any.family, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, std.posix.IPPROTO.TCP);

            try std.posix.connect(socket_fd, &address.any, address.getOsSockLen());

            self.stream = std.net.Stream{ .handle = socket_fd };

            // All three exchanges (Coinbase, Kraken, LCX) use TLS with WSS
            if (self.is_wss) {
                var tls_ctx = try tls.TlsContext.init(self.allocator);
                try tls_ctx.connectWss(socket_fd, host_z);
                self.tls_ctx = tls_ctx;
                std.debug.print("[stream] TLS handshake complete (TLS 1.2+)\n", .{});

                // Send WebSocket HTTP upgrade request
                try self.sendWebSocketUpgrade(host);
                std.debug.print("[stream] WSS connected to {s}:{d}\n", .{ host, port });
            } else {
                // For non-TLS, also send WebSocket upgrade
                try self.sendWebSocketUpgrade(host);
                std.debug.print("[stream] WS connected to {s}:{d}\n", .{ host, port });
            }
        } else {
            return error.HostNameResolutionFailed;
        }
    }

    /// Send WebSocket HTTP upgrade request and wait for 101 response
    fn sendWebSocketUpgrade(self: *StreamInstance, host: []const u8) !void {
        const sec_key = "dGhlIHNhbXBsZSBub25jZQ=="; // Static key for simplicity

        // Use path from URL if provided, otherwise default to "/"
        const path = self.ws_path;

        var buf: [512]u8 = undefined;
        const request = try std.fmt.bufPrint(&buf,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "User-Agent: ExoGridChart/2.1\r\n" ++
            "\r\n",
            .{ path, host, sec_key }
        );

        _ = try self.sendData(request);

        // Wait for HTTP response (101 Switching Protocols or 301 redirect)
        var response_buf: [1024]u8 = undefined;
        const response_len = try self.recvData(&response_buf);

        if (response_len < 12) {
            std.debug.print("[stream] WebSocket upgrade failed: response too short\n", .{});
            return error.WebSocketUpgradeFailed;
        }

        // Check for "101" in response
        if (std.mem.containsAtLeast(u8, response_buf[0..response_len], 1, "101")) {
            std.debug.print("[stream] WebSocket upgrade successful (101 Switching Protocols)\n", .{});
            return; // Success
        }

        // Check for 301/302 redirect
        if (std.mem.containsAtLeast(u8, response_buf[0..response_len], 1, "301") or
            std.mem.containsAtLeast(u8, response_buf[0..response_len], 1, "302")) {
            std.debug.print("[stream] WebSocket received redirect (301/302), trying alternative paths\n", .{});

            // Try common paths for LCX
            const paths = [_][]const u8{ "/ws", "/websocket", "/ws/", "/stream" };
            for (paths) |alt_path| {
                var buf2: [512]u8 = undefined;
                const request2 = try std.fmt.bufPrint(&buf2,
                    "GET {s} HTTP/1.1\r\n" ++
                    "Host: {s}\r\n" ++
                    "Upgrade: websocket\r\n" ++
                    "Connection: Upgrade\r\n" ++
                    "Sec-WebSocket-Key: {s}\r\n" ++
                    "Sec-WebSocket-Version: 13\r\n" ++
                    "User-Agent: ExoGridChart/2.1\r\n" ++
                    "\r\n",
                    .{ alt_path, host, sec_key }
                );
                _ = try self.sendData(request2);
                const response_len2 = try self.recvData(&response_buf);
                if (std.mem.containsAtLeast(u8, response_buf[0..response_len2], 1, "101")) {
                    std.debug.print("[stream] WebSocket upgrade successful with {s} path (101 Switching Protocols)\n", .{alt_path});
                    return;
                }
            }
        }

        // All attempts failed - show full response for debugging
        std.debug.print("[stream] WebSocket upgrade failed: no 101 status\n", .{});
        std.debug.print("[stream] Response ({d} bytes) - Full Content:\n{s}\n", .{ response_len, response_buf[0..@min(response_len, 512)] });
        return error.WebSocketUpgradeFailed;
    }

    pub fn start(self: *StreamInstance, callback: TickCallback) !void {
        if (self.stream == null) return error.NotConnected;

        self.callback = callback;
        self.running.store(true, .release);

        // Send subscription with proper WebSocket masking (RFC 6455)
        const sub_msg = self.getSubscriptionMessage();
        const mask_key = "\x00\x00\x00\x00"; // Static mask for simplicity (all zeros)

        var frame: [4096]u8 = undefined;
        frame[0] = 0x81; // FIN=1, Opcode=1 (text)
        frame[1] = 0x80 | @as(u8, @intCast(sub_msg.len)); // MASK=1, payload length
        @memcpy(frame[2..6], mask_key);

        // XOR payload with mask key (when mask is all zeros, payload unchanged)
        @memcpy(frame[6..][0..sub_msg.len], sub_msg);

        const frame_len = 6 + sub_msg.len;

        std.debug.print("[stream] Sending subscription message ({d} bytes with MASK) to exchange={d}\n", .{ frame_len, @intFromEnum(self.exchange) });
        _ = try self.sendData(frame[0..frame_len]);
        std.debug.print("[stream] Subscription sent successfully\n", .{});

        // Spawn read thread
        const thread = try std.Thread.spawn(.{}, StreamInstance.readLoop, .{ self, self.allocator, callback });
        self.thread = thread;

        std.debug.print("[stream] Streaming started (exchange={d})\n", .{@intFromEnum(self.exchange)});
    }

    fn readLoop(self: *StreamInstance, allocator: std.mem.Allocator, callback: TickCallback) void {
        std.debug.print("[readLoop] Starting for exchange={d}\n", .{@intFromEnum(self.exchange)});
        var header_buf: [2]u8 = undefined;
        var frame_count: u64 = 0;

        while (self.running.load(.acquire)) {
            const bytes_read = self.recvData(&header_buf) catch |err| {
                std.debug.print("[readLoop] recvData error: {} (exchange={d})\n", .{ err, @intFromEnum(self.exchange) });
                break;
            };

            if (bytes_read < 2) {
                std.debug.print("[readLoop] Received {d} bytes (< 2), closing (exchange={d})\n", .{ bytes_read, @intFromEnum(self.exchange) });
                break;
            }

            frame_count += 1;
            if (frame_count <= 3 or frame_count % 100 == 0) {
                std.debug.print("[readLoop] Frame {d}: opcode_byte=0x{x:0>2} len_byte=0x{x:0>2} (exchange={d})\n", .{ frame_count, header_buf[0] & 0x0F, header_buf[1] & 0x7F, @intFromEnum(self.exchange) });
            }

            const opcode_byte = header_buf[0] & 0x0F;
            var payload_len: u64 = @intCast(header_buf[1] & 0x7F);

            const opcode: WsFrameType = switch (opcode_byte) {
                0x0 => .continuation,
                0x1 => .text,
                0x2 => .binary,
                0x8 => .close,
                0x9 => .ping,
                0xA => .pong,
                else => break,
            };

            if (payload_len == 126) {
                var len_buf: [2]u8 = undefined;
                _ = self.recvData(&len_buf) catch break;
                payload_len = (@as(u64, len_buf[0]) << 8) | @as(u64, len_buf[1]);
            } else if (payload_len == 127) {
                var len_buf: [8]u8 = undefined;
                _ = self.recvData(&len_buf) catch break;
                var idx: u32 = 0;
                while (idx < 8) : (idx += 1) {
                    payload_len = (payload_len << 8) | @as(u64, len_buf[idx]);
                }
            }

            const payload = allocator.alloc(u8, payload_len) catch break;
            var total_read: u64 = 0;

            while (total_read < payload_len) {
                const read = self.recvData(payload[total_read..]) catch {
                    allocator.free(payload);
                    return;
                };
                if (read == 0) {
                    allocator.free(payload);
                    return;
                }
                total_read += read;
            }

            switch (opcode) {
                .text => {
                    // Log first text frames for debugging subscriptions
                    if (frame_count <= 3) {
                        const payload_str = if (payload.len < 300) payload else payload[0..300];
                        std.debug.print("[readLoop] TEXT frame: {d} bytes: {s}\n", .{ payload.len, payload_str });
                    }

                    switch (self.exchange) {
                        .coinbase => {
                            if ((coinbase.parseMatch(allocator, payload) catch null)) |match| {
                                const tick = coinbase.matchToTick(match);
                                callback(&tick);
                                match.deinit();
                            }
                        },
                        .kraken => {
                            // Debug: show what Kraken is sending (first few frames)
                            if (frame_count <= 15) {
                                const preview = if (payload.len < 120) payload else payload[0..120];
                                std.debug.print("[readLoop] Kraken frame {d}: {s}\n", .{frame_count, preview});
                            }
                            if ((kraken.parseTrade(allocator, payload) catch null)) |trade| {
                                const tick = kraken.tradeToTick(trade);
                                std.debug.print("[readLoop] Kraken TRADE: {s} ${d}\n", .{trade.pair, @as(i32, @intFromFloat(trade.price))});
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
                    std.debug.print("[readLoop] CLOSE frame from exchange={d}: {d} bytes\n", .{ @intFromEnum(self.exchange), payload.len });
                    if (payload.len >= 2) {
                        const code = (@as(u16, payload[0]) << 8) | @as(u16, payload[1]);
                        const reason = if (payload.len > 2) payload[2..] else "";
                        std.debug.print("[readLoop] Close code: {d}, reason: {s}\n", .{ code, reason });
                    }
                    allocator.free(payload);
                    self.running.store(false, .release);
                    break;
                },
                else => {
                    allocator.free(payload);
                },
            }
        }
    }

    pub fn stop(self: *StreamInstance) void {
        self.running.store(false, .release);

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }

        std.debug.print("[stream] Stopped (exchange={d})\n", .{@intFromEnum(self.exchange)});
    }

    pub fn deinit(self: *StreamInstance) void {
        self.stop();
    }
};
