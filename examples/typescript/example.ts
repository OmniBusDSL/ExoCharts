/**
 * ExoGridChart TypeScript SDK Example
 * Demonstrates type-safe usage from TypeScript
 *
 * Setup: npm install typescript ts-node
 * Run:   npx ts-node example.ts
 */

import { ExoGrid, Tick, MatrixStats } from '../../sdk/js/index';

async function main(): Promise<void> {
    console.log('ExoGridChart TypeScript SDK Example');
    console.log('===================================\n');

    // Create client with type safety
    const exo = new ExoGrid({
        host: 'localhost',
        port: 9090,
        pollInterval: 1000,
    });

    let tickCount: number = 0;
    let totalVolume: number = 0;

    // Handle connection (fully typed)
    exo.on('connected', (): void => {
        console.log('✅ Connected to ExoGrid server\n');
    });

    exo.on('disconnected', (): void => {
        console.log('❌ Disconnected');
        process.exit(0);
    });

    // Handle ticks with full type information
    exo.on('tick', (tick: Tick): void => {
        tickCount++;
        totalVolume += tick.size;

        if (tickCount % 100 === 0) {
            const sideStr: string = tick.side === 0 ? 'BUY' : 'SELL';
            const exchangeNames: Record<number, string> = {
                0: 'Coinbase',
                1: 'Kraken',
                2: 'LCX',
            };

            console.log(
                `[Tick #${tickCount}] ` +
                `${exchangeNames[tick.exchange_id]}: ` +
                `${sideStr} $${tick.price.toFixed(2)} × ${tick.size.toFixed(8)}`
            );
        }
    });

    // Handle matrix updates with full type information
    exo.on('matrix', (matrix: MatrixStats): void => {
        const pocPrice: number = matrix.poc_price;
        const pocVolume: number = matrix.poc_volume;
        const totalTicks: number = matrix.ticks_processed;

        console.log(
            `[Matrix] POC: $${pocPrice.toFixed(2)} (${pocVolume} vol) | ` +
            `Total ticks: ${totalTicks} | Total volume: ${totalVolume.toFixed(2)}`
        );
    });

    // Handle errors with type safety
    exo.on('error', (err: Error): void => {
        console.error('❌ Error:', err.message);
    });

    // Connect with async/await
    try {
        console.log('Connecting to ExoGrid server...');
        await exo.connect();
    } catch (err) {
        console.error('Failed to connect:', err instanceof Error ? err.message : String(err));
        process.exit(1);
    }

    // Run for 10 seconds
    console.log('Streaming for 10 seconds...\n');

    setTimeout((): void => {
        console.log('\n===================================');
        console.log(`Total ticks received: ${tickCount}`);
        console.log(`Total volume: ${totalVolume.toFixed(2)}`);
        console.log('Disconnecting...');
        exo.disconnect();
    }, 10000);
}

// Run with error handling
main().catch((err: Error): void => {
    console.error('Fatal error:', err);
    process.exit(1);
});
