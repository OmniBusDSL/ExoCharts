"""
ExoGridChart Python SDK
Real-time cryptocurrency market data streaming

Usage:
    from exogrid import ExoGrid

    exo = ExoGrid(host='localhost', port=9090)
    exo.on_tick(lambda tick: print(tick))
    exo.connect()
"""

from .client import ExoGrid, Tick, MatrixStats

__version__ = '1.0.0'
__all__ = ['ExoGrid', 'Tick', 'MatrixStats']
