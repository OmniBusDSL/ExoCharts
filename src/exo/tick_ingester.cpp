// ExoGridChart TickIngester
// Consumes ticks from existing Zig-toolz-Assembly WebSocket implementations
// Day 1 Implementation - March 6, 2026

#include <iostream>
#include <thread>
#include <mutex>
#include <atomic>
#include <vector>
#include <functional>
#include <chrono>

#include "../include/exo/types.h"

// Forward declare Zig FFI (will link to compiled Zig code)
extern "C" {
    // From zig-toolz-Assembly/backend/src/ws/ws_client.zig
    typedef void (*ZigTickCallback)(const Tick_t* tick);

    int zig_ws_connect(const char* url);
    int zig_ws_start_streaming(ZigTickCallback callback);
    void zig_ws_stop();
    int zig_ws_get_status();
}

// ============================================================================
// TickIngester Class - Main entry point for tick consumption
// ============================================================================

class TickIngester {
private:
    static constexpr size_t RING_BUFFER_SIZE = 10000000;  // 10M ticks

    Tick_t* ring_buffer_;
    std::atomic<size_t> write_pos_{0};
    std::atomic<size_t> read_pos_{0};
    std::atomic<uint64_t> total_ticks_{0};
    std::mutex buffer_mutex_;

    std::thread stream_thread_;
    std::atomic<bool> running_{false};
    std::atomic<int> connection_status_{0};

    std::vector<std::function<void(const Tick_t&)>> tick_callbacks_;
    std::mutex callbacks_mutex_;

    std::chrono::high_resolution_clock::time_point start_time_;

    // Singleton instance for C callback access (global, not thread-local)
    static TickIngester* instance_ptr;

    static void tick_callback_bridge(const Tick_t* tick) {
        if (!tick) {
            std::cerr << "[TickIngester::tick_callback_bridge] NULL tick pointer!" << std::endl;
            return;
        }
        if (!instance_ptr) {
            std::cerr << "[TickIngester::tick_callback_bridge] NULL instance pointer!" << std::endl;
            return;
        }
        instance_ptr->push_tick(*tick);
    }

public:
    TickIngester() : start_time_(std::chrono::high_resolution_clock::now()) {
        // Allocate ring buffer
        ring_buffer_ = new Tick_t[RING_BUFFER_SIZE];
        if (!ring_buffer_) {
            std::cerr << "[TickIngester] Failed to allocate ring buffer!" << std::endl;
            throw std::runtime_error("Ring buffer allocation failed");
        }
        std::cout << "[TickIngester] Initialized with " << (RING_BUFFER_SIZE * sizeof(Tick_t)) / (1024*1024)
                  << "MB ring buffer" << std::endl;
    }

    ~TickIngester() {
        stop();
        if (ring_buffer_) {
            delete[] ring_buffer_;
        }
    }

    // ========================================================================
    // Connect to exchange via existing WebSocket
    // ========================================================================

    int connect(const char* exchange_url) {
        std::cout << "[TickIngester] Connecting to " << exchange_url << std::endl;

        connection_status_ = zig_ws_connect(exchange_url);
        if (connection_status_ != 0) {
            std::cerr << "[TickIngester] Connection failed!" << std::endl;
            return -1;
        }

        std::cout << "[TickIngester] Connected!" << std::endl;
        return 0;
    }

    // ========================================================================
    // Start streaming ticks
    // ========================================================================

    int start() {
        if (running_) {
            std::cerr << "[TickIngester] Already running!" << std::endl;
            return -1;
        }

        running_ = true;
        instance_ptr = this;  // Set singleton for callback bridge

        // Create thread to read from WebSocket
        stream_thread_ = std::thread([this]() {
            this->streaming_loop();
        });

        std::cout << "[TickIngester] Started streaming..." << std::endl;
        return 0;
    }

    // ========================================================================
    // Stop streaming
    // ========================================================================

    void stop() {
        if (!running_) return;

        std::cout << "[TickIngester] Stopping..." << std::endl;
        running_ = false;

        zig_ws_stop();

        if (stream_thread_.joinable()) {
            stream_thread_.join();
        }

        std::cout << "[TickIngester] Stopped. Total ticks: " << total_ticks_ << std::endl;
    }

    // ========================================================================
    // Register callback for each tick
    // ========================================================================

    void on_tick(std::function<void(const Tick_t&)> callback) {
        std::lock_guard<std::mutex> lock(callbacks_mutex_);
        tick_callbacks_.push_back(callback);
    }

    // ========================================================================
    // Push tick to ring buffer (called from Zig callback)
    // ========================================================================

    void push_tick(const Tick_t& tick) {
        // Get current write position
        size_t write_idx = write_pos_.load(std::memory_order_acquire) % RING_BUFFER_SIZE;

        // Store tick
        ring_buffer_[write_idx] = tick;

        // Increment write position
        write_pos_.fetch_add(1, std::memory_order_release);
        uint64_t total = total_ticks_.fetch_add(1, std::memory_order_relaxed);

        // Log every 10th tick during testing
        if ((total % 10) == 0) {
            std::cout << "[TickIngester::push_tick] #" << total << " Price: " << tick.price
                      << " Size: " << tick.size << std::endl;
        }

        // Call all registered callbacks
        {
            std::lock_guard<std::mutex> lock(callbacks_mutex_);
            for (auto& callback : tick_callbacks_) {
                callback(tick);
            }
        }
    }

    // ========================================================================
    // Get tick at index
    // ========================================================================

