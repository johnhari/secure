const { YahooService } = require('./services/yahoo.service');

async function testYahoo() {
    console.log('--- Testing Yahoo Finance Service ---');
    const service = new YahooService();

    service.on('tick', (tick) => {
        console.log(`TICK RECEIVED: ${tick.symbol} Price: ${tick.price} Time: ${new Date(tick.timestamp).toLocaleTimeString()}`);
    });

    try {
        console.log('Fetching NIFTY50 historical candles...');
        const niftyCandles = await service.fetchIntradayCandles('NIFTY50');
        console.log(`Success: Received ${niftyCandles.length} candles for NIFTY50`);
        if (niftyCandles.length > 0) {
            console.log('First candle:', niftyCandles[0]);
            console.log('Last candle:', niftyCandles[niftyCandles.length - 1]);
        }

        console.log('\nFetching BANKNIFTY historical candles...');
        const bankNiftyCandles = await service.fetchIntradayCandles('BANKNIFTY');
        console.log(`Success: Received ${bankNiftyCandles.length} candles for BANKNIFTY`);

        console.log('\nStarting polling for live ticks (will wait 15 seconds)...');
        service.startPolling();

        await new Promise(resolve => setTimeout(resolve, 15000));

        console.log('\nClosing service...');
        service.close();
        console.log('Test complete.');
        process.exit(0);
    } catch (error) {
        console.error('Test failed:', error);
        process.exit(1);
    }
}

testYahoo();
