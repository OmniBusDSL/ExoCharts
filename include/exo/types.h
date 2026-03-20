// ExoGridChart Core Types
// C-compatible types for Zig/C++ interop

#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Represents a single market tick
typedef struct {
    float price;           ///< Price in USD
    float size;            ///< Order size
    uint8_t side;          ///< 0 = buy, 1 = sell
    uint64_t timestamp_ns; ///< Nanoseconds since Unix epoch
    uint32_t exchange_id;  ///< 0 = Coinbase, 1 = Kraken, 2 = LCX
} Tick_t;

/// Configuration for ExoGridChart
typedef struct {
    char grid_id[64];
    float min_price;
    float max_price;
    float tick_size;
    uint32_t time_period_ms;  // 60000 = 1 minute, 300000 = 5 minutes
    uint32_t exchange_id;
    char pair[16];  // "BTC-USD"
} GridConfig_t;

/// Volume aggregation cell in the matrix
typedef struct {
    uint64_t buy_volume;
    uint64_t sell_volume;
    uint32_t buy_count;
    uint32_t sell_count;
    uint8_t is_poc;  // Point of Control flag
} VolumeCell_t;

/// Imbalance metrics
typedef struct {
    uint64_t buy_volume;
    uint64_t sell_volume;
    int64_t cumulative_delta;
    float imbalance_ratio;  // buy / sell
} Imbalance_t;

/// WebSocket connection status
typedef enum {
    WS_DISCONNECTED = 0,
    WS_CONNECTING = 1,
    WS_CONNECTED = 2,
    WS_ERROR = 3
} WebSocketStatus_t;

#ifdef __cplusplus
}
#endif
