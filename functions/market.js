const admin = require('firebase-admin');
const axios = require('axios');
const moment = require('moment-timezone');

const db = admin.database(); // Using Realtime Database for live data

// List of all Nifty 50 stock symbols
const NIFTY_STOCKS = [
    'ADANIENT', 'ADANIPORTS', 'APOLLOHOSP', 'ASIANPAINT', 'AXISBANK',
    'BAJAJ-AUTO', 'BAJFINANCE', 'BAJAJFINSV', 'BPCL', 'BHARTIARTL',
    'BRITANNIA', 'CIPLA', 'COALINDIA', 'DIVISLAB', 'DRREDDY',
    'EICHERMOT', 'GRASIM', 'HCLTECH', 'HDFCBANK', 'HDFCLIFE',
    'HEROMOTOCO', 'HINDALCO', 'HINDUNILVR', 'ICICIBANK', 'ITC',
    'INDUSINDBK', 'INFY', 'JSWSTEEL', 'KOTAKBANK', 'LTIM',
    'LT', 'M&M', 'MARUTI', 'NTPC', 'NESTLEIND',
    'ONGC', 'POWERGRID', 'RELIANCE', 'SBILIFE', 'SBIN',
    'SHRIRAMFIN', 'SUNPHARMA', 'TCS', 'TATACONSUM', 'TATAMOTORS',
    'TATASTEEL', 'TECHM', 'TITAN', 'ULTRACEMCO', 'WIPRO'
];

const NIFTY_STOCKS_NAMES = {
    'ADANIENT': 'Adani Enterprises',
    'ADANIPORTS': 'Adani Ports & SEZ',
    'APOLLOHOSP': 'Apollo Hospitals',
    'ASIANPAINT': 'Asian Paints',
    'AXISBANK': 'Axis Bank',
    'BAJAJ-AUTO': 'Bajaj Auto',
    'BAJFINANCE': 'Bajaj Finance',
    'BAJAJFINSV': 'Bajaj Finserv',
    'BPCL': 'Bharat Petroleum',
    'BHARTIARTL': 'Bharti Airtel',
    'BRITANNIA': 'Britannia Industries',
    'CIPLA': 'Cipla',
    'COALINDIA': 'Coal India',
    'DIVISLAB': 'Divi\'s Laboratories',
    'DRREDDY': 'Dr. Reddy\'s Laboratories',
    'EICHERMOT': 'Eicher Motors',
    'GRASIM': 'Grasim Industries',
    'HCLTECH': 'HCL Technologies',
    'HDFCBANK': 'HDFC Bank',
    'HDFCLIFE': 'HDFC Life Insurance',
    'HEROMOTOCO': 'Hero MotoCorp',
    'HINDALCO': 'Hindalco Industries',
    'HINDUNILVR': 'Hindustan Unilever',
    'ICICIBANK': 'ICICI Bank',
    'ITC': 'ITC Limited',
    'INDUSINDBK': 'IndusInd Bank',
    'INFY': 'Infosys',
    'JSWSTEEL': 'JSW Steel',
    'KOTAKBANK': 'Kotak Mahindra Bank',
    'LTIM': 'LTIMindtree',
    'LT': 'Larsen & Toubro',
    'M&M': 'Mahindra & Mahindra',
    'MARUTI': 'Maruti Suzuki',
    'NTPC': 'NTPC Limited',
    'NESTLEIND': 'Nestle India',
    'ONGC': 'Oil & Natural Gas Corp',
    'POWERGRID': 'Power Grid Corp',
    'RELIANCE': 'Reliance Industries',
    'SBILIFE': 'SBI Life Insurance',
    'SBIN': 'State Bank of India',
    'SHRIRAMFIN': 'Shriram Finance',
    'SUNPHARMA': 'Sun Pharmaceutical',
    'TCS': 'Tata Consultancy Services',
    'TATACONSUM': 'Tata Consumer Products',
    'TATAMOTORS': 'Tata Motors',
    'TATASTEEL': 'Tata Steel',
    'TECHM': 'Tech Mahindra',
    'TITAN': 'Titan Company',
    'ULTRACEMCO': 'UltraTech Cement',
    'WIPRO': 'Wipro'
};

