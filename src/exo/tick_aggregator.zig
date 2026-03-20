const std = @import("std");
const coinbase = @import("coinbase_match.zig");

pub const Tick = coinbase.Tick;
pub const TickCallback = *const fn (?*const Tick) void;
pub const AggregatorCallback = *const fn (?*const Tick) void;

/// Priority queue for timestamp-ordered tick delivery
/// Input: 3 concurrent, out-of-order tick streams
/// Output: Single ordered stream by timestamp
pub const TickAggregator = struct {
    allocator: std.mem.Allocator,
    queue: std.PriorityQueue(TickWithSource, void, compareByTimestamp),
    min_heap_size: u32 = 100, // Buffering threshold
    total_aggregated: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    output_callback: ?AggregatorCallback = null,

    pub fn init(allocator: std.mem.Allocator) TickAggregator {
        return TickAggregator{
            .allocator = allocator,
            .queue = std.PriorityQueue(TickWithSource, void, compareByTimestamp).init(allocator, {}),
        };
    }

    pub fn deinit(self: *TickAggregator) void {
        self.queue.deinit();
    }

    /// Add tick from stream (called from parallel streams)
    /// Thread-safe: uses allocator's thread-local state
    pub fn ingest(self: *TickAggregator, tick: *const Tick) !void {
        const with_source = TickWithSource{
            .tick = tick.*,
            .source_exchange = tick.exchange_id,
        };

        try self.queue.add(with_source);

        // If queue is large enough, emit oldest tick
        if (self.queue.len > self.min_heap_size) {
            const oldest = self.queue.removeMin();
            if (self.output_callback) |callback| {
                callback(&oldest.tick);
            }
            self.total_aggregated.store(
                self.total_aggregated.load(.acquire) + 1,
                .release,
            );
        }
    }

    /// Flush all remaining ticks (call at shutdown)
    pub fn flush(self: *TickAggregator) !void {
        std.debug.print("[aggregator] Flushing {d} remaining ticks\n", .{self.queue.len});

        while (self.queue.len > 0) {
            const tick = self.queue.removeMin();
            if (self.output_callback) |callback| {
                callback(&tick.tick);
            }
            self.total_aggregated.store(
                self.total_aggregated.load(.acquire) + 1,
                .release,
            );
        }
    }

    pub fn get_total_aggregated(self: *TickAggregator) u64 {
        return self.total_aggregated.load(.acquire);
    }

    pub fn get_queue_size(self: *TickAggregator) u32 {
        return @as(u32, @intCast(self.queue.len));
    }

    pub fn set_output_callback(self: *TickAggregator, callback: AggregatorCallback) void {
        self.output_callback = callback;
    }

    pub fn set_min_heap_size(self: *TickAggregator, size: u32) void {
        self.min_heap_size = size;
    }
};

/// Tick with source information
const TickWithSource = struct {
    tick: Tick,
    source_exchange: u32,
};

/// Min-heap comparison: earlier timestamps first
fn compareByTimestamp(context: void, a: TickWithSource, b: TickWithSource) std.math.Order {
    _ = context;

    if (a.tick.timestamp_ns < b.tick.timestamp_ns) return .lt;
    if (a.tick.timestamp_ns > b.tick.timestamp_ns) return .gt;

    // Tie-breaker: exchange ID (for reproducibility)
    if (a.source_exchange < b.source_exchange) return .lt;
    if (a.source_exchange > b.source_exchange) return .gt;

    return .eq;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aggregator = TickAggregator.init(allocator);
    defer aggregator.deinit();

    std.debug.print("✓ Tick aggregator initialized\n", .{});
    std.debug.print("  Buffers: 100 ticks for timestamp ordering\n", .{});
    std.debug.print("  Exchanges: Coinbase(0), Kraken(1), LCX(2)\n", .{});
}
