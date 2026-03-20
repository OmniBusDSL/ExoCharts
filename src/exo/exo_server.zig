const std = @import("std");
const market_matrix = @import("market_matrix.zig");
const ticker_matrix = @import("ticker_matrix.zig");
const parallel_aggregator = @import("parallel_aggregator.zig");

pub const Tick = market_matrix.Tick;

/// Global ticker matrices (one per trading pair, thread-safe)
var global_matrices: *ticker_matrix.TickerMatrices = undefined;

/// Callback for ParallelAggregator - ingests real ticks into correct per-ticker matrix
fn onTickCallback(tick_opt: ?*const Tick) void {
    if (tick_opt) |tick| {
        global_matrices.ingest(tick) catch |err| {
            std.debug.print("[ERROR] Failed to ingest tick: {}\n", .{err});
        };
    }
}

/// ExoGridChart Server v2.1 - Real-time market profile with live data
/// WebSocket + TLS + 3 Exchanges (Coinbase, Kraken, LCX)

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════╗\n", .{});
    std.debug.print("║   ExoGridChart v2.1 - REAL DATA         ║\n", .{});
    std.debug.print("║   WebSocket + TLS + 3 Exchanges        ║\n", .{});
    std.debug.print("╚════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("[init] Creating per-ticker market matrices (BTC, ETH, XRP, LTC)...\n", .{});
    var mats = try ticker_matrix.TickerMatrices.init(allocator);
    defer mats.deinit();
    global_matrices = &mats;

    std.debug.print("[init] Initializing ParallelAggregator (Coinbase + Kraken + LCX)...\n", .{});
    var agg = parallel_aggregator.ParallelAggregator.init(allocator);
    defer agg.deinit();

    std.debug.print("[init] Starting WebSocket streams with TLS (WSS)...\n", .{});
    agg.start(0x7, onTickCallback) catch |err| {
        std.debug.print("[ERROR] ParallelAggregator start error: {}\n", .{err});
        std.debug.print("[note] Continuing with HTTP server (ticks may not flow if WSS fails)\n", .{});
    };

    std.debug.print("[init] Starting HTTP server on :8080...\n\n", .{});
    std.debug.print("✅ Browser: http://localhost:8080\n", .{});
    std.debug.print("✅ Live data: Coinbase, Kraken, LCX (WSS streams)\n", .{});
    std.debug.print("✅ API: GET /api/matrix (real market data)\n\n", .{});

    try runHttpServer(&mats);

    agg.stop();
}

/// HTTP server serving frontend + real market data (per-ticker or combined)
fn runHttpServer(matrices: *ticker_matrix.TickerMatrices) !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 9090);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    std.debug.print("[server] Listening on http://127.0.0.1:9090\n", .{});

    while (true) {
        var client = try server.accept();
        defer client.stream.close();

        var buffer: [4096]u8 = undefined;
        const bytes_read = try client.stream.read(&buffer);

        if (bytes_read == 0) continue;

        const request = buffer[0..bytes_read];

        // Parse request line
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = lines.next() orelse "";

        var parts = std.mem.splitSequence(u8, request_line, " ");
        const method = parts.next() orelse "GET";
        const path_full = parts.next() orelse "/";

        // Parse path and query string
        var path: []const u8 = path_full;
        var query: []const u8 = "";
        if (std.mem.indexOf(u8, path_full, "?")) |query_idx| {
            path = path_full[0..query_idx];
            if (query_idx + 1 < path_full.len) {
                query = path_full[query_idx + 1 ..];
            }
        }

        if (std.mem.eql(u8, method, "GET")) {
            if (std.mem.eql(u8, path, "/")) {
                serveIndexHtml(client.stream) catch |err| {
                    std.debug.print("[server] HTML error: {}\n", .{err});
                };
            } else if (std.mem.eql(u8, path, "/api/matrix")) {
                serveMatrixJson(client.stream, matrices, query) catch |err| {
                    std.debug.print("[server] API error: {}\n", .{err});
                };
            } else {
                const response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found";
                _ = try client.stream.writeAll(response);
            }
        }
    }
}

fn serveIndexHtml(stream: std.net.Stream) !void {
    const file = std.fs.cwd().openFile("frontend/index.html", .{}) catch {
        const response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 14\r\nConnection: close\r\n\r\nFile not found";
        _ = try stream.writeAll(response);
        return;
    };
    defer file.close();

    var buf: [65536]u8 = undefined;
    const file_stat = try file.stat();
    const size_to_read = @min(buf.len, @as(usize, @intCast(file_stat.size)));
    const bytes_read = try file.readAll(buf[0..size_to_read]);

    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{bytes_read}
    );

    _ = try stream.writeAll(header);
    _ = try stream.writeAll(buf[0..bytes_read]);
}

