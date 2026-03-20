/**
 * ExoGridChart C SDK Example
 * Demonstrates how to use ExoGridChart from C code
 *
 * Build: gcc -o example examples/c/example.c -L./zig-out/lib -lexogrid -lssl -lcrypto
 * Run:   ./example
 */

#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include "../../sdk/c/exogrid.h"

static volatile int running = 1;

/**
 * Signal handler to gracefully stop
 */
void signal_handler(int sig) {
    (void)sig;
    running = 0;
}

/**
 * Callback invoked on each new tick
 */
void on_tick(const Tick* tick) {
    if (!tick) return;

    static uint64_t count = 0;
    count++;

    // Print every 100th tick to avoid spam
    if (count % 100 == 0) {
        const char* side_str = (tick->side == 0) ? "BUY" : "SELL";
        printf("[Tick #%llu] Exchange: %u | Side: %s | Price: $%.2f | Size: %.8f\n",
               count, tick->exchange_id, side_str, tick->price, tick->size);
    }
}

int main(void) {
    printf("ExoGridChart C SDK Example\n");
    printf("==========================\n\n");

    // Setup signal handler for Ctrl+C
    signal(SIGINT, signal_handler);

    // Initialize SDK
    printf("Initializing SDK...\n");
    if (exo_init() != 0) {
        fprintf(stderr, "Failed to initialize SDK\n");
        return 1;
    }

    printf("Starting streams from all 3 exchanges...\n");

    // Start streaming from all 3 exchanges (0x7 = Coinbase | Kraken | LCX)
    if (exo_start(0x7, &on_tick) != 0) {
        fprintf(stderr, "Failed to start streams\n");
        exo_deinit();
        return 1;
    }

    printf("Streaming for 10 seconds... (Press Ctrl+C to stop)\n\n");

    // Stream for 10 seconds or until user interrupts
    for (int i = 0; i < 10 && running; i++) {
        sleep(1);

        // Print stats every second
        MatrixStats stats = exo_get_matrix_stats(0);  // 0 = BTC
        printf("[%2d/10] Ticks: %llu | Volume: %llu | Coinbase: %llu | Kraken: %llu | LCX: %llu\n",
               i + 1, stats.ticks_processed, stats.total_volume,
               stats.exchange_ticks[0], stats.exchange_ticks[1], stats.exchange_ticks[2]);
    }

    printf("\n");
    printf("==========================\n");
    printf("Total ticks received: %llu\n", exo_get_tick_count());

    printf("Stopping streams...\n");
    exo_stop();

    printf("Cleaning up...\n");
    exo_deinit();

    printf("Done!\n");
    return 0;
}
