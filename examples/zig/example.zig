/// ExoGridChart Zig SDK Example
/// Demonstrates how to use ExoGridChart as a Zig library
///
/// Run: zig build && ./zig-out/bin/example

const std = @import("std");
const exogrid = @import("../../sdk/zig/exogrid.zig");

// Global tick counter
var tick_count: u64 = 0;

/// Callback invoked on each new tick
fn onTick(tick_opt: ?*const exogrid.Tick) void {
    if (tick_opt) |tick| {
        tick_count += 1;

        // Print every 100th tick to avoid spam
        if (tick_count % 100 == 0) {
            std.debug.print(
                "[Tick #{d}] Exchange: {d} | Price: {d:.2} | Size: {d:.8}\n",
                .{ tick_count, tick.exchange_id, tick.price, tick.size },
            );
        }
    }
}

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("ExoGridChart Zig SDK Example\n", .{});
    std.debug.print("============================\n\n", .{});

    // Create aggregator
    var aggregator = exogrid.ParallelAggregator.init(allocator);
    defer aggregator.deinit();

    std.debug.print("Starting streams from all 3 exchanges...\n", .{});

    // Start streaming (0x7 = all 3: Coinbase, Kraken, LCX)
    try aggregator.start(0x7, &onTick);

    std.debug.print("Streaming for 10 seconds...\n\n", .{});

    // Let it stream for 10 seconds
    std.time.sleep(10 * std.time.ns_per_s);

    std.debug.print("\n", .{});
    std.debug.print("============================\n", .{});
    std.debug.print("Received {d} ticks total\n", .{tick_count});
    std.debug.print("Stopping streams...\n", .{});

    aggregator.stop();

    std.debug.print("Done!\n", .{});
}
