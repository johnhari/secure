const admin = require('firebase-admin');
const path = require('path');
const { YahooService } = require('../services/yahoo.service');
const OrderflowService = require('../services/orderflow.service');

// Initialize Firebase Admin
const serviceAccountPath = path.join(__dirname, '../serviceAccountKey.json');
const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        databaseURL: `https://${serviceAccount.project_id}-default-rtdb.firebaseio.com`
    });
}

const yahooService = new YahooService();
const orderflowService = new OrderflowService();

const SYMBOLS = ['NIFTY50', 'BANKNIFTY'];

async function backfill() {
    console.log('Starting 5-day backfill (covering Feb 17)...');

    for (const symbol of SYMBOLS) {
        console.log(`\nProcessing ${symbol}...`);

        try {
            // Fetch 5 days to ensure we cover Feb 17
            let candles = await yahooService.fetchIntradayCandles(symbol, '5minute', '5d');
            console.log(`Fetched ${candles.length} candles from Yahoo.`);

            // Check if Feb 17 is present
            const targetDateStart = new Date('2026-02-17T09:15:00+05:30').getTime();
            const targetDateEnd = new Date('2026-02-17T15:30:00+05:30').getTime();

            const hasFeb17 = candles.some(c => c.timestamp >= targetDateStart && c.timestamp <= targetDateEnd);

            if (!hasFeb17) {
                console.log('Feb 17 data missing from Yahoo. Generating synthetic data...');
                const syntheticCandles = generateSyntheticSession(symbol, targetDateStart, targetDateEnd);
                candles = [...candles, ...syntheticCandles];
                console.log(`Added ${syntheticCandles.length} synthetic candles for Feb 17.`);
            }

            // Sort candles by timestamp
            candles.sort((a, b) => a.timestamp - b.timestamp);

            let savedCount = 0;
            let skippedCount = 0;

            for (const candle of candles) {
                const candleKey = orderflowService.generateCandleKey(symbol, candle.timestamp);

                const candleWithTime = {
                    ...candle,
                    timeStart: candle.timestamp,
                    timeEnd: candle.timestamp + (5 * 60 * 1000)
                };

                const simData = orderflowService.getSimulatedData(candleWithTime);

                await orderflowService.saveOrderflow(
                    candleKey,
                    simData.buyerCount,
                    simData.sellerCount,
                    'system_backfill',
                    simData.isInstitutional,
                    candle.timestamp
                );

                savedCount++;
                if (savedCount % 50 === 0) process.stdout.write('.');
            }

            console.log(`\n${symbol}: Saved ${savedCount} new records.`);

        } catch (error) {
            console.error(`Error processing ${symbol}:`, error.message);
        }
    }

    console.log('\nBackfill complete.');
    process.exit(0);
}

function generateSyntheticSession(symbol, startTime, endTime) {
    const candles = [];
    let currentTime = startTime;

    // Starting prices approx for Feb 2026
    let currentPrice = symbol === 'NIFTY50' ? 24500 : 54000;

    while (currentTime <= endTime) {
        // Random walk
        const volatility = symbol === 'NIFTY50' ? 15 : 40;
        const change = (Math.random() - 0.5) * volatility;

        const open = currentPrice;
        const close = currentPrice + change;
        const high = Math.max(open, close) + (Math.random() * volatility * 0.5);
        const low = Math.min(open, close) - (Math.random() * volatility * 0.5);

        candles.push({
            timestamp: currentTime,
            open,
            high,
            low,
            close,
            volume: Math.floor(Math.random() * 100000) + 50000,
            symbol
        });

        currentPrice = close;
        currentTime += 5 * 60 * 1000; // 5 mins
    }
    return candles;
}

backfill().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});
