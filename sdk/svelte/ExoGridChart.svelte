<script>
  import { onMount, onDestroy } from 'svelte';
  import { ExoGrid } from '../../js/index.js';

  export let host = 'localhost';
  export let port = 9090;

  let exo;
  let connected = false;
  let tickCount = 0;
  let matrix = null;

  onMount(() => {
    exo = new ExoGrid({ host, port });

    exo.on('connected', () => {
      connected = true;
    });

    exo.on('disconnected', () => {
      connected = false;
    });

    exo.on('tick', () => {
      tickCount++;
    });

    exo.on('matrix', (data) => {
      matrix = data;
    });

    exo.connect();
  });

  onDestroy(() => {
    if (exo) exo.disconnect();
  });
</script>

<div class="exogrid-chart">
  <div class="status" class:connected class:disconnected={!connected}>
    {connected ? '✓ Connected' : '✗ Disconnected'}
  </div>

  <div class="stats">
    <div>Ticks: {tickCount}</div>
    {#if matrix}
      <div>POC: ${matrix.poc_price?.toFixed(2)}</div>
      <div>Volume: {matrix.total_volume}</div>
    {/if}
  </div>

  <canvas id="chart" width="800" height="600" />
</div>

<style>
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
