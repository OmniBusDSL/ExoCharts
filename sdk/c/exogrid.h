/**
 * ExoGridChart C SDK
 * Real-time multi-exchange crypto market data streaming
 *
 * Usage:
 *   gcc -o myapp myapp.c -L/path/to/lib -lexogrid -lssl -lcrypto
 *   ./myapp
 */

#ifndef EXOGRID_H
#define EXOGRID_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Tick - A single market trade
 * Represents one trade/quote from an exchange
 */
typedef struct {
    float price;           ///< Trade price in USD
    float size;            ///< Trade volume/quantity
    uint8_t side;          ///< 0=buy, 1=sell
    uint64_t timestamp_ns; ///< Nanosecond timestamp
    uint32_t exchange_id;  ///< 0=Coinbase, 1=Kraken, 2=LCX
    uint8_t ticker_id;     ///< 0=BTC, 1=ETH, 2=XRP, 3=LTC
} Tick;

/**
 * TickCallback - Function pointer for tick events
 * Called for each new trade received from the exchanges
 *
 * Example:
 *   void my_callback(const Tick* tick) {
 *       printf("Trade: %f @ %f\n", tick->price, tick->size);
 *   }
 */
typedef void (*TickCallback)(const Tick* tick);

/**
 * MatrixStats - Market profile statistics
 */
typedef struct {
    uint64_t ticks_processed;     ///< Total ticks ingested
    uint64_t total_volume;        ///< Total volume traded
    uint64_t exchange_ticks[3];   ///< Ticks per exchange (CB, Kraken, LCX)
} MatrixStats;

/**
 * Exchange IDs
 */
enum ExchangeId {
    EXCHANGE_COINBASE = 0,
    EXCHANGE_KRAKEN = 1,
    EXCHANGE_LCX = 2,
};

/**
 * Ticker IDs
 */
enum TickerId {
    TICKER_BTC = 0,
    TICKER_ETH = 1,
    TICKER_XRP = 2,
    TICKER_LTC = 3,
};

/**
 * ============================================================================
 * SDK Initialization & Lifecycle
 * ============================================================================
 */

/**
 * Initialize the SDK
 * Must be called once before any other function
 *
 * Returns:
 *   0: Success
 *  -1: Error
 */
int exo_init(void);

/**
 * Deinitialize the SDK
 * Stops all streams and frees all resources
 * Should be called before program exit
 */
void exo_deinit(void);

/**
 * Check if SDK is initialized
 */
bool exo_is_initialized(void);

/**
 * ============================================================================
 * Streaming Control
 * ============================================================================
 */

/**
 * Start streaming from selected exchanges
 *
 * Parameters:
 *   exchanges: Bitmask of exchanges to stream from
 *     - 0x1: Coinbase
 *     - 0x2: Kraken
 *     - 0x4: LCX
 *     - 0x7: All three exchanges
 *   callback: Function called on each tick (can be NULL for default handler)
 *
 * Returns:
 *   0: Success
 *  -1: Error
 *
 * Example:
 *   exo_start(0x7, &my_callback);  // Start all 3 exchanges
 */
int exo_start(uint32_t exchanges, TickCallback callback);

/**
 * Stop all streams
 */
void exo_stop(void);

/**
 * ============================================================================
 * Data Access
 * ============================================================================
 */

/**
 * Get total tick count across all exchanges
 *
 * Returns: Number of ticks received since exo_start()
 */
uint64_t exo_get_tick_count(void);

/**
 * Get market matrix statistics for a ticker
 *
 * Parameters:
 *   ticker_id: Which ticker (0=BTC, 1=ETH, 2=XRP, 3=LTC)
 *
 * Returns: MatrixStats struct with current statistics
 */
MatrixStats exo_get_matrix_stats(uint8_t ticker_id);

/**
 * ============================================================================
 * Ticker Names (Helper Functions)
 * ============================================================================
 */

/// Get full ticker name (e.g., "Bitcoin")
const char* exo_get_ticker_name(uint8_t ticker_id);

/// Get short ticker symbol (e.g., "BTC")
const char* exo_get_ticker_symbol(uint8_t ticker_id);

/// Get exchange name (e.g., "Coinbase")
const char* exo_get_exchange_name(uint8_t exchange_id);

#ifdef __cplusplus
}
#endif

#endif // EXOGRID_H
