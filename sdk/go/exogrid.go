/*
Package exogrid provides Go bindings for the ExoGridChart SDK.

	import "github.com/SAVACAZAN/ExoGridChart/sdk/go"

	client, err := exogrid.Init()
	if err != nil {
		panic(err)
	}
	defer client.Deinit()

	client.Start(exogrid.AllExchanges, func(tick *exogrid.Tick) {
		fmt.Printf("Trade: $%.2f\n", tick.Price)
	})

	time.Sleep(10 * time.Second)
	client.Stop()
*/
package exogrid

/*
#cgo LDFLAGS: -lexogrid -lssl -lcrypto
#include "../../sdk/c/exogrid.h"
*/
import "C"

import (
	"fmt"
	"sync"
	"unsafe"
)

// Tick represents a single market trade
type Tick struct {
	Price      float32
	Size       float32
	Side       uint8 // 0=buy, 1=sell
	TimestampNs uint64
	ExchangeID uint32 // 0=Coinbase, 1=Kraken, 2=LCX
	TickerID   uint8  // 0=BTC, 1=ETH, 2=XRP, 3=LTC
}

// MatrixStats holds market profile statistics
type MatrixStats struct {
	TicksProcessed uint64
	TotalVolume    uint64
	ExchangeTicks  [3]uint64
}

// TickCallback is called for each new tick
type TickCallback func(*Tick)

// Client manages the ExoGrid connection
type Client struct {
	mu       sync.Mutex
	callback TickCallback
	started  bool
}

// Exchange constants
const (
	Coinbase = 0x1
	Kraken   = 0x2
	LCX      = 0x4
	AllExchanges = 0x7
)

// Ticker constants
const (
	BTC = 0
	ETH = 1
	XRP = 2
	LTC = 3
)

var (
	globalClient *Client
	globalMutex  sync.Mutex
)

// Init initializes the SDK
func Init() (*Client, error) {
	if C.exo_init() != 0 {
		return nil, fmt.Errorf("failed to initialize ExoGrid SDK")
	}
	return &Client{}, nil
}

// Deinit cleans up the SDK
func (c *Client) Deinit() {
	C.exo_deinit()
}

// Start begins streaming from selected exchanges
func (c *Client) Start(exchanges uint32, callback TickCallback) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.started {
		return fmt.Errorf("already started")
	}

	c.callback = callback
	globalClient = c

	// C callback wrapper
	if C.exo_start(C.uint32_t(exchanges), C.TickCallback(C.cgoTickCallback)) != 0 {
		return fmt.Errorf("failed to start streaming")
	}

	c.started = true
	return nil
}

// Stop halts all streams
func (c *Client) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.started {
		C.exo_stop()
		c.started = false
	}
}

// GetTickCount returns total ticks received
func (c *Client) GetTickCount() uint64 {
	return uint64(C.exo_get_tick_count())
}

// GetMatrixStats returns market statistics
func (c *Client) GetMatrixStats(tickerID uint8) MatrixStats {
	stats := C.exo_get_matrix_stats(C.uint8_t(tickerID))
	return MatrixStats{
		TicksProcessed: uint64(stats.ticks_processed),
		TotalVolume:    uint64(stats.total_volume),
		ExchangeTicks: [3]uint64{
			uint64(stats.exchange_ticks[0]),
			uint64(stats.exchange_ticks[1]),
			uint64(stats.exchange_ticks[2]),
		},
	}
}

// IsInitialized checks if SDK is ready
func (c *Client) IsInitialized() bool {
	return bool(C.exo_is_initialized())
}

// cgoTickCallback is the C callback wrapper
//export cgoTickCallback
func cgoTickCallback(tick *C.Tick) {
	globalMutex.Lock()
	client := globalClient
	globalMutex.Unlock()

	if client != nil && client.callback != nil {
		goTick := &Tick{
			Price:       float32(tick.price),
			Size:        float32(tick.size),
			Side:        uint8(tick.side),
			TimestampNs: uint64(tick.timestamp_ns),
			ExchangeID:  uint32(tick.exchange_id),
			TickerID:    uint8(tick.ticker_id),
		}
		client.callback(goTick)
	}
}
