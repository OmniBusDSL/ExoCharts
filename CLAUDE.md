# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**ExoGridChart** is a production-ready, real-time cryptocurrency market data aggregation system that streams live data from 3 exchanges (Coinbase, Kraken, LCX) in parallel, aggregates ticks by timestamp, and builds a 2D market profile matrix (price × time) for visualization.

**Key Facts:**
- **Language**: Zig (systems programming)
- **Status**: Complete & production-ready (1,666 LOC)
- **Architecture**: Parallel WebSocket streaming → timestamp aggregation → market matrix
- **Frontend**: HTML5 Canvas visualization (index.html)
- **Runtime**: HTTP server on port 9090

---

## Build & Run Commands

### Build from scratch
```bash
zig build
```

### Start the server
```bash
./startExoChart.sh
```
Server runs on `http://localhost:9090` with live market data from all 3 exchanges.

### Kill existing instances
```bash
pkill -f "exo_server"
```

### Fix permissions (if needed)
```bash
chmod +x ./zig-out/bin/exo_server
```

---

## Install Script Issue

The `install.sh` script has a bug on **line 67**: it tries to copy `exo_ws_test` (doesn't exist) instead of `exo_server` (the actual binary). The script creates unnecessary vendor directories as a side effect. When modifying `install.sh`, change:
```bash
cp zig-out/bin/exo_ws_test → cp zig-out/bin/exo_server
```

---

## Architecture

### High-Level Data Flow
```
Real Market Data (Coinbase, Kraken, LCX WebSocket)
    ↓
ParallelAggregator (manages 3 StreamInstance objects)
    ↓ (3 concurrent threads, exchange_id in Tick struct)
TickAggregator (priority queue, timestamp ordering)
    ↓
MarketMatrix (price × time 2D grid, 3000×60 cells)
    ↓
HTTP Server (exposes matrix + metrics as JSON)
    ↓
index.html (Canvas visualization)
```

### Key Files & Purpose

| File | Purpose |
|------|---------|
| `src/exo/parallel_aggregator.zig` | Manages 3 independent WebSocket streams, routes all ticks to callback |
| `src/exo/stream_instance.zig` | Single independent WebSocket stream (TCP, TLS, WebSocket handshake, read loop) |
| `src/exo/tick_aggregator.zig` | Priority queue for timestamp-ordered tick buffering |
| `src/exo/market_matrix.zig` | 2D price×time grid (180k cells), volume aggregation, POC detection |
| `src/exo/exo_server.zig` | HTTP server entry point, ties everything together |
| `src/exo/http_server.zig` | HTTP request handling, JSON endpoints |
| `src/exo/coinbase_match.zig` | Coinbase JSON parsing |
| `src/exo/kraken_match.zig` | Kraken JSON parsing |
| `src/exo/lcx_match.zig` | LCX JSON parsing |
| `src/exo/ws_types.zig` | Common WebSocket & tick types |
| `src/exo/ws_client.zig` | WebSocket protocol implementation (RFC 6455) |
| `src/exo/tls.zig` | TLS handshake for wss:// connections |
| `build.zig` | Zig build configuration (exo_server + exo_ws_test) |

### Thread Safety

- **ParallelAggregator**: Spawns 3 background threads (Coinbase, Kraken, LCX)
- Each thread independently reads WebSocket frames and calls the shared callback
- **TickAggregator**: Uses atomic operations for concurrent tick ingestion from 3 threads
- **MarketMatrix**: Atomic counters for tick count, volume, POC updates
- No mutexes (all I/O bound, lock-free design)

---

## Key Concepts

### StreamInstance (Independent Stream)
- Each exchange gets its own `StreamInstance` struct
- Holds: TCP socket, allocator, callback pointer, background thread, running flag
- Methods: `init()`, `connect()`, `start()`, `stop()`, `readLoop()`
- No global state—instances can run concurrently

### ParallelAggregator (Multi-Stream Manager)
- Holds 3 optional `StreamInstance` pointers (one per exchange)
- Methods: `init()`, `start(exchanges_bitmask, callback)`, `stop()`, `get_tick_count()`
- Exchange bitmask: `0x1`=Coinbase, `0x2`=Kraken, `0x4`=LCX, `0x7`=all
- Spawns all requested streams in parallel, all deliver to same callback

### TickAggregator (Timestamp Ordering)
- Priority queue buffers incoming ticks from 3 threads
- Sorts by timestamp before delivering to MarketMatrix
- 100-tick buffer smooths out-of-order arrivals from network
- Atomic metrics track total ticks, total volume

### MarketMatrix (2D Profile)
- Price rows (configurable: $40k-$70k with $10 steps = 3000 rows)
- Time columns (60 one-second buckets)
- Each cell aggregates volume for that price×time
- Detects Point of Control (POC)—price with most volume in time period
- ASCII visualization for debugging

---

## Exchange Integration

Each exchange requires custom JSON parsing because they use different formats:

- **Coinbase**: `type="last_match"`, fields: `price`, `size`, `side`
- **Kraken**: `event="trade"`, array of `[price, volume, time, side, type]`
- **LCX**: `type="trade"`, fields: `price`, `quantity`, `taker_type`

Parser modules (`coinbase_match.zig`, etc.) extract price and volume, emit normalized `Tick` struct.

---

## Common Development Tasks

### Add a new exchange
1. Create `src/exo/exchange_match.zig` with JSON parser
2. Add exchange enum variant in `ws_types.zig`
3. Add `StreamInstance` field in `parallel_aggregator.zig`
4. Update bitmask and `start()` logic

### Debug streaming
Run directly to see output:
```bash
./zig-out/bin/exo_server 2>&1 | head -100
```
Watch for `[TLS]`, `[stream]`, `[readLoop]` debug messages.

### Adjust market matrix dimensions
Edit `market_matrix.zig`:
- `PRICE_MIN`, `PRICE_MAX`, `PRICE_STEP`
- `TIME_BUCKETS` (number of one-second columns)

### Modify HTTP endpoints
Edit `src/exo/http_server.zig`:
- Add new routes in request handler
- Serialize matrix or metrics to JSON

---

## Known Issues & Notes

1. **install.sh bug** (line 67): Tries to copy nonexistent `exo_ws_test` binary. This creates spurious vendor directories. Fix by changing to `exo_server`.

2. **Vendor directory**: Populated by install script as side effect. Safe to delete if not needed.

3. **Frontend**: Single `index.html` file with embedded Canvas. No build step required—served directly by exo_server.

4. **Port 9090**: Hardcoded in exo_server. Change in `exo_server.zig` if needed.

5. **TLS certificates**: Coinbase/Kraken/LCX use valid certificates. No self-signed cert setup required for these.

---

## Testing & Verification

### See server output
```bash
./zig-out/bin/exo_server
# Ctrl+C to stop
```

### Check if server is running
```bash
netstat -tuln | grep 9090
```

### Check tick count
HTTP endpoint `/api/ticks` returns JSON with tick counters per exchange.

### Visual verification
Open `http://localhost:9090` in browser → see Canvas chart updating with live data.

---

## Performance Characteristics

- **Throughput**: 300-1,500 ticks/sec from 3 exchanges
- **CPU**: <4% total (all I/O bound)
- **Memory**: ~200KB for 3 streams
- **Latency**: 50-110ms per tick (dominated by network)
- **Ring buffer**: 10M tick capacity

---

## Git & Commits

- All code is committed to git
- Use `git log` to see feature progression
- No uncommitted changes should be in production

---

## References

- **Architecture details**: See `PARALLEL_STREAMING_ARCHITECTURE.md`
- **Production status**: See `READY_FOR_PRODUCTION.md`
- **Zig docs**: https://ziglang.org
- **WebSocket RFC 6455**: https://tools.ietf.org/html/rfc6455