/**
 * Helper to sleep for a given duration
 */
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

/**
 * Fetch Yahoo Finance data with retries and fallbacks
 */
const fetchYahooData = async (symbol, attempt = 1) => {
    const yahooSymbolMap = {
        'NIFTY50': '^NSEI',
        'BANKNIFTY': '^NSEBANK',
        'FINNIFTY': '^CNXFIN',
        'MIDCAPNIFTY': '^NSEMDCP50'
    };

    let yahooSymbol = yahooSymbolMap[symbol];
    if (!yahooSymbol) {
        if (symbol.startsWith('^') || symbol.endsWith('.NS')) {
            yahooSymbol = symbol;
        } else {
            yahooSymbol = `${symbol}.NS`;
        }
    }
    
    // Multi-tiered fallback endpoints
    const endpoints = [
        `https://query1.finance.yahoo.com/v8/finance/chart/${yahooSymbol}`,
        `https://query2.finance.yahoo.com/v8/finance/chart/${yahooSymbol}`
    ];

    const params = {
        interval: '5m',
        range: '3d', // Fetch 3 days to ensure we get enough historical data
        includePrePost: false
    };

    const headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Origin': 'https://finance.yahoo.com',
        'Referer': 'https://finance.yahoo.com/'
    };

    let lastError;

    for (const url of endpoints) {
        try {
            const response = await axios.get(url, { 
                params, 
                headers, 
                timeout: 8000,
                validateStatus: (status) => status === 200
            });

            if (!response.data || !response.data.chart || !response.data.chart.result) {
                throw new Error('Invalid Yahoo Finance response structure');
            }

            const result = response.data.chart.result[0];
            const quote = result.indicators.quote[0];
            const timestamps = result.timestamp;

            if (!timestamps || timestamps.length === 0) {
                throw new Error('No price data returned from Yahoo');
            }

            return {
                timestamps,
                open: quote.open,
                high: quote.high,
                low: quote.low,
                close: quote.close,
                volume: quote.volume
            };
        } catch (error) {
            lastError = error;
            const status = error.response ? error.response.status : null;
            
            console.warn(`[Yahoo] Attempt ${attempt} failed for ${symbol} using ${url}: ${error.message} (Status: ${status})`);

            // If throttled, don't try the next URL immediately on the same attempt
            if (status === 429) break; 
        }
    }

    // Retry logic with exponential backoff
    if (attempt < 3) {
        const delay = attempt * 2000;
        console.log(`[Yahoo] Retrying ${symbol} in ${delay}ms...`);
        await sleep(delay);
        return fetchYahooData(symbol, attempt + 1);
    }

    throw lastError || new Error(`Failed to fetch ${symbol} after multiple attempts`);
};

/**
 * Aggregate data into 5-minute candles
 */
const aggregateCandles = (data) => {
    const candles = {};

    for (let i = 0; i < data.timestamps.length; i++) {
        // Skip null data points which Yahoo occasionally returns
        if (data.open[i] === null || data.close[i] === null) continue;

        const timestamp = data.timestamps[i] * 1000; // Convert to milliseconds
        const candleKey = Math.floor(timestamp / (5 * 60 * 1000)) * (5 * 60 * 1000); // 5-minute intervals

        if (!candles[candleKey]) {
            candles[candleKey] = {
                open: data.open[i],
                high: data.high[i],
                low: data.low[i],
                close: data.close[i],
                volume: data.volume[i] || 0,
                timestamp: candleKey,
                // ✅ Required by CandleModel.fromRTDB
                timeStart: candleKey,
                timeEnd: candleKey + (5 * 60 * 1000),
                candleKey: candleKey.toString()
            };
        } else {
            candles[candleKey].high = Math.max(candles[candleKey].high, data.high[i]);
            candles[candleKey].low = Math.min(candles[candleKey].low, data.low[i]);
            candles[candleKey].close = data.close[i];
            candles[candleKey].volume += (data.volume[i] || 0);
        }
    }

    return candles;
};

/**
 * Check if market is open or near opening/closing
 * Expanded window for admin convenience
 */
