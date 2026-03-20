const std = @import("std");
const coinbase = @import("coinbase_match.zig");

pub const Tick = coinbase.Tick;

/// 2D Price × Time matrix for market profile visualization
/// Rows: Price levels (bucketed)
/// Cols: Time periods (1-second buckets)
/// Values: Volume traded at each (price, time) intersection
pub const MarketMatrix = struct {
    allocator: std.mem.Allocator,

    // Configuration
    price_min: f32 = 0.0,     // Global minimum (accommodates all crypto)
    price_max: f32 = 100000.0, // Global maximum (BTC + altcoins)
    price_step: f32 = 10.0,   // $10 per row
    time_buckets: u32 = 60,   // 60 one-second periods (1 minute)

    // Calculated
    price_rows: u32 = 0,
    total_cells: u32 = 0,

    // Data: 2D grid stored as 1D array (row-major)
    // matrix[row][col] → data[row * time_buckets + col]
    data: ?[]u64 = null,
    buy_data: ?[]u64 = null,   // Buy volume per cell
    sell_data: ?[]u64 = null,  // Sell volume per cell
    current_time_bucket: u32 = 0,
    session_start_ns: u64 = 0,

    // Thread safety
    mutex: std.Thread.Mutex = .{},

    // Metrics
    ticks_processed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    total_volume: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // Per-exchange tracking (exchange_id: 0=Coinbase, 1=Kraken, 2=LCX)
    exchange_ticks: [3]std.atomic.Value(u64) = .{
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
    },
    exchange_volume: [3]std.atomic.Value(u64) = .{
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
    },
    exchange_last_price: [3]std.atomic.Value(u32) = .{
        std.atomic.Value(u32).init(0),
        std.atomic.Value(u32).init(0),
        std.atomic.Value(u32).init(0),
    },

    pub fn init(allocator: std.mem.Allocator) !MarketMatrix {
        var matrix = MarketMatrix{
            .allocator = allocator,
            .session_start_ns = @as(u64, @intCast(std.time.nanoTimestamp())),
        };

        // Calculate grid dimensions
        matrix.price_rows = @as(u32, @intCast(@as(i64, @intFromFloat(
            (matrix.price_max - matrix.price_min) / matrix.price_step + 1,
        ))));
        matrix.total_cells = matrix.price_rows * matrix.time_buckets;

        // Allocate 2D grids (initialized to 0)
        matrix.data = try allocator.alloc(u64, matrix.total_cells);
        @memset(matrix.data.?, 0);

        matrix.buy_data = try allocator.alloc(u64, matrix.total_cells);
        @memset(matrix.buy_data.?, 0);

        matrix.sell_data = try allocator.alloc(u64, matrix.total_cells);
        @memset(matrix.sell_data.?, 0);

        std.debug.print("[matrix] Initialized {d}×{d} grid ({d} cells) with buy/sell tracking\n", .{
            matrix.price_rows,
            matrix.time_buckets,
            matrix.total_cells,
        });

        return matrix;
    }

    pub fn deinit(self: *MarketMatrix) void {
        if (self.data) |data| {
            self.allocator.free(data);
        }
        if (self.buy_data) |data| {
            self.allocator.free(data);
        }
        if (self.sell_data) |data| {
            self.allocator.free(data);
        }
    }

    /// Ingest tick into matrix
    /// Updates the (price, time) cell with tick size (thread-safe with mutex)
    pub fn ingest(self: *MarketMatrix, tick: *const Tick) !void {
        // Determine price row (quantize to nearest step)
        if (tick.price < self.price_min or tick.price > self.price_max) {
            return; // Out of bounds
        }

        const price_offset = tick.price - self.price_min;
        const row: u32 = @as(u32, @intCast(@as(i64, @intFromFloat(
            @trunc(price_offset / self.price_step),
        ))));

        if (row >= self.price_rows) return;

        // Determine time column
        const elapsed_ns = tick.timestamp_ns -% self.session_start_ns;
        const elapsed_sec = elapsed_ns / 1_000_000_000;
        const col: u32 = @min(
            @as(u32, @intCast(elapsed_sec % self.time_buckets)),
            self.time_buckets - 1,
        );

        // Update cell: convert size to volume units (size * 10000 for precision)
        const volume_units = @as(u64, @intCast(@as(i64, @intFromFloat(tick.size * 10000))));

        // Lock mutex for thread-safe grid update
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.data) |data| {
            const idx = row * self.time_buckets + col;
            if (idx < self.total_cells) {
                data[idx] += volume_units;

                // Update buy/sell tracking
                if (self.buy_data) |buy_data| {
                    if (tick.side == 0) {  // buy
                        buy_data[idx] += volume_units;
                    }
                }
                if (self.sell_data) |sell_data| {
                    if (tick.side == 1) {  // sell
                        sell_data[idx] += volume_units;
                    }
                }
            }
        }

        // Update metrics (atomic, no lock needed)
        _ = self.ticks_processed.fetchAdd(1, .release);
        _ = self.total_volume.fetchAdd(volume_units, .release);

        // Update per-exchange metrics
        if (tick.exchange_id < 3) {
            _ = self.exchange_ticks[tick.exchange_id].fetchAdd(1, .release);
            _ = self.exchange_volume[tick.exchange_id].fetchAdd(volume_units, .release);
            // Store last price as fixed-point integer (price in cents)
            // E.g., $70,660.50 → 7,066,050 cents
            const price_cents: u32 = @as(u32, @intFromFloat(@round(tick.price * 100.0)));
            self.exchange_last_price[tick.exchange_id].store(price_cents, .release);
        }
    }

    /// Get cell value (volume at price level & time)
    pub fn get_cell(self: *MarketMatrix, row: u32, col: u32) u64 {
        if (row >= self.price_rows or col >= self.time_buckets or self.data == null) {
            return 0;
        }

        const idx = row * self.time_buckets + col;
        return self.data.?[idx];
    }

    /// Get price for row
    pub fn get_price(self: *MarketMatrix, row: u32) f32 {
        return self.price_min + @as(f32, @floatFromInt(row)) * self.price_step;
    }

    /// Get buy/sell delta (buy - sell) for a cell
    pub fn get_cell_delta(self: *MarketMatrix, row: u32, col: u32) i64 {
        if (row >= self.price_rows or col >= self.time_buckets) return 0;

        self.mutex.lock();
        defer self.mutex.unlock();

        const idx = row * self.time_buckets + col;
        var buy_vol: i64 = 0;
        var sell_vol: i64 = 0;

        if (self.buy_data) |buy_data| {
            buy_vol = @as(i64, @intCast(buy_data[idx]));
        }
        if (self.sell_data) |sell_data| {
            sell_vol = @as(i64, @intCast(sell_data[idx]));
        }

        return buy_vol - sell_vol;
    }

    /// Find point of control (POC) - highest volume row
    pub fn find_poc(self: *MarketMatrix) struct { price: f32, volume: u64 } {
        if (self.data == null) return .{ .price = 0, .volume = 0 };

        var max_volume: u64 = 0;
        var poc_row: u32 = 0;

        for (0..self.price_rows) |row| {
            var row_volume: u64 = 0;

            for (0..self.time_buckets) |col| {
                row_volume += self.get_cell(@as(u32, @intCast(row)), @as(u32, @intCast(col)));
            }

            if (row_volume > max_volume) {
                max_volume = row_volume;
                poc_row = @as(u32, @intCast(row));
            }
        }

        return .{
            .price = self.get_price(poc_row),
            .volume = max_volume,
        };
    }

    /// Get column statistics (time period)
    pub fn get_column_volume(self: *MarketMatrix, col: u32) u64 {
        if (col >= self.time_buckets or self.data == null) return 0;

        var total: u64 = 0;
        for (0..self.price_rows) |row| {
            total += self.get_cell(@as(u32, @intCast(row)), col);
        }
        return total;
    }

    /// Get statistics
    pub fn get_stats(self: *MarketMatrix) struct {
        ticks_processed: u64,
        total_volume: u64,
        poc_price: f32,
        poc_volume: u64,
    } {
        const poc = self.find_poc();
        return .{
            .ticks_processed = self.ticks_processed.load(.acquire),
            .total_volume = self.total_volume.load(.acquire),
            .poc_price = poc.price,
            .poc_volume = poc.volume,
        };
    }

    /// Print ASCII visualization (simple)
    pub fn print_ascii(self: *MarketMatrix) !void {
        const stats = self.get_stats();
        std.debug.print("\n", .{});
        std.debug.print("Market Profile - Last 60 seconds\n", .{});
        std.debug.print("POC: ${:.2} ({d} volume units)\n", .{ stats.poc_price, stats.poc_volume });
        std.debug.print("Total: {d} ticks, {d} volume units\n\n", .{
            stats.ticks_processed,
            stats.total_volume,
        });

        // Print top 10 price levels
        var poc_list: std.ArrayList(struct { price: f32, volume: u64 }) = try std.ArrayList(
            struct { price: f32, volume: u64 },
        ).initCapacity(self.allocator, self.price_rows);
        defer poc_list.deinit();

        for (0..self.price_rows) |row| {
            var row_volume: u64 = 0;
            for (0..self.time_buckets) |col| {
                row_volume += self.get_cell(@as(u32, @intCast(row)), @as(u32, @intCast(col)));
            }

            if (row_volume > 0) {
                try poc_list.append(.{
                    .price = self.get_price(@as(u32, @intCast(row))),
                    .volume = row_volume,
                });
            }
        }

        // Sort descending by volume
        std.mem.sort(
            struct { price: f32, volume: u64 },
            poc_list.items,
            {},
            struct {
                pub fn lessThan(context: void, a: struct { price: f32, volume: u64 }, b: struct { price: f32, volume: u64 }) bool {
                    _ = context;
                    return a.volume > b.volume; // Descending
                }
            }.lessThan,
        );

        const limit = @min(10, poc_list.items.len);
        for (0..limit) |i| {
            const item = poc_list.items[i];
            std.debug.print("  ${:.2}: ", .{item.price});
            var j: u32 = 0;
            while (j < @min(item.volume / 1000, 50)) : (j += 1) {
                std.debug.print("█", .{});
            }
            std.debug.print(" {d}\n", .{item.volume});
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var matrix = try MarketMatrix.init(allocator);
    defer matrix.deinit();

    std.debug.print("✓ Market matrix initialized\n", .{});
    std.debug.print("  Rows: {d} (${:.2} - ${:.2})\n", .{ matrix.price_rows, matrix.price_min, matrix.price_max });
    std.debug.print("  Cols: {d} (60 seconds)\n", .{matrix.time_buckets});
}
