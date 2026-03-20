<template>
  <div class="exogrid-chart">
    <div class="status" :class="connected ? 'connected' : 'disconnected'">
      {{ connected ? '✓ Connected' : '✗ Disconnected' }}
    </div>
    <div class="stats">
      <div>Ticks: {{ tickCount }}</div>
      <div v-if="matrix">POC: ${{ matrix.poc_price?.toFixed(2) }}</div>
      <div v-if="matrix">Volume: {{ matrix.total_volume }}</div>
    </div>
    <canvas id="chart" width="800" height="600"></canvas>
  </div>
</template>

<script>
import { ExoGrid } from '../../js/index.js';

export default {
  name: 'ExoGridChart',
  props: {
    host: { type: String, default: 'localhost' },
    port: { type: Number, default: 9090 },
  },
  data() {
    return {
      exo: null,
      connected: false,
      tickCount: 0,
      matrix: null,
    };
  },
  mounted() {
    this.exo = new ExoGrid({ host: this.host, port: this.port });

    this.exo.on('connected', () => {
      this.connected = true;
    });

    this.exo.on('disconnected', () => {
      this.connected = false;
    });

    this.exo.on('tick', () => {
      this.tickCount++;
    });

    this.exo.on('matrix', (data) => {
      this.matrix = data;
    });

    this.exo.connect();
  },
  unmounted() {
    if (this.exo) {
      this.exo.disconnect();
    }
  },
};
</script>

<style scoped>
.exogrid-chart {
  padding: 20px;
  border: 1px solid #ccc;
  border-radius: 8px;
}

.status {
  font-weight: bold;
  margin-bottom: 10px;
}

.connected {
  color: #4caf50;
}

.disconnected {
  color: #f44336;
}

.stats {
  display: flex;
  gap: 20px;
  margin-bottom: 20px;
}

canvas {
  border: 1px solid #ddd;
}
</style>
