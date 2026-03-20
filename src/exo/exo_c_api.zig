/// C API for ExoGridChart SDK
/// Exports Zig functions with C calling convention for use from C/C++/Python/etc.
///
/// Usage from C:
///   #include "exogrid.h"
///   ExoInitResult res = exo_init();
///   exo_start(0x7, &my_tick_callback);
///   // ... process ticks ...
///   exo_stop();

const std = @import("std");
const parallel_aggregator = @import("parallel_aggregator.zig");
const market_matrix = @import("market_matrix.zig");
const ticker_matrix = @import("ticker_matrix.zig");

// Re-export types for C
pub const Tick = market_matrix.Tick;
pub const TickCallback = parallel_aggregator.TickCallback;
pub const Exchange = parallel_aggregator.Exchange;

// Global SDK state
var gpa: ?std.heap.GeneralPurposeAllocator(std.heap.DefaultConfig) = null;
var gpa_allocator: ?std.mem.Allocator = null;
var aggregator: ?*parallel_aggregator.ParallelAggregator = null;
var matrices: ?*ticker_matrix.TickerMatrices = null;
var sdk_initialized = false;

/// Initialize SDK
/// Returns: 0 on success, -1 on error
export fn exo_init() i32 {
    if (sdk_initialized) return 0; // Already initialized

    var gpa_instance = std.heap.GeneralPurposeAllocator(std.heap.DefaultConfig){};
    gpa = gpa_instance;
    gpa_allocator = gpa.?.allocator();

    // Allocate aggregator
    const agg = gpa_allocator.?.create(parallel_aggregator.ParallelAggregator) catch return -1;
    agg.* = parallel_aggregator.ParallelAggregator.init(gpa_allocator.?);
    aggregator = agg;

    // Allocate matrices
    const mats = gpa_allocator.?.create(ticker_matrix.TickerMatrices) catch return -1;
    mats.* = ticker_matrix.TickerMatrices.init(gpa_allocator.?) catch return -1;
    matrices = mats;

    sdk_initialized = true;
    std.debug.print("[SDK] Initialized\n", .{});
    return 0;
}

/// Deinitialize SDK (cleanup)
export fn exo_deinit() void {
    if (!sdk_initialized) return;

    if (aggregator) |agg| {
        agg.stop();
        gpa_allocator.?.destroy(agg);
    }

    if (matrices) |mats| {
        mats.deinit();
        gpa_allocator.?.destroy(mats);
    }

    if (gpa) |*gpa_instance| {
        _ = gpa_instance.deinit();
    }

    sdk_initialized = false;
    std.debug.print("[SDK] Deinitialized\n", .{});
}

/// Start streaming from exchanges
/// exchanges: bitmask (0x1=Coinbase, 0x2=Kraken, 0x4=LCX, 0x7=all)
/// callback: function called on each tick
/// Returns: 0 on success, -1 on error
export fn exo_start(exchanges: u32, callback: ?TickCallback) i32 {
    if (!sdk_initialized) return -1;
    if (aggregator == null) return -1;

    aggregator.?.start(exchanges, callback orelse onDefaultCallback) catch |err| {
        std.debug.print("[SDK] Start error: {}\n", .{err});
        return -1;
    };

    return 0;
}

/// Stop all streams
export fn exo_stop() void {
    if (!sdk_initialized) return;
    if (aggregator) |agg| {
        agg.stop();
    }
}

/// Get total tick count across all exchanges
export fn exo_get_tick_count() u64 {
    if (!sdk_initialized) return 0;
    if (aggregator) |agg| {
        return agg.tick_count.load(.SeqCst);
    }
    return 0;
}

/// Get market matrix stats for a ticker
/// ticker_id: 0=BTC, 1=ETH, 2=XRP, 3=LTC
/// Returns: populated struct with stats (on error, all fields are 0)
export fn exo_get_matrix_stats(ticker_id: u8) MatrixStats {
    if (!sdk_initialized) return MatrixStats{};
    if (matrices == null) return MatrixStats{};

    const mat = switch (ticker_id) {
        0 => &matrices.?.btc,
        1 => &matrices.?.eth,
        2 => &matrices.?.xrp,
        3 => &matrices.?.ltc,
        else => return MatrixStats{},
    };

    return MatrixStats{
        .ticks_processed = mat.ticks_processed.load(.SeqCst),
        .total_volume = mat.total_volume.load(.SeqCst),
        .exchange_ticks = [3]u64{
            mat.exchange_ticks[0].load(.SeqCst),
            mat.exchange_ticks[1].load(.SeqCst),
            mat.exchange_ticks[2].load(.SeqCst),
        },
    };
}

/// Check if SDK is initialized and ready
export fn exo_is_initialized() bool {
    return sdk_initialized;
}

/// Default tick callback (does nothing, user provides their own)
fn onDefaultCallback(tick_opt: ?*const Tick) void {
    if (tick_opt) |tick| {
        if (matrices) |mats| {
            mats.ingest(tick) catch {};
        }
    }
}

/// C-compatible matrix stats struct
pub const MatrixStats = extern struct {
    ticks_processed: u64 = 0,
    total_volume: u64 = 0,
    exchange_ticks: [3]u64 = [3]u64{ 0, 0, 0 },
};
