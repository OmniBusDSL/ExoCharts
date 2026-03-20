// ExoGridChart TickIngester Header
// C++ wrapper around Zig WebSocket implementations

#pragma once

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// TickIngester C Interface
// ============================================================================

/// Initialize the tick ingester
/// Returns: 0 on success, -1 on failure
int exo_ingester_init();

/// Connect to Coinbase WebSocket
int exo_ingester_connect_coinbase();

/// Connect to Kraken WebSocket
int exo_ingester_connect_kraken();

/// Connect to LCX WebSocket
int exo_ingester_connect_lcx();

/// Start streaming ticks
int exo_ingester_start();

/// Stop streaming ticks
void exo_ingester_stop();

/// Get total ticks received
uint64_t exo_ingester_get_total_ticks();

/// Get throughput (ticks per second)
double exo_ingester_get_throughput();

/// Cleanup
void exo_ingester_deinit();

#ifdef __cplusplus
}
#endif
