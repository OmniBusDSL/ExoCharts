/// <reference types="node" />

import { EventEmitter } from 'events';

/**
 * A single market trade/quote
 */
export interface Tick {
  price: number;        // Trade price in USD
  size: number;         // Trade volume
  side: 'buy' | 'sell'; // Buy or sell side
  timestamp_ns: bigint; // Nanosecond timestamp
  exchange_id: number;  // 0=Coinbase, 1=Kraken, 2=LCX
  ticker_id: number;    // 0=BTC, 1=ETH, 2=XRP, 3=LTC
}

/**
 * Market matrix statistics
 */
export interface MatrixStats {
  price_range: [number, number];      // Min/max price
  time_buckets: number;               // Number of time columns
  matrix: number[][];                 // 2D array of volumes
  buy_data: number[][];               // Buy volumes per cell
  sell_data: number[][];              // Sell volumes per cell
  ticks_processed: number;            // Total ticks ingested
  total_volume: number;               // Total volume traded
  poc_price: number;                  // Point of Control price
  poc_volume: number;                 // POC volume
  current_time_bucket: number;        // Current time index
  exchange_data: {                    // Per-exchange breakdown
    coinbase: { ticks: number; volume: number; last_price: number };
    kraken: { ticks: number; volume: number; last_price: number };
    lcx: { ticks: number; volume: number; last_price: number };
  };
}

/**
 * ExoGrid SDK Configuration
 */
export interface ExoGridOptions {
  host?: string;         // Server host (default: 'localhost')
  port?: number;         // Server port (default: 9090)
  pollInterval?: number; // Poll interval in ms (default: 1000)
}

/**
 * Main ExoGrid SDK class
 */
export class ExoGrid extends EventEmitter {
  constructor(options?: ExoGridOptions);

  /**
   * Connect to ExoGrid server
   */
  connect(): Promise<void>;

  /**
   * Disconnect from server
   */
  disconnect(): void;

  /**
   * Get current market matrix
   * @param ticker - Ticker symbol ('BTC', 'ETH', 'XRP', 'LTC')
   * @param timeframe - Timeframe ('1s', '5s', '1m', '5m')
   */
  getMatrix(ticker?: string, timeframe?: string): Promise<MatrixStats | null>;

  /**
   * Get tick counters
   */
  getTickCounts(): Promise<{
    coinbase: number;
    kraken: number;
    lcx: number;
    total: number;
  } | null>;

  /**
   * Event: Connected to server
   */
  on(event: 'connected', listener: () => void): this;

  /**
   * Event: Disconnected from server
   */
  on(event: 'disconnected', listener: () => void): this;

  /**
   * Event: New market matrix update
   */
  on(event: 'matrix', listener: (data: MatrixStats) => void): this;

  /**
   * Event: New tick received
   */
  on(event: 'tick', listener: (tick: Tick) => void): this;

  /**
   * Event: Error occurred
   */
  on(event: 'error', listener: (err: Error) => void): this;

  on(event: string, listener: (...args: any[]) => void): this;
}

export default ExoGrid;
