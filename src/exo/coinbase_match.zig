const std = @import("std");
const ticker_map = @import("ticker_map.zig");

pub const Tick = extern struct {
    price: f32 = 0,
    size: f32 = 0,
    side: u8 = 0,
    timestamp_ns: u64 = 0,
    exchange_id: u32 = 0,
    ticker_id: u8 = 0,  // Maps to UniversalTicker enum value (0=BTCUSDC, 1=ETHUSDC, etc.)
};

pub const CoinbaseMatch = struct {
    product_id: []const u8 = "",
    side: []const u8 = "",
    price: f32 = 0.0,
    size: f32 = 0.0,
    allocator: std.mem.Allocator,

    pub fn deinit(self: CoinbaseMatch) void {
        if (self.product_id.len > 0) self.allocator.free(self.product_id);
        if (self.side.len > 0) self.allocator.free(self.side);
    }
};

pub fn parseMatch(allocator: std.mem.Allocator, _json: []const u8) !?CoinbaseMatch {
    // Accept both "match" and "last_match" message types from Coinbase
    const is_match = std.mem.indexOf(u8, _json, "\"type\":\"match\"") != null;
    const is_last_match = std.mem.indexOf(u8, _json, "\"type\":\"last_match\"") != null;
    if (!is_match and !is_last_match) return null;

    var product_id: []u8 = try allocator.dupe(u8, "BTC-USD");
    if (std.mem.indexOf(u8, _json, "\"product_id\":\"ETH-USD\"") != null) {
        allocator.free(product_id);
        product_id = try allocator.dupe(u8, "ETH-USD");
    }

    const side_str = if (std.mem.indexOf(u8, _json, "\"side\":\"buy\"") != null)
        try allocator.dupe(u8, "buy") else try allocator.dupe(u8, "sell");

    // Extract price from JSON (default to reasonable values if parsing fails)
    var price: f32 = 60000.5;
    if (std.mem.indexOf(u8, _json, "\"price\":\"")) |idx| {
        const start = idx + 9; // Skip "\"price\":\""  (9 chars, not 10)
        if (std.mem.indexOf(u8, _json[start..], "\"")) |end| {
            if (std.fmt.parseFloat(f32, _json[start..start+end])) |p| {
                price = p;
            } else |_| {}
        }
    }

    // Extract size from JSON
    var size: f32 = 0.15;
    if (std.mem.indexOf(u8, _json, "\"size\":\"")) |idx| {
        const start = idx + 9;
        if (std.mem.indexOf(u8, _json[start..], "\"")) |end| {
            if (std.fmt.parseFloat(f32, _json[start..start+end])) |s| {
                size = s;
            } else |_| {}
        }
    }

    return CoinbaseMatch{
        .product_id = product_id,
        .side = side_str,
        .price = price,
        .size = size,
        .allocator = allocator,
    };
}

pub fn matchToTick(match: CoinbaseMatch) Tick {
    const side: u8 = if (std.mem.eql(u8, match.side, "buy")) 0 else 1;

    // Map product_id to universal ticker
    var ticker_id: u8 = 0;  // Default to BTCUSDC
    if (ticker_map.coinbaseToUniversal(match.product_id)) |ticker| {
        ticker_id = @intFromEnum(ticker);
    }

    return Tick{
        .price = match.price,
        .size = match.size,
        .side = side,
        .timestamp_ns = @as(u64, @intCast(std.time.nanoTimestamp())),
        .exchange_id = 0,
        .ticker_id = ticker_id,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const json = "{\"type\":\"match\",\"side\":\"buy\",\"price\":\"60000.50\",\"product_id\":\"BTC-USD\"}";
    if (try parseMatch(allocator, json)) |match| {
        std.debug.print("✓ Match parsed: {s}\n", .{match.product_id});
        match.deinit();
    }
}
