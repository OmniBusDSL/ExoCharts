// Mock WebSocket implementation for TickIngester testing
// This will be replaced with actual Zig code in Days 2-3
// See: REUSE_STRATEGY.md for integration plan

#include <iostream>
#include <atomic>
#include <chrono>
#include <thread>
#include "../include/exo/types.h"

// Global state for mock
static std::atomic<int> mock_connection_status{0};
static std::atomic<bool> mock_streaming{false};
static std::atomic<uint64_t> mock_tick_count{0};

extern "C" {
    /// Connect to WebSocket URL
    /// Returns: 0 on success, -1 on failure
    int zig_ws_connect(const char* url) {
        std::cout << "[Mock WebSocket] Connecting to: " << url << std::endl;
        mock_connection_status = 1;  // Connected
        return 0;
    }

    /// Start streaming ticks with callback
    /// Returns: 0 on success, -1 on failure
    int zig_ws_start_streaming(void (*callback)(const Tick_t* tick)) {
        if (mock_connection_status != 1) {
            std::cerr << "[Mock WebSocket] Not connected!" << std::endl;
            return -1;
        }

        if (!callback) {
            std::cerr << "[Mock WebSocket] No callback provided!" << std::endl;
            return -1;
        }

        std::cout << "[Mock WebSocket] Starting tick stream with callback @ " << (void*)callback << std::endl;
        mock_streaming = true;

        // Simulate tick stream in background thread
        std::thread([callback]() {
            float base_price[] = {60000.0f, 2500.0f, 150.0f};
            int pair_idx = 0;

            while (mock_streaming) {
                // Generate simulated tick
                Tick_t tick;
                tick.price = base_price[pair_idx] + (rand() % 100 - 50) * 0.01f;
                tick.size = 0.1f + (rand() % 100) * 0.001f;
                tick.side = rand() % 2;
                tick.timestamp_ns = std::chrono::high_resolution_clock::now().time_since_epoch().count();
                tick.exchange_id = 0;  // Coinbase

                callback(&tick);
                mock_tick_count++;
                pair_idx = (pair_idx + 1) % 3;

                // Simulate network latency (~50ms between ticks)
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
        }).detach();

        return 0;
    }

    /// Stop streaming
    void zig_ws_stop() {
        std::cout << "[Mock WebSocket] Stopping stream..." << std::endl;
        mock_streaming = false;
    }

    /// Get connection status
    /// Returns: 0 = disconnected, 1 = connected, -1 = error
    int zig_ws_get_status() {
        return mock_connection_status;
    }

    /// Get total ticks generated (for mock testing)
    uint64_t zig_ws_get_tick_count() {
        return mock_tick_count;
    }
}
