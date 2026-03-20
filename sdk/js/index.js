/**
 * ExoGridChart JavaScript SDK
 * Real-time cryptocurrency market data streaming client
 *
 * Usage:
 *   const { ExoGrid } = require('exogridchart');
 *   const exo = new ExoGrid({ host: 'localhost', port: 9090 });
 *   exo.on('tick', (tick) => console.log(tick));
 *   exo.connect();
 */

const { EventEmitter } = require('events');

class ExoGrid extends EventEmitter {
  /**
   * Create a new ExoGrid client
   * @param {Object} options - Configuration
   * @param {string} options.host - Server hostname (default: 'localhost')
   * @param {number} options.port - Server port (default: 9090)
   * @param {number} options.pollInterval - Poll interval in ms (default: 1000)
   */
  constructor(options = {}) {
    super();
    this.host = options.host || 'localhost';
    this.port = options.port || 9090;
    this.pollInterval = options.pollInterval || 1000;
    this.baseUrl = `http://${this.host}:${this.port}`;
    this.connected = false;
    this.pollTimer = null;
    this.lastTicks = [];
  }

  /**
   * Connect and start polling for data
   */
  async connect() {
    if (this.connected) return;

    try {
      // Test connection
      const response = await this._fetch('/api/ticks');
      if (response.ok) {
        this.connected = true;
        this.emit('connected');
        this._startPolling();
        return;
      }
    } catch (err) {
      // Fall through to emit error
    }

    this.emit('error', new Error('Failed to connect to ExoGrid server'));
  }

  /**
   * Disconnect and stop polling
   */
  disconnect() {
    if (!this.connected) return;

    this.connected = false;
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    this.emit('disconnected');
  }

  /**
   * Get current market matrix
   * @param {string} ticker - Ticker ('BTC', 'ETH', 'XRP', 'LTC')
   * @param {string} timeframe - Timeframe ('1s', '5s', '1m', '5m')
   * @returns {Promise<Object>} Matrix data
   */
  async getMatrix(ticker = 'BTC', timeframe = '1s') {
    try {
      const response = await this._fetch(
        `/api/matrix?ticker=${ticker}&timeframe=${timeframe}`
      );
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return await response.json();
    } catch (err) {
      this.emit('error', err);
      return null;
    }
  }

  /**
   * Get tick counters
   * @returns {Promise<Object>} Tick counts per exchange
   */
  async getTickCounts() {
    try {
      const response = await this._fetch('/api/ticks');
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return await response.json();
    } catch (err) {
      this.emit('error', err);
      return null;
    }
  }

  /**
   * Start polling loop
   * @private
   */
  _startPolling() {
    this.pollTimer = setInterval(async () => {
      try {
        const data = await this.getMatrix();
        if (data) {
          this.emit('matrix', data);

          // Emit tick events if available
          if (data.last_ticks && Array.isArray(data.last_ticks)) {
            for (const tick of data.last_ticks) {
              this.emit('tick', tick);
            }
          }
        }
      } catch (err) {
        // Keep polling even on error
        this.emit('error', err);
      }
    }, this.pollInterval);
  }

  /**
   * Fetch helper with error handling
   * @private
   */
  async _fetch(path) {
    if (typeof fetch === 'undefined') {
      // Node.js environment - use node-fetch or built-in fetch
      const f = global.fetch || require('node-fetch');
      return await f(this.baseUrl + path);
    } else {
      // Browser environment
      return await fetch(this.baseUrl + path);
    }
  }
}

module.exports = { ExoGrid };