const isMarketOpen = () => {
    const now = moment().tz('Asia/Kolkata');
    const dayOfWeek = now.day();
    const time = now.format('HH:mm');

    // Market is closed on weekends
    if (dayOfWeek === 0 || dayOfWeek === 6) {
        return false;
    }

    // Expanded window: 8:45 AM to 4:00 PM IST
    // (Real market: 9:15 AM to 3:40 PM)
    return time >= '08:45' && time <= '16:00';
};

/**
 * Fetch and update market data for all instruments
 */
exports.fetchAndUpdateMarketData = async () => {
    try {
        // Check if market is open
        if (!isMarketOpen()) {
            console.log('[Market] Outside active window. Skipping data fetch.');
            return null;
        }

        const instruments = ['NIFTY50', 'BANKNIFTY', 'FINNIFTY', 'MIDCAPNIFTY'];

        for (const instrument of instruments) {
            try {
                // Fetch Yahoo data
                const data = await fetchYahooData(instrument);

                // Aggregate into 5-minute candles
                const candles = aggregateCandles(data);

                // Get latest candle
                const sortedKeys = Object.keys(candles).sort((a, b) => Number(a) - Number(b));
                if (sortedKeys.length === 0) continue;

                const latestTimestamp = Number(sortedKeys[sortedKeys.length - 1]);
                const latestCandle = candles[latestTimestamp];

                // Update Realtime Database
                const ref = db.ref(`market_data/${instrument}`);

                // 1. Update status
                await ref.child('status').set({
                    connected: true,
                    lastUpdate: admin.database.ServerValue.TIMESTAMP,
                    source: 'yahoo',
                    candlesCount: sortedKeys.length
                });

                // 2. Update latest tick
                await ref.child('latest_tick').set({
                    price: latestCandle.close,
                    timestamp: latestTimestamp,
                    open: latestCandle.open,
                    high: latestCandle.high,
                    low: latestCandle.low,
                    volume: latestCandle.volume,
                    symbol: instrument
                });

                // 3. Update candles in bulk (keep last 500 for ~4 days of data)
                const candleKeysToUpdate = sortedKeys.slice(-500);
                const updates = {};
                
                for (const key of candleKeysToUpdate) {
                    updates[`candles/${key}`] = {
                        ...candles[key],
                        symbol: instrument
                    };
                }

                if (Object.keys(updates).length > 0) {
                    await ref.update(updates);
                }

                console.log(`[Market] Updated ${instrument} with ${candleKeysToUpdate.length} candles`);
            } catch (error) {
                console.error(`[Market] Error updating ${instrument}:`, error.message);

                // Mark as disconnected on error
                await db.ref(`market_data/${instrument}/status`).set({
                    connected: false,
                    lastUpdate: admin.database.ServerValue.TIMESTAMP,
                    error: error.message
                });
            }
        }

        // Fetch heatmap data as well during market hours
        try {
            await exports.fetchHeatmapData();
        } catch (err) {
            console.error('[Market] Error running fetchHeatmapData in fetchAndUpdateMarketData:', err.message);
        }

        return null;
    } catch (error) {
        console.error('[Market] Fatal error in fetchAndUpdateMarketData:', error);
        return null;
    }
};

/**
 * On-demand: fetch candles for one symbol, write to RTDB, return array.
 * No market-hours gate — always fetches last 3 days of 5-min data.
 */
exports.fetchAndReturnCandles = async (symbol) => {
    try {
        const data = await fetchYahooData(symbol);
        const candlesObj = aggregateCandles(data);
        const db = admin.database();
        const ref = db.ref(`market_data/${symbol}`);

        const sortedKeys = Object.keys(candlesObj).sort((a, b) => Number(a) - Number(b));
        if (sortedKeys.length === 0) {
            return { candles: [], symbol, error: 'No data returned' };
        }

        // Write all candles to RTDB
        const updates = {};
        const result = [];
        for (const key of sortedKeys) {
            updates[`candles/${key}`] = { ...candlesObj[key], symbol };
            result.push({ ...candlesObj[key], symbol });
        }
        await ref.update(updates);

        const latest = candlesObj[sortedKeys[sortedKeys.length - 1]];
        await ref.child('status').set({
            connected: true,
            lastUpdate: admin.database.ServerValue.TIMESTAMP,
            source: 'ondemand',
            candlesCount: sortedKeys.length
        });
        await ref.child('latest_tick').set({
            price: latest.close, timestamp: latest.timestamp,
            open: latest.open, high: latest.high,
            low: latest.low, volume: latest.volume, symbol
        });

        console.log(`[OnDemand] ${symbol}: wrote ${result.length} candles to RTDB`);
        return { candles: result, symbol, count: result.length };
    } catch (err) {
        console.error(`[OnDemand] ${symbol} error:`, err.message);
        return { candles: [], symbol, error: err.message };
    }
};

