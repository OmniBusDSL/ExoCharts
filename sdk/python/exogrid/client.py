"""ExoGrid Python Client"""

import requests
import threading
import time
from typing import Callable, Optional, Dict, Any
from dataclasses import dataclass

@dataclass
class Tick:
    """Market trade/quote"""
    price: float
    size: float
    side: str  # 'buy' or 'sell'
    timestamp_ns: int
    exchange_id: int  # 0=Coinbase, 1=Kraken, 2=LCX
    ticker_id: int  # 0=BTC, 1=ETH, 2=XRP, 3=LTC

@dataclass
class MatrixStats:
    """Market profile statistics"""
    ticks_processed: int
    total_volume: float
    poc_price: float
    poc_volume: int
    exchange_ticks: Dict[str, int]

class ExoGrid:
    """ExoGrid SDK Client"""

    def __init__(self, host: str = 'localhost', port: int = 9090, poll_interval: float = 1.0):
        self.host = host
        self.port = port
        self.base_url = f'http://{host}:{port}'
        self.poll_interval = poll_interval
        self.connected = False
        self.poll_thread: Optional[threading.Thread] = None

        # Callbacks
        self._tick_callbacks: list[Callable] = []
        self._matrix_callbacks: list[Callable] = []
        self._error_callbacks: list[Callable] = []
        self._connect_callbacks: list[Callable] = []
        self._disconnect_callbacks: list[Callable] = []

    def on_tick(self, callback: Callable[[Tick], None]) -> None:
        """Register callback for new ticks"""
        self._tick_callbacks.append(callback)

    def on_matrix(self, callback: Callable[[MatrixStats], None]) -> None:
        """Register callback for matrix updates"""
        self._matrix_callbacks.append(callback)

    def on_error(self, callback: Callable[[Exception], None]) -> None:
        """Register error callback"""
        self._error_callbacks.append(callback)

    def on_connect(self, callback: Callable[[], None]) -> None:
        """Register connection callback"""
        self._connect_callbacks.append(callback)

    def on_disconnect(self, callback: Callable[[], None]) -> None:
        """Register disconnection callback"""
        self._disconnect_callbacks.append(callback)

    def connect(self) -> bool:
        """Connect to ExoGrid server"""
        try:
            resp = requests.get(f'{self.base_url}/api/ticks', timeout=5)
            if resp.status_code == 200:
                self.connected = True
                for cb in self._connect_callbacks:
                    cb()
                self._start_polling()
                return True
        except Exception as e:
            self._emit_error(e)
        return False

    def disconnect(self) -> None:
        """Disconnect from server"""
        self.connected = False
        if self.poll_thread:
            self.poll_thread.join(timeout=2)
        for cb in self._disconnect_callbacks:
            cb()

    async def get_matrix(self, ticker: str = 'BTC', timeframe: str = '1s') -> Optional[Dict[str, Any]]:
        """Get market matrix (non-blocking)"""
        try:
            resp = requests.get(
                f'{self.base_url}/api/matrix',
                params={'ticker': ticker, 'timeframe': timeframe},
                timeout=5
            )
            return resp.json() if resp.status_code == 200 else None
        except Exception as e:
            self._emit_error(e)
            return None

    async def get_ticks(self) -> Optional[Dict[str, int]]:
        """Get tick counters"""
        try:
            resp = requests.get(f'{self.base_url}/api/ticks', timeout=5)
            return resp.json() if resp.status_code == 200 else None
        except Exception as e:
            self._emit_error(e)
            return None

    def _start_polling(self) -> None:
        """Start polling thread"""
        self.poll_thread = threading.Thread(target=self._poll_loop, daemon=True)
        self.poll_thread.start()

    def _poll_loop(self) -> None:
        """Polling loop"""
        while self.connected:
            try:
                resp = requests.get(f'{self.base_url}/api/matrix', timeout=5)
                if resp.status_code == 200:
                    data = resp.json()
                    # Emit matrix
                    for cb in self._matrix_callbacks:
                        try:
                            cb(data)
                        except Exception as e:
                            self._emit_error(e)
                time.sleep(self.poll_interval)
            except Exception as e:
                self._emit_error(e)
                time.sleep(self.poll_interval)

    def _emit_error(self, error: Exception) -> None:
        """Emit error to callbacks"""
        for cb in self._error_callbacks:
            try:
                cb(error)
            except:
                pass
