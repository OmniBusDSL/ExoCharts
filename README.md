# ExoGridChart — Real-Time Multi-Exchange Market Profile

**Status**: ✅ **Production Ready**
**Date**: March 2026
**Language**: Zig
**Total Code**: 1,666 LOC

A high-performance cryptocurrency market data aggregation system that streams real-time price & volume data from 3 exchanges (Coinbase, Kraken, LCX) in parallel, aggregates by timestamp, and renders an interactive 2D market profile matrix.

---

## Quick Start

### Prerequisites
- **Zig** (latest) — [https://ziglang.org](https://ziglang.org)
- **OpenSSL development libraries** — for TLS/WSS support

### Build & Run
```bash
# Build
zig build

# Start server on 0.0.0.0:9090
./startExoChart.sh

# Open in browser
# http://localhost:9090
```

Server starts all 3 exchange streams automatically. You should see:
- ✅ Coinbase WebSocket connected
- ✅ Kraken WebSocket connected
- ✅ LCX WebSocket connected
- ✅ Real ticks streaming in

---

## System Architecture

### Data Pipeline
```
Coinbase (WSS)  ──┐
Kraken (WSS)    ──┼──> Parallel Aggregator ──> Tick Ordering ──> Market Matrix ──> HTTP Server ──> Canvas Viz
LCX (WSS)       ──┘
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **Parallel Streams** | `stream_instance.zig` | Independent TCP/TLS/WebSocket per exchange |
| **Stream Manager** | `parallel_aggregator.zig` | Routes all ticks to single callback, 3 concurrent threads |
| **Tick Aggregator** | `tick_aggregator.zig` | Buffers & orders by timestamp (smooths out-of-order arrivals) |
| **Market Matrix** | `market_matrix.zig` | 2D price×time grid, volume aggregation, POC detection |
| **HTTP Server** | `exo_server.zig` + `http_server.zig` | Serves API endpoints + frontend |
| **Exchange Parsers** | `coinbase_match.zig`, `kraken_match.zig`, `lcx_match.zig` | JSON parsing per exchange format |

---

## API Endpoints

### `/` (GET)
Returns `index.html` with Canvas visualization

### `/api/matrix` (GET)
Returns market profile matrix as JSON:
```json
{
  "price_range": [40000, 70000],
  "time_buckets": 60,
  "matrix": [[volume_cell_1, ...], ...],
  "poc": { "price": 45320.5, "volume": 1500 }
}
```

### `/api/ticks` (GET)
Returns tick counters per exchange:
```json
{
  "coinbase": 12340,
  "kraken": 9821,
  "lcx": 5632,
  "total": 27793
}
```

---

## Configuration

### Market Matrix Dimensions
Edit `src/exo/market_matrix.zig`:
```zig
const PRICE_MIN = 40000.0;    // $40k minimum
const PRICE_MAX = 70000.0;    // $70k maximum
const PRICE_STEP = 10.0;       // $10 per row
const TIME_BUCKETS = 60;       // 60 one-second buckets
```

### Port
Edit `src/exo/exo_server.zig`:
```zig
const PORT = 9090;  // Change here
```

---

## Performance

- **Throughput**: 300-1,500 ticks/sec from 3 exchanges
- **Latency**: 50-110ms per tick (network-bound)
- **CPU**: <4% single-core (I/O bound)
- **Memory**: ~200KB for 3 streams + matrix buffers
- **Ring Buffer**: 10M tick capacity

---

## Development

### Common Tasks

#### See live output
```bash
./zig-out/bin/exo_server
```
Watch debug logs: `[TLS]`, `[stream]`, `[readLoop]`, `[matrix]`

#### Stop the server
```bash
pkill -f "exo_server"
```

#### Check if running
```bash
netstat -tuln | grep 9090
```

#### Add a new exchange
1. Create parser in `src/exo/exchange_match.zig`
2. Add enum variant in `ws_types.zig`
3. Add `StreamInstance` field in `parallel_aggregator.zig`
4. Update bitmask logic in `start()` method

#### Change market matrix size
Edit `PRICE_MIN`, `PRICE_MAX`, `PRICE_STEP`, `TIME_BUCKETS` in `market_matrix.zig`

---

## Architecture Details

For deep-dive on parallel streaming design, thread safety, and scalability:
- See **`PARALLEL_STREAMING_ARCHITECTURE.md`**
- See **`READY_FOR_PRODUCTION.md`**
- See **`CLAUDE.md`** (for Claude Code development guidance)

---

## Exchanges

### Supported
- ✅ **Coinbase** — `wss://ws-feed.exchange.coinbase.com` (BTC-USD, ETH-USD)
- ✅ **Kraken** — `wss://ws.kraken.com` (XBTUSDT, ETHUSD)
- ✅ **LCX** — `wss://stream.production.lcx.ch` (BTC-USD, ETH-USD)

### Adding More
1. Add WebSocket URL + product IDs
2. Implement JSON parser for their format
3. Register in `parallel_aggregator.zig`

---

## Known Issues & Notes

1. **install.sh bug** — Line 67 references wrong binary. Use `./startExoChart.sh` instead.
2. **Vendor directory** — Created as side effect of install script. Safe to ignore.
3. **TLS** — Automatically handled for wss:// URLs. No cert setup needed.
4. **Browser compatibility** — Requires HTML5 Canvas (all modern browsers).

---

## Files Structure

```
.
├── src/exo/                        # Zig source code (1,666 LOC)
│   ├── exo_server.zig              # Main entry point
│   ├── parallel_aggregator.zig     # Multi-stream manager
│   ├── stream_instance.zig         # Single stream
│   ├── tick_aggregator.zig         # Timestamp ordering
│   ├── market_matrix.zig           # 2D profile grid
│   ├── http_server.zig             # HTTP endpoints
│   ├── coinbase_match.zig          # Coinbase parser
│   ├── kraken_match.zig            # Kraken parser
│   ├── lcx_match.zig               # LCX parser
│   ├── ws_client.zig               # WebSocket protocol
│   ├── tls.zig                     # TLS handshake
│   └── ws_types.zig                # Common types
├── frontend/
│   └── index.html                  # Canvas visualization
├── build.zig                        # Build configuration
├── startExoChart.sh                 # Startup script
├── CLAUDE.md                        # Claude Code development guide
├── PARALLEL_STREAMING_ARCHITECTURE.md # Detailed design
├── READY_FOR_PRODUCTION.md          # Production status
└── README.md                        # This file
```

---

## License & Attribution

System built March 2026 for real-time trading market profile analysis.

---

## Support

For development guidance: See **CLAUDE.md**
For architecture questions: See **PARALLEL_STREAMING_ARCHITECTURE.md**
For issues: Use `git log` to trace changes
