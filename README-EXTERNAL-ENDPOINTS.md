# External Exchange Endpoints

Documentation of public API endpoints used by ExoGridChart to stream real-time market data.

---

## Coinbase

### WebSocket (Trade Stream)

**Endpoint**: `wss://ws-feed.exchange.coinbase.com`

**Products Subscribed**:
- `BTC-USD` — Bitcoin / US Dollar
- `ETH-USD` — Ethereum / US Dollar

**Message Type**: `last_match`

**Data Format**:
```json
{
  "type": "last_match",
  "trade_id": 984441757,
  "maker_order_id": "f3adf8a8-c2f0-445e-be8f-1cf99e9a2a45",
  "taker_order_id": "8bc53efc-d8f7-4058-8e23-cd9eec2ba113",
  "side": "buy",
  "size": "0.00000022",
  "price": "70065.81",
  "product_id": "BTC-USD",
  "sequence": 124535979538,
  "time": "2026-03-20T14:37:30.424477Z"
}
```

**Fields Used**:
- `price` — Trade price (string, converted to float)
- `size` — Trade volume (string, converted to float)
- `product_id` — Product identifier (BTC-USD, ETH-USD)
- `time` — Timestamp (RFC3339 format)

**Parser**: `src/exo/coinbase_match.zig`

**Rate Limits**: None (WebSocket subscription)

**Authentication**: Not required for public streams

**Documentation**: https://docs.cloud.coinbase.com/exchange/docs/websocket-channels#matches

---

## Kraken

### WebSocket (Trade Stream)

**Endpoint**: `wss://ws.kraken.com`

**Products Subscribed**:
- `XBTUSDT` — Bitcoin (ticker: XBTUSDT)
- `ETHUSD` — Ethereum (ticker: ETHUSD)

**Message Type**: `trade`

**Data Format**:
```json
{
  "channelID": 119930881,
  "channelName": "trade",
  "event": "trade",
  "pair": "XBT/USD",
  "data": [
    [
      "70065.8",
      "0.12345",
      1711020000.123,
      "s",
      "m"
    ]
  ]
}
```

**Fields Used** (array per trade):
- `[0]` — Price (string, converted to float)
- `[1]` — Volume (string, converted to float)
- `[2]` — Timestamp (Unix time, float)
- `[3]` — Side ("b"=buy, "s"=sell)
- `[4]` — Order type ("m"=market, "l"=limit)

**Parser**: `src/exo/kraken_match.zig`

**Rate Limits**: None (WebSocket subscription)

**Authentication**: Not required for public streams

**Documentation**: https://docs.kraken.com/websockets-v2/docs/categories/public-feeds

---

## LCX (Liquid Crypto Exchange)

### WebSocket (Trade Stream)

**Endpoint**: `wss://exchange-api.lcx.com/ws`

**Products Subscribed**:
- `BTC-USD` — Bitcoin / US Dollar
- `ETH-USD` — Ethereum / US Dollar

**Message Type**: `trade`

**Data Format**:
```json
{
  "channelID": 119930881,
  "channelName": "trade",
  "event": "trade",
  "data": {
    "price": "70065.81",
    "quantity": "0.12345",
    "timestamp": 1711020000123,
    "taker_type": "buy",
    "pair": "BTC-USD"
  }
}
```

**Fields Used**:
- `price` — Trade price (string, converted to float)
- `quantity` — Trade volume (string, converted to float)
- `timestamp` — Unix timestamp in milliseconds (integer)
- `taker_type` — Side ("buy", "sell")
- `pair` — Product identifier (BTC-USD, ETH-USD)

**Parser**: `src/exo/lcx_match.zig`

**Rate Limits**: None (WebSocket subscription)

**Authentication**: Not required for public streams

**Documentation**: LCX WebSocket documentation (internal API)

---

## Connection Details

### WebSocket Handshake

All three exchanges use standard RFC 6455 WebSocket protocol:

1. **TCP Connection** → Exchange server
2. **TLS Handshake** → Establish encrypted connection
3. **HTTP Upgrade** → Request WebSocket upgrade
4. **Frame Exchange** → Binary/text frames with market data

**Implementation**: `src/exo/ws_client.zig`, `src/exo/tls.zig`

### Subscription Messages

Each exchange receives a subscription message after handshake:

