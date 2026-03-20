const std = @import("std");
const stream_inst = @import("stream_instance.zig");

pub const Tick = stream_inst.Tick;
pub const TickCallback = stream_inst.TickCallback;
pub const Exchange = stream_inst.Exchange;
pub const StreamInstance = stream_inst.StreamInstance;

/// Parallel stream aggregator
/// Manages multiple independent WebSocket connections
/// Routes all ticks from all exchanges to single callback
pub const ParallelAggregator = struct {
    allocator: std.mem.Allocator,
    coinbase_stream: ?StreamInstance = null,
    kraken_stream: ?StreamInstance = null,
    lcx_stream: ?StreamInstance = null,
    tick_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub fn init(allocator: std.mem.Allocator) ParallelAggregator {
        return ParallelAggregator{
            .allocator = allocator,
        };
    }

    /// Start streaming from selected exchanges in parallel
    /// exchanges: bitmask (0x1=Coinbase, 0x2=Kraken, 0x4=LCX)
    pub fn start(self: *ParallelAggregator, exchanges: u32, callback: TickCallback) !void {
        std.debug.print("[aggregator] Starting parallel streams (mask=0x{x})\n", .{exchanges});

        // Coinbase
        if ((exchanges & 0x1) != 0) {
            var stream = StreamInstance.init(self.allocator, .coinbase);
            try stream.connect("wss://ws-feed.exchange.coinbase.com");
            self.coinbase_stream = stream;
            try self.coinbase_stream.?.start(callback);
        }

        // Kraken
        if ((exchanges & 0x2) != 0) {
            var stream = StreamInstance.init(self.allocator, .kraken);
            try stream.connect("wss://ws.kraken.com");
            self.kraken_stream = stream;
            try self.kraken_stream.?.start(callback);
        }

        // LCX
        if ((exchanges & 0x4) != 0) {
            var stream = StreamInstance.init(self.allocator, .lcx);
            try stream.connect("wss://exchange-api.lcx.com/ws");
            self.lcx_stream = stream;
            try self.lcx_stream.?.start(callback);
        }

        std.debug.print("[aggregator] All selected streams started\n", .{});
    }

    pub fn stop(self: *ParallelAggregator) void {
        std.debug.print("[aggregator] Stopping all streams...\n", .{});

        if (self.coinbase_stream) |*stream| {
            stream.deinit();
            self.coinbase_stream = null;
        }

        if (self.kraken_stream) |*stream| {
            stream.deinit();
            self.kraken_stream = null;
        }

        if (self.lcx_stream) |*stream| {
            stream.deinit();
            self.lcx_stream = null;
        }

        std.debug.print("[aggregator] All streams stopped\n", .{});
    }

    pub fn deinit(self: *ParallelAggregator) void {
        self.stop();
    }

    pub fn get_tick_count(self: *ParallelAggregator) u64 {
        return self.tick_count.load(.acquire);
    }

    pub fn increment_tick_count(self: *ParallelAggregator) void {
        var count = self.tick_count.load(.acquire);
        count += 1;
        self.tick_count.store(count, .release);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aggregator = ParallelAggregator.init(allocator);
    defer aggregator.deinit();

    std.debug.print("✓ Parallel aggregator initialized\n", .{});
    std.debug.print("  Ready to start multi-exchange streaming\n", .{});
}
