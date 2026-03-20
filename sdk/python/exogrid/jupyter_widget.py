"""Jupyter notebook widget for ExoGridChart"""

try:
    from ipywidgets import Output, HTML, HBox, VBox, Button, Text
    from IPython.display import display, clear_output
    import threading
except ImportError:
    raise ImportError("Jupyter widgets require ipywidgets and IPython")

from .client import ExoGrid

class ExoGridWidget:
    """Interactive Jupyter widget for ExoGridChart"""

    def __init__(self, host='localhost', port=9090):
        self.exo = ExoGrid(host=host, port=port)
        self.output = Output()
        self.controls = self._create_controls()

        # Register callbacks
        self.exo.on_connect(self._on_connect)
        self.exo.on_disconnect(self._on_disconnect)
        self.exo.on_tick(self._on_tick)
        self.exo.on_error(self._on_error)

        self.tick_count = 0
        self.matrix = None

    def _create_controls(self):
        """Create UI controls"""
        self.connect_btn = Button(description='Connect')
        self.disconnect_btn = Button(description='Disconnect', disabled=True)
        self.status_html = HTML(value='<b>Status:</b> Disconnected')

        self.connect_btn.on_click(lambda _: self._connect())
        self.disconnect_btn.on_click(lambda _: self._disconnect())

        return HBox([self.connect_btn, self.disconnect_btn, self.status_html])

    def _connect(self):
        """Connect to server"""
        self.connect_btn.disabled = True
        self.exo.connect()

    def _disconnect(self):
        """Disconnect from server"""
        self.disconnect_btn.disabled = True
        self.exo.disconnect()

    def _on_connect(self):
        """Handle connection"""
        self.connect_btn.disabled = True
        self.disconnect_btn.disabled = False
        self.status_html.value = '<b style="color:green">Status:</b> Connected'

    def _on_disconnect(self):
        """Handle disconnection"""
        self.connect_btn.disabled = False
        self.disconnect_btn.disabled = True
        self.status_html.value = '<b style="color:red">Status:</b> Disconnected'

    def _on_tick(self, tick):
        """Handle new tick"""
        self.tick_count += 1

    def _on_error(self, error):
        """Handle error"""
        with self.output:
            clear_output()
            print(f"❌ Error: {error}")

    def display(self):
        """Display the widget"""
        display(VBox([
            self.controls,
            self.output
        ]))