**Coinbase**:
```json
{
  "type": "subscribe",
  "product_ids": ["BTC-USD", "ETH-USD"],
  "channels": ["matches"]
}
```

**Kraken**:
```json
{
  "method": "subscribe",
  "params": {
    "channel": "trade",
    "pair": ["XBTUSDT", "ETHUSD"]
  }
}
```

**LCX**:
```json
{
  "method": "subscribe",
  "channels": [
    {"name": "trade", "pair": "BTC-USD"},
    {"name": "trade", "pair": "ETH-USD"}
  ]
}
```

---

## Data Processing Pipeline

```
Exchange WebSocket
    ↓ (TLS encrypted connection)
ws_client.zig (RFC 6455 frame parsing)
    ↓
exchange_match.zig (JSON parsing)
    ↓
Normalized Tick struct
    {
      exchange_id: u8,
      price: f64,
      volume: f64,
      timestamp: u64,
      product_id: [20]u8
    }
    ↓
parallel_aggregator.zig (callback dispatch)
    ↓
tick_aggregator.zig (timestamp ordering)
    ↓
market_matrix.zig (volume aggregation)
```

---

## Exchange Comparison

| Property | Coinbase | Kraken | LCX |
|----------|----------|--------|-----|
| **Endpoint** | wss://ws-feed.exchange.coinbase.com | wss://ws.kraken.com | wss://exchange-api.lcx.com/ws |
| **Protocol** | WebSocket (RFC 6455) | WebSocket (RFC 6455) | WebSocket (RFC 6455) |
| **Products** | BTC-USD, ETH-USD | XBTUSDT, ETHUSD | BTC-USD, ETH-USD |
| **Data Format** | JSON objects | JSON arrays | JSON objects |
| **Price Field** | `price` (string) | Array [0] (string) | `price` (string) |
| **Volume Field** | `size` (string) | Array [1] (string) | `quantity` (string) |
| **Timestamp** | RFC3339 string | Unix float (seconds) | Unix milliseconds |
| **Authentication** | Public (none) | Public (none) | Public (none) |
| **Rate Limit** | Unlimited | Unlimited | Unlimited |
| **TLS Version** | 1.2+ | 1.2+ | 1.2+ |

---

## Status & Monitoring

### Health Checks

**Coinbase**: https://status.pro.coinbase.com/
**Kraken**: https://status.kraken.com/
**LCX**: https://status.lcx.com/ (if available)

### In ExoGridChart

Debug output shows connection status:
```
[TLS] Connected: ws-feed.exchange.coinbase.com (TLS 1.2+)
[stream] TLS handshake complete (TLS 1.2+)
[stream] WebSocket upgrade successful (101 Switching Protocols)
[stream] WSS connected to ws-feed.exchange.coinbase.com:443
[stream] Subscription sent successfully
[readLoop] Starting for exchange=0
```

---

## API Versioning

| Exchange | API Version | Last Updated |
|----------|-------------|--------------|
| Coinbase | v2/WebSocket | 2024+ |
| Kraken | v2/WebSocket | 2024+ |
| LCX | v1/WebSocket | 2024+ |

---

## Security Notes

- ✅ **All connections use TLS 1.2+** — Encrypted traffic
- ✅ **No authentication required** — Public endpoints only
- ✅ **No API keys stored** — Stateless connections
- ✅ **Read-only access** — Market data only, no trading

---

## Rate Limits & Fair Use

- **Coinbase**: Unlimited WebSocket connections
- **Kraken**: Unlimited WebSocket connections
- **LCX**: Unlimited WebSocket connections

**Fair Use Policy**: Monitor for abnormal behavior and disconnect if needed

---

## Troubleshooting Connection Issues

### "Connection refused"
- Exchange server may be down
- Check: https://status.pro.coinbase.com/, https://status.kraken.com/

### "TLS handshake failed"
- OpenSSL not installed or outdated
- Check: `openssl version` (should be 1.1.1+ or 3.0+)

### "No data arriving"
- Subscription message may have been malformed
- Check: `./zig-out/bin/exo_server 2>&1` for debug logs

### "Slow or sporadic updates"
- Network latency
- Exchange may be under heavy load
- This is normal during high-volatility periods

---

**Last Updated**: March 2026
**Status**: ✅ All endpoints actively streaming
