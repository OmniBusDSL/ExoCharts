# ExoGridChart SDK Documentation

Multi-language SDK for real-time cryptocurrency market data streaming from 3 exchanges (Coinbase, Kraken, LCX).

**Status**: ✅ Production Ready
**Version**: 1.0.0
**Supported Languages**: Zig, C/C++, JavaScript/Node.js, TypeScript

---

## Table of Contents

1. [Installation](#installation)
2. [Zig SDK](#zig-sdk)
3. [C SDK](#c-sdk)
4. [JavaScript SDK](#javascript-sdk)
5. [Architecture](#architecture)
6. [API Reference](#api-reference)
7. [Examples](#examples)
8. [Troubleshooting](#troubleshooting)

---

## Installation

### Build the SDK

```bash
# Build static + shared C libraries
zig build sdk

# Output:
# zig-out/lib/libexogrid.a    (static)
# zig-out/lib/libexogrid.so   (shared)
# zig-out/include/exogrid.h   (C header)
```

### Build Everything (executable + SDK)

```bash
zig build       # Default: builds exo_server + exo_ws_test
zig build sdk   # SDK libraries only
zig build-all   # Both
```

---

## Zig SDK

### Installation

```zig
const exogrid = @import("path/to/sdk/zig/exogrid.zig");
```

Or import the whole codebase in your `build.zig`:

```zig
const exogrid_module = b.createModule(.{
    .root_source_file = b.path("path/to/sdk/zig/exogrid.zig"),
});
```

### Basic Usage

```zig
const std = @import("std");
const exogrid = @import("exogrid.zig");

fn onTick(tick_opt: ?*const exogrid.Tick) void {
    if (tick_opt) |tick| {
        std.debug.print("Trade: ${:.2} x {:.8}\n", .{ tick.price, tick.size });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create aggregator (manages 3 parallel WebSocket streams)
    var aggregator = exogrid.ParallelAggregator.init(allocator);
    defer aggregator.deinit();

    // Start streaming (0x7 = all 3 exchanges)
    try aggregator.start(0x7, &onTick);

    // Let it run for 10 seconds
    std.time.sleep(10 * std.time.ns_per_s);

    aggregator.stop();
}
```

### Key Types

```zig
pub const Tick = struct {
    price: f32,           // Trade price
    size: f32,            // Trade volume
    side: u8,             // 0=buy, 1=sell
    timestamp_ns: u64,    // Nanosecond timestamp
    exchange_id: u32,     // 0=Coinbase, 1=Kraken, 2=LCX
    ticker_id: u8,        // 0=BTC, 1=ETH, 2=XRP, 3=LTC
};

pub const ParallelAggregator = struct {
    /// Initialize aggregator
    pub fn init(allocator: std.mem.Allocator) ParallelAggregator;

    /// Start streaming (exchanges: bitmask 0x1=CB, 0x2=Kraken, 0x4=LCX)
    pub fn start(self: *ParallelAggregator, exchanges: u32, callback: TickCallback) !void;

    /// Stop all streams
    pub fn stop(self: *ParallelAggregator) void;

    /// Get total tick count
    pub fn get_tick_count(self: *ParallelAggregator) u64;
};

pub const MarketMatrix = struct {
    /// Initialize market profile grid
    pub fn init(allocator: std.mem.Allocator) !MarketMatrix;

    /// Ingest a tick (thread-safe)
    pub fn ingest(self: *MarketMatrix, tick: *const Tick) !void;

    /// Find Point of Control (highest volume price)
    pub fn find_poc(self: *MarketMatrix) struct { price: f32, volume: u64 };

    /// Get cell volume (price row, time column)
    pub fn get_cell(self: *MarketMatrix, row: u32, col: u32) u64;
};
```

### Running the Example

```bash
cd examples/zig
zig build-exe example.zig -I /path/to/sdk/zig
./example
```

---

## C SDK

### Installation

```c
#include "exogrid.h"
```

Compile:

```bash
# Static linking
gcc -o myapp myapp.c -L./zig-out/lib -lexogrid -lssl -lcrypto

# Dynamic linking
gcc -o myapp myapp.c -L./zig-out/lib -lexogrid -Wl,-rpath,./zig-out/lib -lssl -lcrypto
```

### Basic Usage

```c
#include "exogrid.h"
#include <stdio.h>

void my_callback(const Tick* tick) {
    if (!tick) return;
    printf("Trade: $%.2f x %.8f\n", tick->price, tick->size);
}

int main(void) {
    // Initialize SDK
    if (exo_init() != 0) {
        fprintf(stderr, "Init failed\n");
        return 1;
    }

    // Start streaming (0x7 = all 3 exchanges)
    if (exo_start(0x7, &my_callback) != 0) {
        fprintf(stderr, "Start failed\n");
        exo_deinit();
        return 1;
    }

    // Let it stream for 10 seconds
    sleep(10);

    // Cleanup
    exo_stop();
    exo_deinit();
    return 0;
}
```

### Key Functions

```c
// Lifecycle
int exo_init(void);                              // Initialize
void exo_deinit(void);                           // Cleanup
bool exo_is_initialized(void);                   // Check status

// Streaming
int exo_start(uint32_t exchanges, TickCallback callback);  // Start
void exo_stop(void);                             // Stop

// Data Access
uint64_t exo_get_tick_count(void);               // Total ticks
MatrixStats exo_get_matrix_stats(uint8_t ticker_id);      // Stats
```

### Running the Example

```bash
cd examples/c
gcc -o example example.c -L../../zig-out/lib -lexogrid -lssl -lcrypto
./example
```

---

## JavaScript & TypeScript SDK

### Installation (npm)

```bash
npm install exogridchart
```

Or use locally:

```bash
npm install /path/to/sdk/js
```

### Basic Usage (Node.js)

```javascript
const { ExoGrid } = require('exogridchart');

async function main() {
    const exo = new ExoGrid({
        host: 'localhost',
        port: 9090,
        pollInterval: 1000,  // Poll every 1 second
    });

    // Handle events
    exo.on('connected', () => {
        console.log('Connected!');
    });

    exo.on('tick', (tick) => {
        console.log(`Trade: $${tick.price.toFixed(2)} x ${tick.size}`);
    });

    exo.on('error', (err) => {
        console.error('Error:', err);
    });

    // Connect
    await exo.connect();

    // Run for 10 seconds
    setTimeout(() => {
        exo.disconnect();
    }, 10000);
}

main();
```

### Basic Usage (TypeScript)

Full type safety with automatic IDE completion:

```typescript
import { ExoGrid, Tick, MatrixStats } from 'exogridchart';

const exo = new ExoGrid({
    host: 'localhost',
    port: 9090,
    pollInterval: 1000,
});

// Type-safe tick handler
exo.on('tick', (tick: Tick): void => {
    console.log(`${tick.price.toFixed(2)} @ ${tick.size}`);
});

// Type-safe matrix handler
exo.on('matrix', (matrix: MatrixStats): void => {
    console.log(`POC: ${matrix.poc_price}`);
});

await exo.connect();
```

### Basic Usage (Browser)

```html
<script src="exogridchart.js"></script>
<script>
    const exo = new ExoGrid({ host: 'localhost', port: 9090 });

    exo.on('matrix', (data) => {
        console.log('POC:', data.poc_price);
    });

    exo.connect();
</script>
```

### Key Methods

```typescript
class ExoGrid extends EventEmitter {
    constructor(options?: ExoGridOptions);

    async connect(): Promise<void>;
    disconnect(): void;
    async getMatrix(ticker?: string, timeframe?: string): Promise<MatrixStats>;
    async getTickCounts(): Promise<{ coinbase, kraken, lcx, total }>;
}
```

### Events

| Event | Data | Description |
|-------|------|-------------|
| `'connected'` | (none) | Connected to server |
| `'disconnected'` | (none) | Disconnected from server |
| `'tick'` | Tick | New tick received |
| `'matrix'` | MatrixStats | Matrix update |
| `'error'` | Error | Error occurred |

### Running the Examples

**JavaScript:**
```bash
cd examples/javascript
npm install
node example.js
```

**TypeScript:**
```bash
npm install -g typescript ts-node
cd examples/typescript
npm install
ts-node example.ts
```

Or with npx:
```bash
npx ts-node examples/typescript/example.ts
```

---

## Architecture

### SDK Structure

```
sdk/
├── zig/
│   └── exogrid.zig           # Zig public API
├── c/
│   └── exogrid.h             # C header
└── js/
    ├── index.js              # JS implementation
    ├── index.d.ts            # TypeScript types
    └── package.json          # npm package
```

### Data Flow (Zig/C)

```
Exchange WebSocket (WSS)
    ↓ (TLS encrypted)
StreamInstance (independent per exchange)
    ↓ (3 parallel threads)
ParallelAggregator (routes to callback)
    ↓
TickCallback (user-provided function)
    ↓
MarketMatrix (aggregates price×time)
```

### Data Flow (JavaScript)

```
ExoGrid (JavaScript client)
    ↓
HTTP polling (1 Hz default)
    ↓
ExoGridChart server (/api/matrix endpoint)
    ↓
EventEmitter (emits 'tick', 'matrix' events)
```

---

## API Reference

### Exchange IDs

```c
#define EXCHANGE_COINBASE 0
#define EXCHANGE_KRAKEN   1
#define EXCHANGE_LCX      2
```

### Ticker IDs

```c
#define TICKER_BTC  0
#define TICKER_ETH  1
#define TICKER_XRP  2
#define TICKER_LTC  3
```

### Exchange Bitmask

```c
0x1  // Coinbase
0x2  // Kraken
0x4  // LCX
0x3  // Coinbase + Kraken
0x7  // All three
```

### Tick Structure

```c
typedef struct {
    float price;           // Trade price ($)
    float size;            // Trade quantity
    uint8_t side;          // 0=buy, 1=sell
    uint64_t timestamp_ns; // Nanosecond timestamp
    uint32_t exchange_id;  // 0=Coinbase, 1=Kraken, 2=LCX
    uint8_t ticker_id;     // 0=BTC, 1=ETH, 2=XRP, 3=LTC
} Tick;
```

---

## Examples

### Zig: Print first 10 ticks

```zig
var count: u32 = 0;

fn onTick(tick_opt: ?*const exogrid.Tick) void {
    if (tick_opt) |tick| {
        count += 1;
        if (count <= 10) {
            std.debug.print("#{d}: ${:.2}\n", .{ count, tick.price });
        }
    }
}
```

### C: Get BTC market profile

```c
MatrixStats stats = exo_get_matrix_stats(TICKER_BTC);
printf("BTC: %llu ticks, $%.2f POC at volume %llu\n",
       stats.ticks_processed, poc_price, stats.total_volume);
```

### JavaScript: Stream to file

```javascript
const fs = require('fs');
const stream = fs.createWriteStream('ticks.jsonl');

exo.on('tick', (tick) => {
    stream.write(JSON.stringify(tick) + '\n');
});

exo.on('error', () => {
    stream.end();
});
```

---

## Troubleshooting

### "Connection refused" (C/JavaScript)

**Cause**: ExoGridChart server not running

**Solution**:
```bash
./startExoChart.sh
```

### "libexogrid.so not found" (C)

**Cause**: Library not in path

**Solution**:
```bash
export LD_LIBRARY_PATH=./zig-out/lib:$LD_LIBRARY_PATH
./example
```

Or compile with rpath:
```bash
gcc -o example example.c -L./zig-out/lib -lexogrid -Wl,-rpath,./zig-out/lib -lssl -lcrypto
```

### "OpenSSL not found" (build error)

**Cause**: OpenSSL dev libraries missing

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get install libssl-dev

# macOS
brew install openssl
```

### No ticks arriving

**Check**:
1. Is `exo_server` running? `netstat -tuln | grep 9090`
2. Are the exchanges online? Check status pages
3. Are exchanges selected? Make sure bitmask includes at least one exchange (0x1, 0x2, 0x4)

---

## Performance

- **Throughput**: 300-1,500 ticks/second (all 3 exchanges)
- **Latency**: 50-110ms per tick (network-bound)
- **CPU**: <4% single-core (I/O bound)
- **Memory**: ~1MB per language binding

---

## License

MIT

---

## Support

- **Documentation**: See README.md, CLAUDE.md
- **Issues**: GitHub issues
- **Examples**: See `examples/` directory

---

**Ready to stream real market data!** 🚀
