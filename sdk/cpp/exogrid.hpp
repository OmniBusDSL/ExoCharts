/**
 * ExoGridChart C++ SDK (Header-only)
 * Modern C++ wrapper around C API
 *
 * #include "exogrid.hpp"
 * auto exo = exogrid::init();
 * exo->start(0x7, [](const exogrid::Tick& t) { ... });
 */

#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <stdexcept>

// C API declarations
extern "C" {
    struct Tick {
        float price;
        float size;
        uint8_t side;
        uint64_t timestamp_ns;
        uint32_t exchange_id;
        uint8_t ticker_id;
    };

    struct MatrixStats {
        uint64_t ticks_processed;
        uint64_t total_volume;
        uint64_t exchange_ticks[3];
    };

    typedef void (*TickCallback)(const Tick* tick);

    int exo_init(void);
    void exo_deinit(void);
    bool exo_is_initialized(void);
    int exo_start(uint32_t exchanges, TickCallback callback);
    void exo_stop(void);
    uint64_t exo_get_tick_count(void);
    MatrixStats exo_get_matrix_stats(uint8_t ticker_id);
}

namespace exogrid {

// Re-export C types
using Tick = ::Tick;
using MatrixStats = ::MatrixStats;
using TickCallback = std::function<void(const Tick&)>;

namespace {
    // Static callback adapter
    TickCallback* g_callback = nullptr;

    void c_callback_wrapper(const Tick* tick) {
        if (g_callback && tick) {
            (*g_callback)(*tick);
        }
    }
}

/**
 * ExoGrid client (RAII wrapper)
 */
class Client {
public:
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;

    /**
     * Initialize and start streaming
     */
    void start(uint32_t exchanges, const TickCallback& callback) {
        g_callback = new TickCallback(callback);
        int res = exo_start(exchanges, c_callback_wrapper);
        if (res != 0) {
            delete g_callback;
            g_callback = nullptr;
            throw std::runtime_error("Failed to start ExoGrid");
        }
    }

    /**
     * Stop streaming
     */
    void stop() {
        exo_stop();
        if (g_callback) {
            delete g_callback;
            g_callback = nullptr;
        }
    }

    /**
     * Get total tick count
     */
    uint64_t get_tick_count() const {
        return exo_get_tick_count();
    }

    /**
     * Get matrix statistics
     */
    MatrixStats get_matrix_stats(uint8_t ticker_id) const {
        return exo_get_matrix_stats(ticker_id);
    }

    /**
     * Check if initialized
     */
    bool is_initialized() const {
        return exo_is_initialized();
    }

    /**
     * Destructor - cleanup
     */
    ~Client() {
        stop();
        exo_deinit();
    }

private:
    Client() {
        if (exo_init() != 0) {
            throw std::runtime_error("Failed to initialize ExoGrid");
        }
    }

    friend std::unique_ptr<Client> init();
};

/**
 * Initialize SDK
 */
inline std::unique_ptr<Client> init() {
    return std::unique_ptr<Client>(new Client());
}

/**
 * Exchange identifiers
 */
enum Exchange : uint32_t {
    Coinbase = 0x1,
    Kraken = 0x2,
    LCX = 0x4,
    All = 0x7
};

/**
 * Ticker identifiers
 */
enum Ticker : uint8_t {
    BTC = 0,
    ETH = 1,
    XRP = 2,
    LTC = 3
};

} // namespace exogrid