/**
 * Propagate NIFTY50 orderflow data injection to similar Nifty stocks
 */
exports.propagateOrderflow = async (niftyOrderflow) => {
    const candleKey = niftyOrderflow.candleKey;
    if (!candleKey) {
        console.warn('[Propagation] No candleKey provided. Skipping.');
        return;
    }

    console.log(`[Propagation] Starting propagation for candleKey ${candleKey}`);
    const db = admin.database();
    
    // Fetch NIFTY50 candle from RTDB
    let niftyCandleSnapshot = await db.ref(`market_data/NIFTY50/candles/${candleKey}`).once('value');
    let niftyCandle = niftyCandleSnapshot.val();

    if (!niftyCandle) {
        console.log(`[Propagation] NIFTY50 candle not found in RTDB for ${candleKey}. Seeding...`);
        try {
            await exports.fetchAndReturnCandles('NIFTY50');
            niftyCandleSnapshot = await db.ref(`market_data/NIFTY50/candles/${candleKey}`).once('value');
            niftyCandle = niftyCandleSnapshot.val();
        } catch (err) {
            console.error('[Propagation] Failed to seed NIFTY50 candles:', err.message);
        }
    }

    if (!niftyCandle) {
        console.warn(`[Propagation] NIFTY50 candle still not found for ${candleKey}. Skipping propagation.`);
        return;
    }

    // Detect extreme patterns
    const niftyRange = niftyCandle.high - niftyCandle.low;
    const niftyOpenEqualsHigh = niftyRange > 0 && (Math.abs(niftyCandle.open - niftyCandle.high) <= niftyRange * 0.015 || niftyCandle.open === niftyCandle.high);
    const niftyOpenEqualsLow = niftyRange > 0 && (Math.abs(niftyCandle.open - niftyCandle.low) <= niftyRange * 0.015 || niftyCandle.open === niftyCandle.low);

    console.log(`[Propagation] NIFTY50 candle pattern: openEqualsHigh=${niftyOpenEqualsHigh}, openEqualsLow=${niftyOpenEqualsLow}`);

    // Fetch niftyCandles once for previous direction comparison
    const niftySnapshot = await db.ref('market_data/NIFTY50/candles').once('value');
    const niftyCandles = niftySnapshot.val() || {};
    const sortedNiftyKeys = Object.keys(niftyCandles).sort((a, b) => Number(a) - Number(b));
    const niftyTargetIndex = sortedNiftyKeys.indexOf(candleKey);

    const firestore = admin.firestore();
    const firestoreBatch = firestore.batch();
    let writeCount = 0;

    const batchSize = 10;
    for (let i = 0; i < NIFTY_STOCKS.length; i += batchSize) {
        const chunk = NIFTY_STOCKS.slice(i, i + batchSize);
        await Promise.all(chunk.map(async (stockSymbol) => {
            try {
                let stockCandlesRef = db.ref(`market_data/${stockSymbol}/candles`);
                let snapshot = await stockCandlesRef.once('value');
                let candles = snapshot.exists() ? snapshot.val() : null;

                // Seed candles if missing or target candle is missing
                if (!candles || !candles[candleKey]) {
                    const yahooData = await fetchYahooData(stockSymbol);
                    candles = aggregateCandles(yahooData);
                    const updates = {};
                    for (const [k, v] of Object.entries(candles)) {
                        updates[k] = { ...v, symbol: stockSymbol };
                    }
                    await stockCandlesRef.update(updates);
                }

                let stockCandle = candles ? candles[candleKey] : null;
                if (!stockCandle) return;

                // Auto-adjust candle if NIFTY50 has open = high or open = low
                let candleChanged = false;
                if (niftyOpenEqualsHigh) {
                    stockCandle.open = stockCandle.high;
                    if (stockCandle.close > stockCandle.open) {
                        stockCandle.close = stockCandle.open;
                    }
                    candleChanged = true;
                } else if (niftyOpenEqualsLow) {
                    stockCandle.open = stockCandle.low;
                    if (stockCandle.close < stockCandle.open) {
                        stockCandle.close = stockCandle.open;
                    }
                    candleChanged = true;
                }

                if (candleChanged) {
                    await db.ref(`market_data/${stockSymbol}/candles/${candleKey}`).set(stockCandle);
                    // Update the local reference
                    candles[candleKey] = stockCandle;
                }

                // Check similarity
                const sortedKeys = Object.keys(candles).sort((a, b) => Number(a) - Number(b));
                const targetIndex = sortedKeys.indexOf(candleKey);

                let score = 0;
                if (targetIndex !== -1 && niftyTargetIndex !== -1) {
                    const n0 = niftyCandles[sortedNiftyKeys[niftyTargetIndex]];
                    const s0 = candles[sortedKeys[targetIndex]];
                    if ((n0.close >= n0.open) === (s0.close >= s0.open)) {
                        score += 2;
                    }

                    if (niftyTargetIndex > 0 && targetIndex > 0) {
                        const n1 = niftyCandles[sortedNiftyKeys[niftyTargetIndex - 1]];
                        const s1 = candles[sortedKeys[targetIndex - 1]];
                        if ((n1.close >= n1.open) === (s1.close >= s1.open)) {
                            score += 1;
                        }
                    } else {
                        score += 1;
                    }

                    if (niftyTargetIndex > 1 && targetIndex > 1) {
                        const n2 = niftyCandles[sortedNiftyKeys[niftyTargetIndex - 2]];
                        const s2 = candles[sortedKeys[targetIndex - 2]];
                        if ((n2.close >= n2.open) === (s2.close >= s2.open)) {
                            score += 1;
                        }
                    } else {
                        score += 1;
                    }
                }

                const isSimilar = score >= 3;
                if (isSimilar) {
                    const stockDocId = `${stockSymbol}_${candleKey}`;
                    const niftyTotal = niftyOrderflow.buyerCount + niftyOrderflow.sellerCount;
                    const buyerRatio = niftyTotal > 0 ? (niftyOrderflow.buyerCount / niftyTotal) : 0.5;

                    // Randomized volume scale: between 20% and 120%
                    const randomScale = 0.2 + Math.random() * 1.0;
                    const stockTotal = Math.max(10, Math.floor(niftyTotal * randomScale));
                    const stockBuyer = Math.floor(stockTotal * buyerRatio);
                    const stockSeller = stockTotal - stockBuyer;

                    const docData = {
                        candleKey: candleKey,
                        candleTime: niftyOrderflow.candleTime || Number(candleKey),
                        symbol: stockSymbol,
                        buyerCount: stockBuyer,
                        sellerCount: stockSeller,
                        bubbleScale: niftyOrderflow.bubbleScale !== undefined ? niftyOrderflow.bubbleScale : 5.0,
                        bubbleOpacity: niftyOrderflow.bubbleOpacity !== undefined ? niftyOrderflow.bubbleOpacity : 0.65,
                        bubbleGlow: niftyOrderflow.bubbleGlow !== undefined ? niftyOrderflow.bubbleGlow : 0.0,
                        showLabel: niftyOrderflow.showLabel !== undefined ? niftyOrderflow.showLabel : true,
                        isBigSignal: !!niftyOrderflow.isBigSignal,
                        isMediumSignal: !!niftyOrderflow.isMediumSignal,
                        isTrap: !!niftyOrderflow.isTrap,
                        isLiquidation: !!niftyOrderflow.isLiquidation,
                        customTag: niftyOrderflow.customTag || '',
                        pulseSpeed: niftyOrderflow.pulseSpeed !== undefined ? niftyOrderflow.pulseSpeed : 1.0,
                        borderColor: niftyOrderflow.borderColor || 'DEFAULT',
                        expiryTime: niftyOrderflow.expiryTime || null,
                        broadcastPush: false, // Don't spam push notifications
                        isInstitutional: false,
                        updatedBy: 'SYSTEM_PROPAGATION',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    };

                    firestoreBatch.set(firestore.collection('orderflow').doc(stockDocId), docData, { merge: true });
                    writeCount++;
                }
            } catch (err) {
                console.error(`[Propagation] Error processing stock ${stockSymbol}:`, err.message);
            }
        }));
    }

    if (writeCount > 0) {
        await firestoreBatch.commit();
        console.log(`[Propagation] Successfully propagated nifty orderflow to ${writeCount} stocks.`);
    } else {
        console.log('[Propagation] No similar stocks found to propagate.');
    }
};

