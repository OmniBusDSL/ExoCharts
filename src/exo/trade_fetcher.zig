const std = @import("std");

/// Simple trade data fetcher from public REST APIs
pub const TradeFetcher = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TradeFetcher {
        return TradeFetcher{ .allocator = allocator };
    }

    /// Fetch recent BTC trades from Coinbase REST API (public endpoint, no auth)
    pub fn fetchCoinbaseTrades(self: TradeFetcher) ![]const u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = "https://api.exchange.coinbase.com/products/BTC-USD/trades?limit=100";
        const uri = try std.Uri.parse(url);

        var headers = std.http.Client.Request.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        try headers.append("User-Agent", "ExoGridChart/2.1");
        try headers.append("Accept", "application/json");

        var request = try client.open(.GET, uri, .{
            .headers = headers,
        });
        defer request.deinit();

        try request.send();

        var response = request.reader();
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try response.readAllArrayList(&buffer, 1024 * 1024); // Max 1MB response

        const result = try self.allocator.dupe(u8, buffer.items);
        return result;
    }

    /// Parse Coinbase trade JSON and extract trades
    pub fn parseCoinbaseJson(self: TradeFetcher, json_str: []const u8) ![100]struct { price: f64, size: f64, side: []const u8 } {
        var result: [100]struct { price: f64, size: f64, side: []const u8 } = undefined;
        var count: usize = 0;

        // Simple JSON parsing (proper parsing would use std.json)
        var lines = std.mem.splitSequence(u8, json_str, "{");
        while (lines.next()) |line| {
            if (count >= 100) break;

            // Parse "price":"12345.67"
            if (std.mem.indexOf(u8, line, "\"price\"")) |idx| {
                const price_part = line[idx + 10 ..];
                if (std.mem.indexOf(u8, price_part, ",")) |end| {
                    if (std.fmt.parseFloat(f64, price_part[0..end])) |price| {
                        result[count].price = price;
                    } else |_| {}
                }
            }

            // Parse "size":"0.5"
            if (std.mem.indexOf(u8, line, "\"size\"")) |idx| {
                const size_part = line[idx + 8 ..];
                if (std.mem.indexOf(u8, size_part, ",")) |end| {
                    if (std.fmt.parseFloat(f64, size_part[0..end])) |size| {
                        result[count].size = size;
                    } else |_| {}
                }
            }

            // Parse "side":"buy" or "sell"
            if (std.mem.indexOf(u8, line, "\"side\"")) |idx| {
                const side_part = line[idx + 8 ..];
                if (std.mem.indexOf(u8, side_part, "\"")) |end| {
                    result[count].side = side_part[0..end];
                    count += 1;
                }
            }
        }

        return result;
    }

    pub fn deinit(self: TradeFetcher) void {
        _ = self;
    }
};
