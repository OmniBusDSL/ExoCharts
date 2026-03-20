const std = @import("std");

/// Universal ticker symbols (what user selects)
pub const UniversalTicker = enum {
    BTCUSDC,
    ETHUSDC,
    XRPUSDC,
    LTCUSDC,
};

/// Exchange-specific ticker formats
pub const ExchangeTicker = struct {
    coinbase: []const u8,  // e.g., "BTC-USDC"
    kraken: []const u8,    // e.g., "XBT/USDC"
    lcx: []const u8,       // e.g., "BTC/USDC"
};

/// Get exchange-specific tickers for a universal ticker
pub fn getExchangeTickers(ticker: UniversalTicker) ExchangeTicker {
    return switch (ticker) {
        .BTCUSDC => .{
            .coinbase = "BTC-USDC",
            .kraken = "XBT/USDC",
            .lcx = "BTC/USDC",
        },
        .ETHUSDC => .{
            .coinbase = "ETH-USDC",
            .kraken = "ETH/USDC",
            .lcx = "ETH/USDC",
        },
        .XRPUSDC => .{
            .coinbase = "XRP-USDC",
            .kraken = "XRP/USDC",
            .lcx = "XRP/USDC",
        },
        .LTCUSDC => .{
            .coinbase = "LTC-USDC",
            .kraken = "LTC/USDC",
            .lcx = "LTC/USDC",
        },
    };
}

/// Map Coinbase product_id to universal ticker
pub fn coinbaseToUniversal(product_id: []const u8) ?UniversalTicker {
    if (std.mem.eql(u8, product_id, "BTC-USDC") or std.mem.eql(u8, product_id, "BTC-USD")) {
        return .BTCUSDC;
    } else if (std.mem.eql(u8, product_id, "ETH-USDC") or std.mem.eql(u8, product_id, "ETH-USD")) {
        return .ETHUSDC;
    } else if (std.mem.eql(u8, product_id, "XRP-USDC") or std.mem.eql(u8, product_id, "XRP-USD")) {
        return .XRPUSDC;
    } else if (std.mem.eql(u8, product_id, "LTC-USDC") or std.mem.eql(u8, product_id, "LTC-USD")) {
        return .LTCUSDC;
    }
    return null;
}

/// Map Kraken pair to universal ticker
pub fn krakenToUniversal(pair: []const u8) ?UniversalTicker {
    if (std.mem.eql(u8, pair, "XBT/USDC") or std.mem.eql(u8, pair, "XBT/USD")) {
        return .BTCUSDC;
    } else if (std.mem.eql(u8, pair, "ETH/USDC") or std.mem.eql(u8, pair, "ETH/USD")) {
        return .ETHUSDC;
    } else if (std.mem.eql(u8, pair, "XRP/USDC") or std.mem.eql(u8, pair, "XRP/USD")) {
        return .XRPUSDC;
    } else if (std.mem.eql(u8, pair, "LTC/USDC") or std.mem.eql(u8, pair, "LTC/USD")) {
        return .LTCUSDC;
    }
    return null;
}

/// Map LCX pair to universal ticker
pub fn lcxToUniversal(pair: []const u8) ?UniversalTicker {
    if (std.mem.eql(u8, pair, "BTC/USDC") or std.mem.eql(u8, pair, "BTC/EUR")) {
        return .BTCUSDC;
    } else if (std.mem.eql(u8, pair, "ETH/USDC") or std.mem.eql(u8, pair, "ETH/EUR")) {
        return .ETHUSDC;
    } else if (std.mem.eql(u8, pair, "XRP/USDC") or std.mem.eql(u8, pair, "XRP/EUR")) {
        return .XRPUSDC;
    } else if (std.mem.eql(u8, pair, "LTC/USDC") or std.mem.eql(u8, pair, "LTC/EUR")) {
        return .LTCUSDC;
    }
    return null;
}

/// Get display name for universal ticker
pub fn getTickerName(ticker: UniversalTicker) []const u8 {
    return switch (ticker) {
        .BTCUSDC => "BTCUSDC",
        .ETHUSDC => "ETHUSDC",
        .XRPUSDC => "XRPUSDC",
        .LTCUSDC => "LTCUSDC",
    };
}

/// Get short display name
pub fn getShortName(ticker: UniversalTicker) []const u8 {
    return switch (ticker) {
        .BTCUSDC => "BTC",
        .ETHUSDC => "ETH",
        .XRPUSDC => "XRP",
        .LTCUSDC => "LTC",
    };
}

pub fn main() !void {
    const tickers = getExchangeTickers(.BTCUSDC);
    std.debug.print("BTCUSDC maps to:\n", .{});
    std.debug.print("  Coinbase: {s}\n", .{tickers.coinbase});
    std.debug.print("  Kraken: {s}\n", .{tickers.kraken});
    std.debug.print("  LCX: {s}\n", .{tickers.lcx});
}
