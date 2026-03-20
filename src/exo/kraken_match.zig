const std = @import("std");
const coinbase = @import("coinbase_match.zig");
const ticker_map = @import("ticker_map.zig");

pub const Tick = coinbase.Tick;

pub const KrakenTrade = struct {
    pair: []const u8 = "",
    side: []const u8 = "",
    price: f32 = 0.0,
    size: f32 = 0.0,
    allocator: std.mem.Allocator,

    pub fn deinit(self: KrakenTrade) void {
        if (self.pair.len > 0) self.allocator.free(self.pair);
        if (self.side.len > 0) self.allocator.free(self.side);
    }
};

/// Parse Kraken trade message - ARRAY FORMAT!
/// Format: [channelID, [[price, size, time, side, ordertype, misc]], "trade", "pair"]
/// Example: [13959169,[["2075.15000","0.00178382","1772787932.613746","s","l",""]],"trade","ETH/USD"]
/// Heartbeats: {"event":"heartbeat"}
/// Ignore subscription status/systemStatus messages
pub fn parseTrade(allocator: std.mem.Allocator, payload: []const u8) !?KrakenTrade {
    // FILTER OUT: Subscription confirmations, status, heartbeats
    if (std.mem.indexOf(u8, payload, "\"subscriptionStatus\"") != null or
        std.mem.indexOf(u8, payload, "\"systemStatus\"") != null or
        std.mem.indexOf(u8, payload, "\"heartbeat\"") != null) {
        return null;
    }

    // Must be an array starting with [
    if (payload.len == 0 or payload[0] != '[') return null;

    // Look for "trade" marker in the message
    if (std.mem.indexOf(u8, payload, "\"trade\"") == null) return null;

    // Extract pair name - look for "pair" at end like: "ETH/USD"] or "XBT/USD"]
    var pair: []u8 = try allocator.dupe(u8, "XBT/USD");
    if (std.mem.indexOf(u8, payload, "\"ETH/USD\"") != null) {
        allocator.free(pair);
        pair = try allocator.dupe(u8, "ETH/USD");
    } else if (std.mem.indexOf(u8, payload, "\"LTC/USD\"") != null) {
        allocator.free(pair);
        pair = try allocator.dupe(u8, "LTC/USD");
    } else if (std.mem.indexOf(u8, payload, "\"XRP/USD\"") != null) {
        allocator.free(pair);
        pair = try allocator.dupe(u8, "XRP/USD");
    }

    // Format: [channelID, [[price, size, time, side, ...]], "trade", "pair"]
    // Find the first array with prices: [[ pattern
    var price: f32 = 0.0;
    var size: f32 = 0.0;
    var side: []u8 = try allocator.dupe(u8, "sell");

    if (std.mem.indexOf(u8, payload, "[[\"")) |start_idx| {
        const array_start = start_idx + 3; // Skip [["

        // Extract price (first quoted number)
        if (std.mem.indexOf(u8, payload[array_start..], "\"")) |quote_end| {
            const price_str = payload[array_start..array_start + quote_end];
            if (std.fmt.parseFloat(f32, price_str)) |p| {
                price = p;
            } else |_| {}
        }

        // Extract size (second quoted number, after next comma+quote)
        if (std.mem.indexOf(u8, payload[array_start..], ",\"")) |comma_idx| {
            const size_start = array_start + comma_idx + 2;
            if (std.mem.indexOf(u8, payload[size_start..], "\"")) |quote_end| {
                const size_str = payload[size_start..size_start + quote_end];
                if (std.fmt.parseFloat(f32, size_str)) |s| {
                    size = s;
                } else |_| {}
            }
        }

        // Extract side - look for "b" or "s" pattern after time
        // In Kraken: "b"=buy, "s"=sell
        if (std.mem.indexOf(u8, payload[array_start..], ",\"b\"")) |_| {
            allocator.free(side);
            side = try allocator.dupe(u8, "buy");
        } else if (std.mem.indexOf(u8, payload[array_start..], ",\"s\"")) |_| {
            allocator.free(side);
            side = try allocator.dupe(u8, "sell");
        }
    }

    return KrakenTrade{
        .pair = pair,
        .side = side,
        .price = price,
        .size = size,
        .allocator = allocator,
    };
}

/// Convert Kraken trade to Tick struct
pub fn tradeToTick(trade: KrakenTrade) Tick {
    const side: u8 = if (std.mem.eql(u8, trade.side, "buy")) 0 else 1;

    // Map pair to universal ticker
    var ticker_id: u8 = 0;  // Default to BTCUSDC
    if (ticker_map.krakenToUniversal(trade.pair)) |ticker| {
        ticker_id = @intFromEnum(ticker);
    }

    return Tick{
        .price = trade.price,
        .size = trade.size,
        .side = side,
        .timestamp_ns = @as(u64, @intCast(std.time.nanoTimestamp())),
        .exchange_id = 1, // Kraken
        .ticker_id = ticker_id,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{\"event\":\"trade\",\"pair\":\"XBTUSDT\",\"data\":[{\"price\":\"47500.00\",\"volume\":\"0.25\",\"side\":\"b\"}]}";
    if (try parseTrade(allocator, json)) |trade| {
        std.debug.print("✓ Kraken trade parsed: {s}\n", .{trade.pair});
        trade.deinit();
    }
}
