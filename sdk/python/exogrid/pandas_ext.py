"""Pandas integration for ExoGridChart"""

import pandas as pd
from typing import Optional

def plot_exogrid(df: pd.DataFrame, **kwargs):
    """
    Plot ExoGridChart market profile from DataFrame

    Usage:
        df.exogrid.plot_matrix(ticker='BTC')
    """
    import matplotlib.pyplot as plt
    import matplotlib.patches as patches

    # Extract matrix data
    if 'price' not in df.columns or 'volume' not in df.columns:
        raise ValueError("DataFrame must have 'price' and 'volume' columns")

    fig, ax = plt.subplots(figsize=(12, 8))

    # Group by price and sum volume
    volume_by_price = df.groupby('price')['volume'].sum().sort_index()

    # Create horizontal bars
    ax.barh(volume_by_price.index, volume_by_price.values, height=10)
    ax.set_xlabel('Volume')
    ax.set_ylabel('Price ($)')
    ax.set_title('Market Profile - ExoGridChart')

    # Highlight POC
    max_idx = volume_by_price.idxmax()
    ax.axhline(y=max_idx, color='r', linestyle='--', label=f'POC: ${max_idx:.2f}')
    ax.legend()

    plt.tight_layout()
    return fig, ax

# Register with Pandas
@pd.api.extensions.register_dataframe_accessor("exogrid")
class ExoGridAccessor:
    def __init__(self, pandas_obj):
        self._obj = pandas_obj

    def plot_matrix(self, ticker='BTC', **kwargs):
        """Plot market profile matrix"""
        return plot_exogrid(self._obj, **kwargs)

    def ohlcv(self, price_col='price', volume_col='size', time_col=None):
        """Convert ticks to OHLCV bars"""
        if time_col is None:
            self._obj['time_bucket'] = pd.cut(self._obj.index, bins=60)
            time_col = 'time_bucket'

        return self._obj.groupby(time_col).agg({
            price_col: ['open', 'high', 'low', 'close'],
            volume_col: 'sum'
        }).rename(columns={
            price_col: 'price',
            volume_col: 'volume'
        })
