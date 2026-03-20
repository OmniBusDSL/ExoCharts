const std = @import("std");
const market_matrix = @import("market_matrix.zig");
const ticker_map = @import("ticker_map.zig");

pub const Tick = market_matrix.Tick;

/// Manages 4 separate market matrices, one per ticker
pub const TickerMatrices = struct {
    allocator: std.mem.Allocator,
    btc: market_matrix.MarketMatrix,
    eth: market_matrix.MarketMatrix,
    xrp: market_matrix.MarketMatrix,
    ltc: market_matrix.MarketMatrix,

    pub fn init(allocator: std.mem.Allocator) !TickerMatrices {
        return TickerMatrices{
            .allocator = allocator,
            .btc = try market_matrix.MarketMatrix.init(allocator),
            .eth = try market_matrix.MarketMatrix.init(allocator),
            .xrp = try market_matrix.MarketMatrix.init(allocator),
            .ltc = try market_matrix.MarketMatrix.init(allocator),
        };
    }

    /// Get the matrix for a specific ticker
    fn getMatrix(self: *TickerMatrices, ticker_id: u8) *market_matrix.MarketMatrix {
        return switch (ticker_id) {
            0 => &self.btc,   // BTCUSDC
            1 => &self.eth,   // ETHUSDC
            2 => &self.xrp,   // XRPUSDC
            3 => &self.ltc,   // LTCUSDC
            else => &self.btc, // Default to BTC
        };
    }

    /// Ingest tick into the correct per-ticker matrix
    pub fn ingest(self: *TickerMatrices, tick: *const Tick) !void {
        const matrix = self.getMatrix(tick.ticker_id);
        try matrix.ingest(tick);
    }

    /// Get matrix for a specific ticker by name
    pub fn getMatrixByTicker(self: *TickerMatrices, ticker: ticker_map.UniversalTicker) *market_matrix.MarketMatrix {
        return self.getMatrix(@intFromEnum(ticker));
    }

    /// Deinitialize all matrices
    pub fn deinit(self: *TickerMatrices) void {
        self.btc.deinit();
        self.eth.deinit();
        self.xrp.deinit();
        self.ltc.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var matrices = try TickerMatrices.init(allocator);
    defer matrices.deinit();

    std.debug.print("✓ Ticker matrices initialized\n", .{});
    std.debug.print("  BTC matrix: {d}×{d}\n", .{ matrices.btc.price_rows, matrices.btc.time_buckets });
    std.debug.print("  ETH matrix: {d}×{d}\n", .{ matrices.eth.price_rows, matrices.eth.time_buckets });
}
