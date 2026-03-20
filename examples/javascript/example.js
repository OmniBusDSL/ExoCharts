/**
 * ExoGridChart JavaScript SDK Example
 * Demonstrates how to use ExoGridChart from Node.js or browser
 *
 * Setup: npm install exogridchart
 * Run:   node example.js
 */

// For npm usage, import like this:
// const { ExoGrid } = require('exogridchart');

// For local testing, use the local version:
const { ExoGrid } = require('../../sdk/js/index.js');

async function main() {
    console.log('ExoGridChart JavaScript SDK Example');
    console.log('====================================\n');

    // Create client
    const exo = new ExoGrid({
        host: 'localhost',
        port: 9090,
        pollInterval: 1000, // Poll every 1 second
    });

    let tick_count = 0;
    let matrix_count = 0;

    // Handle connection
    exo.on('connected', () => {
        console.log('✅ Connected to ExoGrid server\n');
    });

    exo.on('disconnected', () => {
        console.log('❌ Disconnected from server');
        process.exit(0);
    });

    // Handle new ticks
    exo.on('tick', (tick) => {
        tick_count++;
        if (tick_count % 100 === 0) {
            const side = tick.side === 0 ? 'BUY' : 'SELL';
            console.log(
                `[Tick #${tick_count}] Exchange: ${tick.exchange_id} | Side: ${side} | ` +
                `Price: $${tick.price.toFixed(2)} | Size: ${tick.size.toFixed(8)}`
            );
        }
    });

    // Handle matrix updates
    exo.on('matrix', (matrix) => {
        matrix_count++;
        if (matrix_count % 10 === 0) {  // Print every 10 updates
            console.log(
                `[Matrix Update #${matrix_count}] ` +
                `Ticks: ${matrix.ticks_processed} | ` +
                `Volume: ${matrix.total_volume} | ` +
                `POC: $${matrix.poc_price.toFixed(2)}`
            );
        }
    });

    // Handle errors
    exo.on('error', (err) => {
        console.error('❌ Error:', err.message);
    });

    // Connect to server
    console.log('Connecting to ExoGrid server...');
    try {
        await exo.connect();
    } catch (err) {
        console.error('Failed to connect:', err.message);
        process.exit(1);
    }

    // Run for 10 seconds
    console.log('Streaming for 10 seconds... (Press Ctrl+C to stop)\n');
    setTimeout(() => {
        console.log('\n====================================');
        console.log(`Total ticks: ${tick_count}`);
        console.log(`Total matrix updates: ${matrix_count}`);
        console.log('Disconnecting...');
        exo.disconnect();
    }, 10000);
}

// Run
main().catch(console.error);