fn serveMatrixJson(stream: std.net.Stream, matrices: *ticker_matrix.TickerMatrices, query: []const u8) !void {
    // Parse ticker parameter from query string (default to BTCUSDC = ticker 0)
    var selected_ticker: u8 = 0;  // Default BTC
    if (std.mem.indexOf(u8, query, "ticker=")) |idx| {
        const ticker_str = query[idx + 7 ..];
        if (std.mem.startsWith(u8, ticker_str, "ETHUSDC")) {
            selected_ticker = 1;
        } else if (std.mem.startsWith(u8, ticker_str, "XRPUSDC")) {
            selected_ticker = 2;
        } else if (std.mem.startsWith(u8, ticker_str, "LTCUSDC")) {
            selected_ticker = 3;
        }
    }

    // Parse timeframe parameter for aggregation
    var buckets_per_output: u32 = 1;  // Default 1s
    if (std.mem.indexOf(u8, query, "timeframe=")) |idx| {
        const tf = query[idx + 10 ..];
        if (std.mem.startsWith(u8, tf, "5s")) buckets_per_output = 5;
        if (std.mem.startsWith(u8, tf, "1m")) buckets_per_output = 60;
        if (std.mem.startsWith(u8, tf, "5m")) buckets_per_output = 60;
    }

    // Get matrix for selected ticker
    const matrix = matrices.getMatrixByTicker(@as(@import("ticker_map.zig").UniversalTicker, @enumFromInt(selected_ticker)));

    // Calculate output columns based on aggregation
    const output_cols = matrix.time_buckets / buckets_per_output;

    // Get current matrix state (thread-safe)
    const stats = matrix.get_stats();
    const poc = matrix.find_poc();

    // Build JSON response (6MB buffer for full data + delta arrays)
    var json_buf: [6291456]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&json_buf);
    const writer = fbs.writer();

    try writer.print(
        "{{\"price_min\":{d},\"price_max\":{d},\"price_step\":{d},\"time_buckets\":{d},\"price_rows\":{d},\"ticks_processed\":{d},\"total_volume\":{d},\"poc_price\":{d},\"poc_volume\":{d},\"current_time_bucket\":{d},\"data\":[",
        .{
            matrix.price_min,
            matrix.price_max,
            matrix.price_step,
            output_cols,
            matrix.price_rows,
            stats.ticks_processed,
            stats.total_volume,
            poc.price,
            poc.volume,
            matrix.current_time_bucket,
        }
    );

    // Write data array (total volume, aggregated by timeframe)
    if (matrix.data) |data| {
        var first_element = true;
        for (0..matrix.price_rows) |row| {
            for (0..output_cols) |out_col| {
                var agg: u64 = 0;
                for (0..buckets_per_output) |offset| {
                    const src = row * matrix.time_buckets + out_col * buckets_per_output + offset;
                    if (src < data.len) {
                        agg += data[src];
                    }
                }
                if (!first_element) try writer.writeAll(",");
                try writer.print("{d}", .{agg});
                first_element = false;
            }
        }
    }

    try writer.writeAll("],\"delta\":[");

    // Write delta array (buy - sell, aggregated by timeframe)
    if (matrix.buy_data) |buy_data| {
        var first_element = true;
        for (0..matrix.price_rows) |row| {
            for (0..output_cols) |out_col| {
                var agg_buy: i64 = 0;
                var agg_sell: i64 = 0;
                for (0..buckets_per_output) |offset| {
                    const src = row * matrix.time_buckets + out_col * buckets_per_output + offset;
                    if (src < buy_data.len) {
                        agg_buy += @as(i64, @intCast(buy_data[src]));
                    }
                    if (matrix.sell_data) |sell_data| {
                        if (src < sell_data.len) {
                            agg_sell += @as(i64, @intCast(sell_data[src]));
                        }
                    }
                }
                const delta = agg_buy - agg_sell;
                if (!first_element) try writer.writeAll(",");
                try writer.print("{d}", .{delta});
                first_element = false;
            }
        }
    }

    // Add per-exchange breakdown
    try writer.writeAll("],\"exchanges\":{");

    // Coinbase (price stored as cents * 100, e.g., $70,660.50 → 7,066,050)
    const cb_ticks = matrix.exchange_ticks[0].load(.acquire);
    const cb_volume = matrix.exchange_volume[0].load(.acquire);
    const cb_price_cents = matrix.exchange_last_price[0].load(.acquire);
    try writer.print("\"coinbase\":{{\"ticks\":{d},\"volume\":{d},\"price\":{d}.{d:0>2}}},", .{
        cb_ticks, cb_volume, cb_price_cents / 100, cb_price_cents % 100
    });

    // Kraken
    const kraken_ticks = matrix.exchange_ticks[1].load(.acquire);
    const kraken_volume = matrix.exchange_volume[1].load(.acquire);
    const kraken_price_cents = matrix.exchange_last_price[1].load(.acquire);
    try writer.print("\"kraken\":{{\"ticks\":{d},\"volume\":{d},\"price\":{d}.{d:0>2}}},", .{
        kraken_ticks, kraken_volume, kraken_price_cents / 100, kraken_price_cents % 100
    });

    // LCX
    const lcx_ticks = matrix.exchange_ticks[2].load(.acquire);
    const lcx_volume = matrix.exchange_volume[2].load(.acquire);
    const lcx_price_cents = matrix.exchange_last_price[2].load(.acquire);
    try writer.print("\"lcx\":{{\"ticks\":{d},\"volume\":{d},\"price\":{d}.{d:0>2}}}", .{
        lcx_ticks, lcx_volume, lcx_price_cents / 100, lcx_price_cents % 100
    });

    try writer.writeAll("}}");

    const json_content = fbs.getWritten();

    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        .{json_content.len}
    );

    _ = try stream.writeAll(header);
    _ = try stream.writeAll(json_content);
}
