const std = @import("std");
const coinbase = @import("coinbase_match.zig");
const ticker_map = @import("ticker_map.zig");

pub const Tick = coinbase.Tick;

pub const LcxTrade = struct {
    pair: []const u8 = "",
    side: []const u8 = "",
    price: f32 = 0.0,
    size: f32 = 0.0,
    allocator: std.mem.Allocator,

    pub fn deinit(self: LcxTrade) void {
        if (self.pair.len > 0) self.allocator.free(self.pair);
        if (self.side.len > 0) self.allocator.free(self.side);
    }
};

/// Parse LCX ticker message (snapshot or update)
/// Format: {"type":"ticker","topic":"snapshot"/"update","pair":"","data":{...pair data...}}
/// Each ticker data object has: "last" (last price), "bestBid", "bestAsk", etc.
pub fn parseTrade(allocator: std.mem.Allocator, _json: []const u8) !?LcxTrade {
    // Check for ticker type (LCX sends "type":"ticker" not "trade")
    if (std.mem.indexOf(u8, _json, "\"type\":\"ticker\"") == null) return null;

    // Must have data field (skip empty messages)
    if (std.mem.indexOf(u8, _json, "\"data\":{") == null) return null;

    // Default pair
    var pair: []u8 = try allocator.dupe(u8, "BTC/USDC");

    // Look for BTC-related pairs in order of preference: BTC/USDC, BTC/EUR
    var btc_section: []const u8 = "";
    if (std.mem.indexOf(u8, _json, "\"BTC/USDC\":{")) |btc_idx| {
        const search_start = btc_idx;
        if (std.mem.indexOf(u8, _json[search_start..], "},\"")) |end_idx| {
            btc_section = _json[search_start..search_start + end_idx + 1];
        } else if (std.mem.indexOf(u8, _json[search_start..], "}}}")) |end_idx| {
            btc_section = _json[search_start..search_start + end_idx + 1];
        }
    } else if (std.mem.indexOf(u8, _json, "\"BTC/EUR\":{")) |btc_idx| {
        const search_start = btc_idx;
        if (std.mem.indexOf(u8, _json[search_start..], "},\"")) |end_idx| {
            btc_section = _json[search_start..search_start + end_idx + 1];
        } else if (std.mem.indexOf(u8, _json[search_start..], "}}}")) |end_idx| {
            btc_section = _json[search_start..search_start + end_idx + 1];
        }
        allocator.free(pair);
        pair = try allocator.dupe(u8, "BTC/EUR");
    }

    // Extract price from LCX ticker data
    // LCX format: "bestAsk":0.08438,"bestBid":0.08412 (numbers without quotes!)
    var price: f32 = 0.0;

    // Search in BTC section if found, otherwise search entire message
    const search_text = if (btc_section.len > 0) btc_section else _json;

    // Try bestAsk first (market ask price)
    // Format: "bestAsk":0.08438,"bestBid"  (no quotes around number!)
    if (std.mem.indexOf(u8, search_text, "\"bestAsk\":")) |idx| {
        const start = idx + 10;
        // Find next comma or quote (end of number)
        var end_pos: usize = 0;
        for (start..@min(start + 20, search_text.len)) |i| {
            if (search_text[i] == ',' or search_text[i] == '"') {
                end_pos = i - start;
                break;
            }
        }
        if (end_pos > 0) {
            if (std.fmt.parseFloat(f32, search_text[start..start + end_pos])) |p| {
                price = p;
            } else |_| {}
        }
    }

    // If no bestAsk, try bestBid
    if (price == 0.0) {
        if (std.mem.indexOf(u8, search_text, "\"bestBid\":")) |idx| {
            const start = idx + 10;
            var end_pos: usize = 0;
            for (start..@min(start + 20, search_text.len)) |i| {
                if (search_text[i] == ',' or search_text[i] == '"') {
                    end_pos = i - start;
                    break;
                }
            }
            if (end_pos > 0) {
                if (std.fmt.parseFloat(f32, search_text[start..start + end_pos])) |p| {
                    price = p;
                } else |_| {}
            }
        }
    }

    // Last resort: try "last" or "last24Price"
    if (price == 0.0) {
        if (std.mem.indexOf(u8, search_text, "\"last\":")) |idx| {
            const start = idx + 7;
            var end_pos: usize = 0;
            for (start..@min(start + 20, search_text.len)) |i| {
                if (search_text[i] == ',' or search_text[i] == '"') {
                    end_pos = i - start;
                    break;
                }
            }
            if (end_pos > 0) {
                if (std.fmt.parseFloat(f32, search_text[start..start + end_pos])) |p| {
                    price = p;
                } else |_| {}
            }
        }
    }

    // For LCX ticker, we'll use volume as 0.1 (simplified - ticker is price level, not trade)
    const size: f32 = 0.1;

    // Side doesn't really apply to ticker data - default to buy
    const side_str = try allocator.dupe(u8, "buy");

    return LcxTrade{
        .pair = pair,
        .side = side_str,
        .price = price,
        .size = size,
        .allocator = allocator,
    };
}

/// Convert LCX trade to Tick struct
pub fn tradeToTick(trade: LcxTrade) Tick {
    const side: u8 = if (std.mem.eql(u8, trade.side, "buy")) 0 else 1;

    // Map pair to universal ticker
    var ticker_id: u8 = 0;  // Default to BTCUSDC
    if (ticker_map.lcxToUniversal(trade.pair)) |ticker| {
        ticker_id = @intFromEnum(ticker);
    }

    return Tick{
        .price = trade.price,
        .size = trade.size,
        .side = side,
        .timestamp_ns = @as(u64, @intCast(std.time.nanoTimestamp())),
        .exchange_id = 2, // LCX
        .ticker_id = ticker_id,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"event\":\"trade\",\"pair\":\"BTC-USD\",\"data\":[{\"price\":\"48000.00\",\"volume\":\"0.20\",\"side\":\"buy\"}]}";
    if (try parseTrade(allocator, json)) |trade| {
        std.debug.print("✓ LCX trade parsed: {s}\n", .{trade.pair});
        trade.deinit();
    }
}
