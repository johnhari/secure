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
        'NIFTY': '^NSEI',
        'BANKNIFTY': '^NSEBANK',
        'FINNIFTY': '^CNXFIN',
        'SENSEX': '^BSESN',
        'MIDCAPNIFTY': '^NSEMDCP50',
        'MIDCPNIFTY': '^NSMIDCP',
        'INDIA_VIX': '^INDIAVIX'
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
                volume: quote.volume,
                meta: result.meta
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
 * Aggregate data into 5-minute candles strictly within NSE market hours (09:15 to 15:40 IST)
 * Last valid 5m candle starts at 15:35 (runs 15:35 to 15:40).
 * Any post-market settlement tick (>= 15:40) is folded into the 15:35 candle, NOT creating a post-close candle.
 * Official EOD closing price from meta is applied to the 15:35 candle.
 */
const aggregateCandles = (data) => {
    const candles = {};
    const meta = data.meta || {};

    for (let i = 0; i < data.timestamps.length; i++) {
        // Skip null data points which Yahoo occasionally returns
        if (data.open[i] === null || data.close[i] === null) continue;

        const timestamp = data.timestamps[i] * 1000; // Convert to milliseconds
        const ist = moment(timestamp).tz('Asia/Kolkata');
        const dayOfWeek = ist.day();
        // Skip weekends
        if (dayOfWeek === 0 || dayOfWeek === 6) continue;

        const minuteOfDay = ist.hour() * 60 + ist.minute();
        // Pre-market check: skip before 09:15 IST (555 min)
        if (minuteOfDay < 555) continue;

        // In NSE, trading & post-close session runs until 15:40 IST (940 min).
        // Any settlement tick arriving at or after 15:40 belongs to the session closing candle.
        let candleTime;
        if (minuteOfDay >= 940) {
            candleTime = ist.clone().hour(15).minute(35).second(0).millisecond(0).valueOf();
        } else {
            const bucketMinute = Math.floor(ist.minute() / 5) * 5;
            candleTime = ist.clone().minute(bucketMinute).second(0).millisecond(0).valueOf();
        }

        const candleKey = candleTime;

        if (!candles[candleKey]) {
            candles[candleKey] = {
                open: data.open[i],
                high: data.high[i],
                low: data.low[i],
                close: data.close[i],
                volume: data.volume[i] || 0,
                timestamp: candleKey,
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

    // Apply official NSE EOD closing price from meta to final session candle
    const sortedKeys = Object.keys(candles).sort((a, b) => Number(a) - Number(b));
    if (sortedKeys.length > 0 && meta) {
        const daysMap = {};
        for (const key of sortedKeys) {
            const dayStr = moment(Number(key)).tz('Asia/Kolkata').format('YYYYMMDD');
            if (!daysMap[dayStr]) daysMap[dayStr] = [];
            daysMap[dayStr].push(candles[key]);
        }

        const todayIst = moment().tz('Asia/Kolkata');
        const todayStr = todayIst.format('YYYYMMDD');
        const currentMinuteOfDay = todayIst.hour() * 60 + todayIst.minute();
        const sortedDays = Object.keys(daysMap).sort();

        // 1. If today has finished trading (>= 15:40 IST = 940 min, 3:40 PM) or on weekend/after-hours:
        // Update today's final candle close with meta.regularMarketPrice (the official NSE EOD close)
        if (daysMap[todayStr] && currentMinuteOfDay >= 940 && meta.regularMarketPrice && meta.regularMarketPrice > 0) {
            const todayCandles = daysMap[todayStr];
            const lastCandle = todayCandles[todayCandles.length - 1];
            lastCandle.close = meta.regularMarketPrice;
            lastCandle.high = Math.max(lastCandle.high, meta.regularMarketPrice);
            lastCandle.low = Math.min(lastCandle.low, meta.regularMarketPrice);
        }

        // 2. Ensure previous completed trading day has official previous close
        const prevClose = meta.chartPreviousClose || meta.previousClose;
        if (prevClose && prevClose > 0) {
            const pastDays = sortedDays.filter(d => d < todayStr || (d === todayStr && currentMinuteOfDay >= 940));
            let prevTradingDayStr = null;
            if (currentMinuteOfDay < 940) {
                prevTradingDayStr = pastDays[pastDays.length - 1];
            } else if (pastDays.length >= 2) {
                prevTradingDayStr = pastDays[pastDays.length - 2];
            }

            if (prevTradingDayStr && daysMap[prevTradingDayStr]) {
                const prevDayCandles = daysMap[prevTradingDayStr];
                const lastPrevCandle = prevDayCandles[prevDayCandles.length - 1];
                lastPrevCandle.close = prevClose;
                lastPrevCandle.high = Math.max(lastPrevCandle.high, prevClose);
                lastPrevCandle.low = Math.min(lastPrevCandle.low, prevClose);
            }
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
                        bubbleScale: niftyOrderflow.bubbleScale !== undefined ? niftyOrderflow.bubbleScale : 3.0,
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
 * Fetch current trading data for all Nifty 50 stocks with live points and percentages
 */
exports.fetchHeatmapData = async () => {
    try {
        const now = Date.now();
        // Dynamic cache: 30 seconds for live market sync
        if (cachedHeatmapData && (now - lastHeatmapFetchTime < 30000)) {
            console.log('[Heatmap] Returning cached heatmap data.');
            return cachedHeatmapData;
        }

        console.log('[Heatmap] Starting heatmap data fetch with live points...');
        const heatmap = {};

        // 1. Primary: TradingView India Scanner (fetches 49+ stocks in single fast request)
        try {
            const mapTv = (s) => {
                if (s === 'BAJAJ-AUTO') return 'NSE:BAJAJ_AUTO';
                if (s === 'M&M') return 'NSE:M&M';
                if (s === 'TATAMOTORS') return 'NSE:TMCV';
                return `NSE:${s}`;
            };

            const tvTickers = NIFTY_STOCKS.map(mapTv);
            const tvUrl = 'https://scanner.tradingview.com/india/scan';
            const tvResp = await axios.post(tvUrl, {
                symbols: { tickers: tvTickers },
                columns: ['name', 'close', 'change', 'change_abs', 'open', 'high', 'low', 'volume', 'description']
            }, {
                headers: {
                    'Content-Type': 'application/json',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                },
                timeout: 8000
            });

            if (tvResp.data && tvResp.data.data) {
                const lookup = {};
                for (const item of tvResp.data.data) {
                    lookup[item.s] = item.d;
                }

                for (const symbol of NIFTY_STOCKS) {
                    const tvTicker = mapTv(symbol);
                    if (lookup[tvTicker]) {
                        const d = lookup[tvTicker];
                        const price = d[1] || 0.0;
                        const changePercent = d[2] || 0.0;
                        const changePts = d[3] || 0.0;
                        const dayOpen = d[4] || price;
                        const dayHigh = d[5] || price;
                        const dayLow = d[6] || price;
                        const volume = d[7] || 0;
                        const name = d[8] || NIFTY_STOCKS_NAMES[symbol] || symbol;

                        heatmap[symbol] = {
                            price: price,
                            change: changePts, // Real Points Change!
                            changePercent: changePercent,
                            open: dayOpen,
                            high: dayHigh,
                            low: dayLow,
                            volume: volume,
                            name: name,
                            symbol: symbol,
                            lastUpdate: Date.now()
                        };
                    }
                }
            }
        } catch (tvErr) {
            console.warn('[Heatmap] TradingView scan error, falling back to Yahoo:', tvErr.message);
        }

        // 2. Secondary: Yahoo Spark for any missing stocks
        const missing = NIFTY_STOCKS.filter(s => !heatmap[s]);
        if (missing.length > 0) {
            console.log(`[Heatmap] Fetching ${missing.length} missing stocks via Yahoo...`);
            const batchSize = 15;
            for (let i = 0; i < missing.length; i += batchSize) {
                const chunk = missing.slice(i, i + batchSize);
                const symbols = chunk.map(s => `${s}.NS`).join(',');
                const url = `https://query1.finance.yahoo.com/v7/finance/spark?symbols=${symbols}&range=1d&interval=5m`;
                const headers = {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                    'Origin': 'https://finance.yahoo.com',
                    'Referer': 'https://finance.yahoo.com/'
                };

                try {
                    const response = await axios.get(url, { headers, timeout: 6000 });
                    if (response.data && response.data.spark && response.data.spark.result) {
                        for (const result of response.data.spark.result) {
                            const yahooSymbol = result.symbol;
                            const symbol = yahooSymbol.replace('.NS', '');
                            const meta = result.response[0]?.meta;
                            if (meta) {
                                const price = meta.regularMarketPrice || 0.0;
                                const prevClose = meta.chartPreviousClose !== undefined ? meta.chartPreviousClose : (meta.previousClose || price);
                                const changePts = price - prevClose;
                                const changePercent = prevClose ? (changePts / prevClose) * 100 : 0.0;
                                const dayOpen = meta.regularMarketDayOpen || price;
                                const dayHigh = meta.regularMarketDayHigh || price;
                                const dayLow = meta.regularMarketDayLow || price;

                                heatmap[symbol] = {
                                    price: price,
                                    change: changePts,
                                    changePercent: changePercent,
                                    open: dayOpen,
                                    high: dayHigh,
                                    low: dayLow,
                                    volume: meta.regularMarketVolume || 0,
                                    name: NIFTY_STOCKS_NAMES[symbol] || symbol,
                                    symbol: symbol,
                                    lastUpdate: Date.now()
                                };
                            }
                        }
                    }
                } catch (err) {
                    console.error(`[Heatmap] Yahoo chunk error:`, err.message);
                }
            }
        }

        if (Object.keys(heatmap).length > 0) {
            await db.ref('market_data/nifty50_heatmap').set(heatmap);
            cachedHeatmapData = heatmap;
            lastHeatmapFetchTime = Date.now();
            console.log(`[Heatmap] Successfully updated heatmap data in RTDB for ${Object.keys(heatmap).length} stocks with live points.`);
        } else {
            console.warn('[Heatmap] Heatmap aggregation returned empty.');
        }

        return heatmap;
    } catch (error) {
        console.error('[Heatmap] Fatal error updating heatmap data:', error);
        return null;
    }
};

/**
 * Fetch and update Pre-Market Bias Data
 * Fetches TradingView Scanner + NSE FII/DII + Yahoo Fallback, writes to RTDB
 */
exports.fetchPreMarketBiasData = async () => {
    try {
        console.log('[PreMarketBias] Fetching real live bias data...');
        const biasData = {
            giftNifty: 0,
            giftNiftyChange: 0,
            giftNiftyPct: 0,
            expectedOpen: 'FLAT OPEN',
            expectedOpenType: 'FLAT',
            niftyPrevClose: 0,
            fiiNet: 0,
            diiNet: 0,
            fiiDiiDate: '',
            globalFutures: {},
            lastUpdated: Date.now()
        };

        // 1. TradingView Global Scanner
        try {
            const tvUrl = 'https://scanner.tradingview.com/global/scan';
            const tvBody = {
                symbols: {
                    tickers: [
                        'NSEIX:NIFTY1!',
                        'CBOT_MINI:YM1!',
                        'CME_MINI:NQ1!',
                        'XETR:DAX',
                        'TVC:NI225',
                        'NSE:NIFTY'
                    ]
                },
                columns: ['name', 'close', 'change', 'change_abs', 'description']
            };

            const tvRes = await axios.post(tvUrl, tvBody, {
                headers: { 
                    'Content-Type': 'application/json',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                },
                timeout: 7000
            });

            if (tvRes.data && tvRes.data.data) {
                for (const item of tvRes.data.data) {
                    const s = item.s;
                    const d = item.d;
                    const close = d[1];
                    const pct = d[2];
                    const chg = d[3];

                    if (s === 'NSEIX:NIFTY1!') {
                        biasData.giftNifty = close || 0;
                        biasData.giftNiftyPct = pct || 0;
                        biasData.giftNiftyChange = chg || 0;
                    } else if (s === 'NSE:NIFTY') {
                        biasData.niftyPrevClose = (close && chg) ? (close - chg) : close;
                    } else if (s === 'CBOT_MINI:YM1!') {
                        biasData.globalFutures['DOW FUT'] = `${chg >= 0 ? '+' : ''}${Math.round(chg)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`;
                    } else if (s === 'CME_MINI:NQ1!') {
                        biasData.globalFutures['NASDAQ FUT'] = `${chg >= 0 ? '+' : ''}${chg.toFixed(1)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`;
                    } else if (s === 'XETR:DAX') {
                        biasData.globalFutures['DAX'] = `${chg >= 0 ? '+' : ''}${chg.toFixed(1)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`;
                    } else if (s === 'TVC:NI225') {
                        biasData.globalFutures['NIKKEI'] = `${chg >= 0 ? '+' : ''}${Math.round(chg)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`;
                    }
                }
            }
        } catch (tvErr) {
            console.warn('[PreMarketBias] TradingView scanner error:', tvErr.message);
        }

        // 2. NSE FII / DII Provisional Data
        try {
            const nseRes = await axios.get('https://www.nseindia.com/api/fiidiiTradeReact', {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
                    'Accept': 'application/json, text/plain, */*',
                    'Referer': 'https://www.nseindia.com/'
                },
                timeout: 6000
            });

            if (Array.isArray(nseRes.data)) {
                for (const row of nseRes.data) {
                    const cat = (row.category || '').toUpperCase();
                    const net = parseFloat(row.netValue) || 0;
                    if (cat.includes('FII') || cat.includes('FPI')) {
                        biasData.fiiNet = net;
                        biasData.fiiDiiDate = row.date || biasData.fiiDiiDate;
                    } else if (cat.includes('DII')) {
                        biasData.diiNet = net;
                        biasData.fiiDiiDate = row.date || biasData.fiiDiiDate;
                    }
                }
            }
        } catch (nseErr) {
            console.warn('[PreMarketBias] NSE FII/DII fetch error:', nseErr.message);
        }

        // 3. Expected Open Calculation
        let gap = 0;
        if (biasData.niftyPrevClose > 0 && biasData.giftNifty > 0) {
            gap = biasData.giftNifty - biasData.niftyPrevClose;
        } else {
            gap = biasData.giftNiftyChange;
        }

        const absGap = Math.abs(gap);
        const minPts = Math.round(absGap * 0.85);
        const maxPts = Math.round(absGap * 1.15);

        if (gap >= 35) {
            biasData.expectedOpen = `GAP UP (+${minPts} to +${maxPts} points)`;
            biasData.expectedOpenType = 'GAP UP';
        } else if (gap <= -35) {
            biasData.expectedOpen = `GAP DOWN (-${maxPts} to -${minPts} points)`;
            biasData.expectedOpenType = 'GAP DOWN';
        } else {
            const sign = gap >= 0 ? '+' : '';
            biasData.expectedOpen = `FLAT OPEN (${sign}${Math.round(gap)} points)`;
            biasData.expectedOpenType = 'FLAT';
        }

        // 4. Save to Firebase Realtime Database
        if (biasData.giftNifty > 0) {
            await db.ref('market_data/pre_market_bias').set(biasData);
            console.log('[PreMarketBias] Successfully updated pre_market_bias in RTDB.');
        }

        return biasData;
    } catch (error) {
        console.error('[PreMarketBias] Fatal error updating pre-market bias:', error.message);
        return null;
    }
};

exports.NIFTY_STOCKS = NIFTY_STOCKS;
exports.NIFTY_STOCKS_NAMES = NIFTY_STOCKS_NAMES;
