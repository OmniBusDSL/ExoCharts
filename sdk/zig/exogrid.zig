/// ExoGridChart Zig SDK
/// High-level API for streaming real-time cryptocurrency market data
///
/// Example usage:
/// ```zig
/// var allocator = std.heap.page_allocator;
/// var aggregator = ParallelAggregator.init(allocator);
/// try aggregator.start(0x7, &onTick);  // Start all 3 exchanges
/// // ... process ticks in onTick callback ...
/// aggregator.stop();
/// ```

pub const parallel_aggregator = @import("../../src/exo/parallel_aggregator.zig");
pub const market_matrix = @import("../../src/exo/market_matrix.zig");
pub const ticker_matrix = @import("../../src/exo/ticker_matrix.zig");
pub const stream_instance = @import("../../src/exo/stream_instance.zig");
pub const ticker_map = @import("../../src/exo/ticker_map.zig");

/// A single market trade/quote from an exchange
pub const Tick = market_matrix.Tick;

/// Callback invoked on each new tick
pub const TickCallback = parallel_aggregator.TickCallback;

/// Exchange identifier
pub const Exchange = parallel_aggregator.Exchange;

/// Manages multiple independent WebSocket streams (one per exchange)
/// Delivers all ticks to a single callback in a thread-safe manner
///
/// Example:
/// ```zig
/// var agg = ParallelAggregator.init(allocator);
/// try agg.start(0x7, &myCallback);  // 0x7 = all 3 exchanges
/// std.time.sleep(10 * std.time.ns_per_s);
/// agg.stop();
/// ```
pub const ParallelAggregator = parallel_aggregator.ParallelAggregator;

/// 2D price × time market profile grid
/// Aggregates ticks by price bucket and time period
///
/// Example:
/// ```zig
/// var matrix = try MarketMatrix.init(allocator);
/// try matrix.ingest(&tick);
/// const poc = matrix.find_poc();
/// std.debug.print("Point of Control: {}\n", .{poc.price});
/// ```
pub const MarketMatrix = market_matrix.MarketMatrix;

/// Manages multiple MarketMatrix instances (one per ticker: BTC, ETH, XRP, LTC)
/// Routes ticks to the correct matrix based on ticker_id
///
/// Example:
/// ```zig
/// var matrices = try TickerMatrices.init(allocator);
/// try matrices.ingest(&tick);  // Automatically routes to BTC/ETH/XRP/LTC
/// const btc_matrix = matrices.getMatrixByTicker(.BTCUSDC);
/// ```
pub const TickerMatrices = ticker_matrix.TickerMatrices;

/// Universal ticker identifiers
pub const UniversalTicker = ticker_map.UniversalTicker;

/// Cross-exchange ticker mapping
/// Maps exchange-specific product IDs to universal ticker IDs
///
/// Example:
/// ```zig
/// const ticker = ticker_map.coinbaseToUniversal("BTC-USD") orelse unreachable;
/// // ticker == .BTCUSDC
/// ```
pub const TickerMap = ticker_map;

/// Exchange-specific types and parsers
pub const coinbase = @import("../../src/exo/coinbase_match.zig");
pub const kraken = @import("../../src/exo/kraken_match.zig");
pub const lcx = @import("../../src/exo/lcx_match.zig");

/// WebSocket protocol types
pub const ws_types = @import("../../src/exo/ws_types.zig");

/// TLS support for WSS connections
pub const tls = @import("../../src/exo/tls.zig");

/// WebSocket client
pub const ws_client = @import("../../src/exo/ws_client.zig");

/// Re-export std for convenience
pub const std = @import("std");