let cachedHeatmapData = null;
let lastHeatmapFetchTime = 0;

/**
 * Fetch current trading data for all Nifty 50 stocks in chunks of 15 and write to RTDB
 */
exports.fetchHeatmapData = async () => {
    try {
        const now = Date.now();
        // Cache for 5 minutes (300,000 ms) to avoid Yahoo Finance rate limits
        if (cachedHeatmapData && (now - lastHeatmapFetchTime < 300000)) {
            console.log('[Heatmap] Returning cached heatmap data.');
            return cachedHeatmapData;
        }

        console.log('[Heatmap] Starting heatmap data fetch from Yahoo...');
        const heatmap = {};
        const batchSize = 15;

        for (let i = 0; i < NIFTY_STOCKS.length; i += batchSize) {
            const chunk = NIFTY_STOCKS.slice(i, i + batchSize);
            const symbols = chunk.map(s => `${s}.NS`).join(',');
            const url = `https://query1.finance.yahoo.com/v7/finance/spark?symbols=${symbols}&range=1d&interval=5m`;

            const headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
                'Accept': '*/*',
                'Accept-Language': 'en-US,en;q=0.9',
                'Origin': 'https://finance.yahoo.com',
                'Referer': 'https://finance.yahoo.com/'
            };

            try {
                const response = await axios.get(url, { headers, timeout: 8000 });
                if (response.data && response.data.spark && response.data.spark.result) {
                    for (const result of response.data.spark.result) {
                        const yahooSymbol = result.symbol;
                        const symbol = yahooSymbol.replace('.NS', '');
                        const meta = result.response[0]?.meta;
                        if (meta) {
                            const price = meta.regularMarketPrice;
                            const prevClose = meta.chartPreviousClose !== undefined ? meta.chartPreviousClose : meta.previousClose;
                            const changePercent = prevClose ? ((price - prevClose) / prevClose) * 100 : 0.0;
                            const dayOpen = meta.regularMarketDayOpen || meta.regularMarketPrice || 0;
                            const dayHigh = meta.regularMarketDayHigh || meta.regularMarketPrice || 0;
                            const dayLow = meta.regularMarketDayLow || meta.regularMarketPrice || 0;

                            heatmap[symbol] = {
                                price: price !== undefined ? price : 0.0,
                                open: dayOpen,
                                high: dayHigh,
                                low: dayLow,
                                changePercent: changePercent,
                                volume: meta.regularMarketVolume || 0,
                                name: NIFTY_STOCKS_NAMES[symbol] || symbol,
                                symbol: symbol,
                                lastUpdate: Date.now()
                            };
                        }
                    }
                }
            } catch (err) {
                console.error(`[Heatmap] Error fetching chunk starting at index ${i}:`, err.message);
            }
        }

        if (Object.keys(heatmap).length > 0) {
            await db.ref('market_data/nifty50_heatmap').set(heatmap);
            cachedHeatmapData = heatmap;
            lastHeatmapFetchTime = Date.now();
            console.log(`[Heatmap] Successfully updated heatmap data in RTDB for ${Object.keys(heatmap).length} stocks.`);
        } else {
            console.warn('[Heatmap] Heatmap aggregation returned empty.');
        }

        return heatmap;
    } catch (error) {
        console.error('[Heatmap] Fatal error updating heatmap data:', error);
        return null;
    }
};

exports.NIFTY_STOCKS = NIFTY_STOCKS;
