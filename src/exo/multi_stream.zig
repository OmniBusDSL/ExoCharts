const std = @import("std");
const exo_ws = @import("exo_ws.zig");

/// Multi-exchange stream manager
/// Spawns up to 3 WebSocket connections (one per exchange)
/// Routes all ticks to single aggregator callback

pub const MultiStream = struct {
    allocator: std.mem.Allocator,
    active_exchanges: u32 = 0, // Bitmask: bit 0=Coinbase, 1=Kraken, 2=LCX
    callback: ?exo_ws.TickCallback = null,
    thread_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) MultiStream {
        return MultiStream{
            .allocator = allocator,
        };
    }

    /// Start streaming from multiple exchanges in parallel
    /// exchanges: bitmask (0x1=Coinbase, 0x2=Kraken, 0x4=LCX)
    /// Example: 0x3 = Coinbase + Kraken
    pub fn start(self: *MultiStream, exchanges: u32, callback: exo_ws.TickCallback) !void {
        if (exchanges == 0 or exchanges > 0x7) return error.InvalidExchangeMask;

        self.active_exchanges = exchanges;
        self.callback = callback;
        self.thread_count = 0;

        // Spawn thread for each exchange
        if ((exchanges & 0x1) != 0) {
            // Coinbase
            exo_ws.exo_ws_set_exchange(0);
            exo_ws.exo_ws_connect("wss://ws-feed.exchange.coinbase.com");
            if (exo_ws.exo_ws_start_streaming(callback) == 0) {
                self.thread_count += 1;
                std.debug.print("[multi_stream] Coinbase streaming started\n", .{});
            }
        }

        if ((exchanges & 0x2) != 0) {
            // Kraken
            exo_ws.exo_ws_set_exchange(1);
            exo_ws.exo_ws_connect("wss://ws.kraken.com");
            if (exo_ws.exo_ws_start_streaming(callback) == 0) {
                self.thread_count += 1;
                std.debug.print("[multi_stream] Kraken streaming started\n", .{});
            }
        }

        if ((exchanges & 0x4) != 0) {
            // LCX
            exo_ws.exo_ws_set_exchange(2);
            exo_ws.exo_ws_connect("wss://stream.production.lcx.ch");
            if (exo_ws.exo_ws_start_streaming(callback) == 0) {
                self.thread_count += 1;
                std.debug.print("[multi_stream] LCX streaming started\n", .{});
            }
        }

        std.debug.print("[multi_stream] {d} exchange(s) streaming\n", .{self.thread_count});
    }

    pub fn stop(self: *MultiStream) void {
        exo_ws.exo_ws_stop();
        std.debug.print("[multi_stream] All streams stopped\n", .{});
    }

    pub fn get_status(self: *MultiStream) i32 {
        return exo_ws.exo_ws_get_status();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var multi = MultiStream.init(allocator);

    std.debug.print("✓ Multi-stream aggregator ready\n", .{});
    std.debug.print("  Supports: 0x1=Coinbase, 0x2=Kraken, 0x4=LCX\n", .{});
    std.debug.print("  Example: 0x3 = Coinbase + Kraken\n", .{});

    // Demo: show initialization
    std.debug.print("\nInitialized for: {d} exchanges\n", .{multi.thread_count});
}