    bool get_tick(size_t index, Tick_t* out_tick) {
        if (index >= total_ticks_) {
            return false;
        }

        size_t read_idx = index % RING_BUFFER_SIZE;
        *out_tick = ring_buffer_[read_idx];
        return true;
    }

    // ========================================================================
    // Get recent ticks
    // ========================================================================

    std::vector<Tick_t> get_recent_ticks(size_t count) {
        std::vector<Tick_t> result;
        result.reserve(count);

        size_t total = total_ticks_.load();
        size_t start_idx = (total > count) ? (total - count) : 0;

        for (size_t i = start_idx; i < total && result.size() < count; ++i) {
            Tick_t tick;
            if (get_tick(i, &tick)) {
                result.push_back(tick);
            }
        }

        return result;
    }

    // ========================================================================
    // Metrics
    // ========================================================================

    uint64_t get_total_ticks() const {
        return total_ticks_.load();
    }

    int get_status() const {
        return connection_status_;
    }

    double get_throughput() {
        // Calculate ticks per second since object creation
        auto now = std::chrono::high_resolution_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time_).count();

        if (elapsed < 100) return 0.0;  // Require at least 100ms of data
        return (total_ticks_.load() * 1000.0) / static_cast<double>(elapsed);  // Ticks per second
    }

private:
    // ========================================================================
    // Streaming loop (runs in separate thread)
    // ========================================================================

    void streaming_loop() {
        std::cout << "[TickIngester::streaming_loop] Started" << std::endl;

        // Register callback with Zig WebSocket
        int result = zig_ws_start_streaming(tick_callback_bridge);

        if (result != 0) {
            std::cerr << "[TickIngester] Failed to start streaming!" << std::endl;
            running_ = false;
            return;
        }

        // Keep thread alive while streaming
        while (running_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        std::cout << "[TickIngester::streaming_loop] Ended" << std::endl;
    }
};

// Define global instance pointer for callback bridge
TickIngester* TickIngester::instance_ptr = nullptr;

// ============================================================================
// Global Instance & C Interface
// ============================================================================

static TickIngester* g_ingester = nullptr;

extern "C" {
    // Initialize ingester
    int exo_ingester_init() {
        if (g_ingester) {
            std::cerr << "[C API] Ingester already initialized!" << std::endl;
            return -1;
        }

        try {
            g_ingester = new TickIngester();
            std::cout << "[C API] TickIngester initialized" << std::endl;
            return 0;
        } catch (const std::exception& e) {
            std::cerr << "[C API] Failed to initialize: " << e.what() << std::endl;
            return -1;
        }
    }

    // Connect to exchange
    int exo_ingester_connect_coinbase() {
        if (!g_ingester) return -1;
        return g_ingester->connect("wss://ws-feed.exchange.coinbase.com");
    }

    int exo_ingester_connect_kraken() {
        if (!g_ingester) return -1;
        return g_ingester->connect("wss://ws.kraken.com");
    }

    int exo_ingester_connect_lcx() {
        if (!g_ingester) return -1;
        return g_ingester->connect("wss://wss.lcx.com/v1");
    }

    // Start/stop streaming
    int exo_ingester_start() {
        if (!g_ingester) return -1;
        return g_ingester->start();
    }

    void exo_ingester_stop() {
        if (g_ingester) {
            g_ingester->stop();
        }
    }

    // Get metrics
    uint64_t exo_ingester_get_total_ticks() {
        if (!g_ingester) return 0;
        return g_ingester->get_total_ticks();
    }

    double exo_ingester_get_throughput() {
        if (!g_ingester) return 0.0;
        return g_ingester->get_throughput();
    }

    // Cleanup
    void exo_ingester_deinit() {
        if (g_ingester) {
            g_ingester->stop();
            delete g_ingester;
            g_ingester = nullptr;
            std::cout << "[C API] TickIngester deinitialized" << std::endl;
        }
    }
}

// ============================================================================
// TEST: Standalone execution
// ============================================================================

#ifdef EXOGRIDCHART_TEST_INGESTER

int main() {
    std::cout << "╔════════════════════════════════════════╗" << std::endl;
    std::cout << "║  ExoGridChart TickIngester - TEST    ║" << std::endl;
    std::cout << "╚════════════════════════════════════════╝" << std::endl;

    // Initialize
    if (exo_ingester_init() != 0) {
        std::cerr << "Failed to initialize!" << std::endl;
        return 1;
    }

    // Connect to Coinbase
    std::cout << "\n[TEST] Connecting to Coinbase..." << std::endl;
    if (exo_ingester_connect_coinbase() != 0) {
        std::cerr << "Failed to connect!" << std::endl;
        exo_ingester_deinit();
        return 1;
    }

    // Start streaming
    std::cout << "[TEST] Starting stream..." << std::endl;
    if (exo_ingester_start() != 0) {
        std::cerr << "Failed to start!" << std::endl;
        exo_ingester_deinit();
        return 1;
    }

    // Wait for ticks
    std::cout << "[TEST] Waiting 10 seconds for ticks..." << std::endl;
    std::this_thread::sleep_for(std::chrono::seconds(10));

    // Show metrics
    std::cout << "\n[TEST] METRICS:" << std::endl;
    std::cout << "  Total Ticks: " << exo_ingester_get_total_ticks() << std::endl;
    std::cout << "  Throughput: " << exo_ingester_get_throughput() << " ticks/sec" << std::endl;

    // Cleanup
    exo_ingester_stop();
    exo_ingester_deinit();

    std::cout << "\n[TEST] Done!" << std::endl;
    return 0;
}

#endif
