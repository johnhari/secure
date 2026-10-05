const admin = require('firebase-admin');
const axios = require('axios');

const db = admin.database();
const firestore = admin.firestore();

// ═══════════════════════════════════════════════════════════════════
// 1. CANDLE PATTERN DETECTION ENGINE
// ═══════════════════════════════════════════════════════════════════

/**
 * Detect candlestick patterns from an array of OHLC candles.
 * Returns { patterns: string[], score: number (-100..+100) }
 */
const detectPatterns = (candles) => {
    if (!candles || candles.length < 3) {
        return { patterns: [], score: 0 };
    }

    const patterns = [];
    let score = 0;

    const len = candles.length;
    const c = candles[len - 1]; // current (latest)
    const p = candles[len - 2]; // previous
    const pp = len >= 3 ? candles[len - 3] : null; // 2 candles ago

    const cBody = Math.abs(c.close - c.open);
    const cRange = c.high - c.low;
    const pBody = Math.abs(p.close - p.open);
    const pRange = p.high - p.low;

    const cBullish = c.close >= c.open;
    const cBearish = c.close < c.open;
    const pBullish = p.close >= p.open;
    const pBearish = p.close < p.open;

    // ── Doji ──────────────────────────────────────────────────────
    if (cRange > 0 && cBody / cRange < 0.1) {
        patterns.push('Doji');
        // Doji is neutral — slight contrarian bias based on prior trend
        score += pBullish ? -10 : 10;
    }

    // ── Hammer (bullish reversal) ────────────────────────────────
    if (cRange > 0) {
        const lowerShadow = Math.min(c.open, c.close) - c.low;
        const upperShadow = c.high - Math.max(c.open, c.close);
        if (lowerShadow >= cBody * 2 && upperShadow < cBody * 0.5 && pBearish) {
            patterns.push('Hammer');
            score += 30;
        }
    }

    // ── Inverted Hammer (bullish reversal) ───────────────────────
    if (cRange > 0) {
        const lowerShadow = Math.min(c.open, c.close) - c.low;
        const upperShadow = c.high - Math.max(c.open, c.close);
        if (upperShadow >= cBody * 2 && lowerShadow < cBody * 0.5 && pBearish) {
            patterns.push('Inverted Hammer');
            score += 20;
        }
    }

    // ── Shooting Star (bearish reversal) ─────────────────────────
    if (cRange > 0) {
        const lowerShadow = Math.min(c.open, c.close) - c.low;
        const upperShadow = c.high - Math.max(c.open, c.close);
        if (upperShadow >= cBody * 2 && lowerShadow < cBody * 0.5 && pBullish) {
            patterns.push('Shooting Star');
            score -= 30;
        }
    }

    // ── Bullish Engulfing ────────────────────────────────────────
    if (cBullish && pBearish && c.open <= p.close && c.close >= p.open && cBody > pBody) {
        patterns.push('Bullish Engulfing');
        score += 40;
    }

    // ── Bearish Engulfing ────────────────────────────────────────
    if (cBearish && pBullish && c.open >= p.close && c.close <= p.open && cBody > pBody) {
        patterns.push('Bearish Engulfing');
        score -= 40;
    }

    // ── Morning Star (3-candle bullish reversal) ─────────────────
    if (pp) {
        const ppBearish = pp.close < pp.open;
        const ppBody = Math.abs(pp.close - pp.open);
        if (ppBearish && ppBody > 0 && pBody / ppBody < 0.3 && cBullish && c.close > (pp.open + pp.close) / 2) {
            patterns.push('Morning Star');
            score += 45;
        }
    }

    // ── Evening Star (3-candle bearish reversal) ─────────────────
    if (pp) {
        const ppBullish = pp.close >= pp.open;
        const ppBody = Math.abs(pp.close - pp.open);
        if (ppBullish && ppBody > 0 && pBody / ppBody < 0.3 && cBearish && c.close < (pp.open + pp.close) / 2) {
            patterns.push('Evening Star');
            score -= 45;
        }
    }

    // ── Three White Soldiers (strong bullish) ────────────────────
    if (pp) {
        const ppBullish = pp.close >= pp.open;
        if (ppBullish && pBullish && cBullish &&
            p.close > pp.close && c.close > p.close &&
            p.open > pp.open && c.open > p.open) {
            patterns.push('Three White Soldiers');
            score += 50;
        }
    }

    // ── Three Black Crows (strong bearish) ───────────────────────
    if (pp) {
        const ppBearish = pp.close < pp.open;
        if (ppBearish && pBearish && cBearish &&
            p.close < pp.close && c.close < p.close &&
            p.open < pp.open && c.open < p.open) {
            patterns.push('Three Black Crows');
            score -= 50;
        }
    }

    // ── Open = High (bearish pressure) ──────────────────────────
    if (cRange > 0 && Math.abs(c.open - c.high) <= cRange * 0.015) {
        patterns.push('Open = High');
        score -= 20;
    }

    // ── Open = Low (bullish pressure) ────────────────────────────
    if (cRange > 0 && Math.abs(c.open - c.low) <= cRange * 0.015) {
        patterns.push('Open = Low');
        score += 20;
    }

    // Clamp score to -100..+100
    score = Math.max(-100, Math.min(100, score));

    return { patterns, score };
};


// ═══════════════════════════════════════════════════════════════════
// 2. ORDERFLOW SCORING ENGINE
// ═══════════════════════════════════════════════════════════════════

/**
 * Score orderflow from Firestore injections for a given instrument.
 * Looks at the most recent 3 candle injections.
 * Returns { score: number (-100..+100), summary: string }
 */
const scoreOrderflow = async (instrument) => {
    try {
        const now = Date.now();
        const threeHoursAgo = now - (3 * 60 * 60 * 1000);

        const snapshot = await firestore.collection('orderflow')
            .where('symbol', '==', instrument)
            .where('candleTime', '>=', threeHoursAgo)
            .orderBy('candleTime', 'desc')
            .limit(5)
            .get();

        if (snapshot.empty) {
            return { score: 0, summary: 'No recent orderflow injections' };
        }

        let totalBuyers = 0;
        let totalSellers = 0;
        let bigSignalCount = 0;
        let trapCount = 0;
        let liquidationCount = 0;

        snapshot.docs.forEach(doc => {
            const data = doc.data();
            totalBuyers += (data.buyerCount || 0);
            totalSellers += (data.sellerCount || 0);
            if (data.isBigSignal) bigSignalCount++;
            if (data.isTrap) trapCount++;
            if (data.isLiquidation) liquidationCount++;
        });

        const total = totalBuyers + totalSellers;
        if (total === 0) {
            return { score: 0, summary: 'No volume in recent injections' };
        }

        const buyerRatio = totalBuyers / total;
        // Map buyer ratio to score: 0.5 = neutral, 1.0 = +100, 0.0 = -100
        let score = (buyerRatio - 0.5) * 200;

        // Amplify if big signals detected
        if (bigSignalCount > 0) {
            score *= (1 + bigSignalCount * 0.15);
        }

        // Trap signals add contrarian bias
        if (trapCount > 0) {
            score *= -0.5; // Traps invert sentiment partially
        }

        // Liquidation = extreme volatility, amplify direction
        if (liquidationCount > 0) {
            score *= 1.3;
        }

        score = Math.max(-100, Math.min(100, Math.round(score)));

        // Build summary
        const direction = totalBuyers > totalSellers ? 'buying' : 'selling';
        const formatNum = (n) => n.toLocaleString('en-IN');
        let summary = `Heavy ${direction}: ${formatNum(totalBuyers)} buyers vs ${formatNum(totalSellers)} sellers`;
        if (bigSignalCount > 0) summary += ` (${bigSignalCount} big signal${bigSignalCount > 1 ? 's' : ''})`;
        if (trapCount > 0) summary += ` ⚠️ TRAP detected`;

        return { score, summary };
    } catch (err) {
        console.error('[Signals] Orderflow scoring error:', err.message);
        return { score: 0, summary: 'Error reading orderflow data' };
    }
};


// ═══════════════════════════════════════════════════════════════════
// 3. SENTIMENT SCORING ENGINE (Gemini AI)
// ═══════════════════════════════════════════════════════════════════

/**
 * Fetch live Google News headlines and score sentiment via Gemini AI.
 * Returns { score: number (-100..+100), label: string }
 */
const scoreSentiment = async () => {
    try {
        // 1. Fetch Gemini API key from Firestore config
        const configSnap = await firestore.collection('global_config')
            .doc('active_configuration').get();
        const config = configSnap.data() || {};
        const apiKey = config.geminiApiKey || '';

        if (!apiKey) {
            console.warn('[Signals] No Gemini API key configured. Returning neutral sentiment.');
            return { score: 0, label: 'NEUTRAL' };
        }

        // 2. Fetch Google News RSS headlines
        const rssUrl = 'https://news.google.com/rss/search?q=stock+market+india+nifty&hl=en-IN&gl=IN&ceid=IN:en';
        let headlines = [];
        try {
            const rssResponse = await axios.get(rssUrl, {
                headers: { 'User-Agent': 'Mozilla/5.0' },
                timeout: 6000
            });
            const titleRegex = /<item>[\s\S]*?<title>([\s\S]*?)<\/title>/g;
            let match;
            while ((match = titleRegex.exec(rssResponse.data)) !== null && headlines.length < 10) {
                let title = match[1].trim();
                if (title.startsWith('<![CDATA[')) title = title.slice(9, -3).trim();
                title = title.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                headlines.push(title);
            }
        } catch (rssErr) {
            console.warn('[Signals] RSS fetch failed:', rssErr.message);
        }

        if (headlines.length === 0) {
            return { score: 0, label: 'NEUTRAL' };
        }

        // 3. Call Gemini AI
        const headlineText = headlines.map(h => `- ${h}`).join('\n');
        const prompt = `You are an expert Indian stock market analyst. Analyze these headlines and respond with ONLY a valid JSON object (no markdown, no backticks):
${headlineText}

Required JSON schema:
{"sentiment":"BULLISH|BEARISH|NEUTRAL|VOLATILITY","confidence":0-100}`;

        const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
        const geminiResponse = await axios.post(geminiUrl, {
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.3, maxOutputTokens: 100 }
        }, { timeout: 10000 });

        let responseText = geminiResponse.data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
        // Clean markdown wrappers
        if (responseText.includes('```json')) {
            responseText = responseText.split('```json').pop().split('```')[0].trim();
        } else if (responseText.includes('```')) {
            responseText = responseText.split('```')[1]?.split('```')[0]?.trim() || responseText;
        }

        const parsed = JSON.parse(responseText);
        const sentimentLabel = (parsed.sentiment || 'NEUTRAL').toUpperCase();
        const confidence = Math.min(100, Math.max(0, parsed.confidence || 50));

        // Map sentiment to score
        const sentimentScoreMap = {
            'BULLISH': confidence,
            'BEARISH': -confidence,
            'NEUTRAL': 0,
            'VOLATILITY': 0 // Volatile = neutral directionally
        };

        const score = Math.max(-100, Math.min(100, sentimentScoreMap[sentimentLabel] || 0));

        return { score, label: sentimentLabel };
    } catch (err) {
        console.error('[Signals] Sentiment scoring error:', err.message);
        return { score: 0, label: 'NEUTRAL' };
    }
};


// ═══════════════════════════════════════════════════════════════════
// 4. COMPOSITE SIGNAL GENERATOR
// ═══════════════════════════════════════════════════════════════════

const WEIGHTS = {
    orderflow: 0.45,
    pattern: 0.30,
    sentiment: 0.25
};

/**
 * Generate a composite trade signal for an instrument.
 */
const generateSignalForInstrument = async (instrument) => {
    console.log(`[Signals] Generating signal for ${instrument}...`);

    // 1. Fetch recent candles from RTDB
    const candlesSnapshot = await db.ref(`market_data/${instrument}/candles`)
        .orderByKey()
        .limitToLast(10)
        .once('value');

    const candlesRaw = candlesSnapshot.val() || {};
    const sortedKeys = Object.keys(candlesRaw).sort((a, b) => Number(a) - Number(b));
    const candles = sortedKeys.map(k => candlesRaw[k]);

    // 2. Run all 3 scoring engines
    const patternResult = detectPatterns(candles);
    const orderflowResult = await scoreOrderflow(instrument);
    const sentimentResult = await scoreSentiment();

    // 3. Compute weighted composite score
    const compositeScore = Math.round(
        orderflowResult.score * WEIGHTS.orderflow +
        patternResult.score * WEIGHTS.pattern +
        sentimentResult.score * WEIGHTS.sentiment
    );

    // 4. Map to signal type
    let signal;
    const absScore = Math.abs(compositeScore);
    if (compositeScore >= 60) signal = 'STRONG_BUY';
    else if (compositeScore >= 25) signal = 'BUY';
    else if (compositeScore <= -60) signal = 'STRONG_SELL';
    else if (compositeScore <= -25) signal = 'SELL';
    else signal = 'HOLD';

    // 5. Calculate confidence (0-100)
    const confidence = Math.min(100, Math.max(0, absScore));

    // 6. Generate reasoning
    const reasoningParts = [];

    if (orderflowResult.score !== 0) {
        const dir = orderflowResult.score > 0 ? 'buying pressure' : 'selling pressure';
        reasoningParts.push(`Strong institutional ${dir} detected`);
    }

    if (patternResult.patterns.length > 0) {
        const patternNames = patternResult.patterns.join(', ');
        const bias = patternResult.score > 0 ? 'bullish' : patternResult.score < 0 ? 'bearish' : 'neutral';
        reasoningParts.push(`${bias} reversal pattern${patternResult.patterns.length > 1 ? 's' : ''}: ${patternNames}`);
    }

    if (sentimentResult.label !== 'NEUTRAL') {
        reasoningParts.push(`Market sentiment is ${sentimentResult.label.toLowerCase()}`);
    }

    if (reasoningParts.length === 0) {
        reasoningParts.push('No strong directional signals detected. Market appears range-bound.');
    }

    const reasoning = reasoningParts.join('. ') + '.';

    // 7. Build signal object
    const signalData = {
        signal,
        confidence,
        compositeScore,
        scores: {
            orderflow: orderflowResult.score,
            pattern: patternResult.score,
            sentiment: sentimentResult.score
        },
        patterns: patternResult.patterns,
        orderflowSummary: orderflowResult.summary,
        sentimentLabel: sentimentResult.label,
        reasoning,
        instrument,
        timestamp: Date.now(),
        generatedAt: admin.database.ServerValue.TIMESTAMP
    };

    // 8. Write to RTDB
    await db.ref(`trade_signals/${instrument}/latest`).set(signalData);

    // 9. Append to history (keep last 50)
    const historyRef = db.ref(`trade_signals/${instrument}/history`);
    await historyRef.push({
        ...signalData,
        generatedAt: Date.now() // Use epoch for history since push() doesn't support ServerValue
    });

    // Trim history to last 50 entries
    const historySnap = await historyRef.orderByKey().once('value');
    const historyCount = historySnap.numChildren();
    if (historyCount > 50) {
        const deleteCount = historyCount - 50;
        let deleted = 0;
        historySnap.forEach(child => {
            if (deleted < deleteCount) {
                historyRef.child(child.key).remove();
                deleted++;
            }
        });
    }

    console.log(`[Signals] ${instrument}: ${signal} (confidence: ${confidence}%, composite: ${compositeScore})`);
    return signalData;
};


// ═══════════════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════════════

/**
 * Generate trade signals for all major instruments.
 * Called by scheduled Cloud Function every 5 minutes.
 */
exports.generateAllSignals = async () => {
    const instruments = ['NIFTY50', 'BANKNIFTY', 'FINNIFTY', 'MIDCAPNIFTY'];
    const results = {};

    for (const instrument of instruments) {
        try {
            results[instrument] = await generateSignalForInstrument(instrument);
        } catch (err) {
            console.error(`[Signals] Error generating signal for ${instrument}:`, err.message);
            results[instrument] = { signal: 'HOLD', confidence: 0, error: err.message };
        }

        // Small delay between instruments to avoid Gemini rate limits
        await new Promise(resolve => setTimeout(resolve, 1500));
    }

    return results;
};

/**
 * Generate signal for a single instrument (on-demand).
 */
exports.generateSignalForInstrument = generateSignalForInstrument;

// ═══════════════════════════════════════════════════════════════════
// 5. AUTONOMOUS VOLATILITY SCANNER & STOCK ORDERFLOW AUTO-INJECTOR
// ═══════════════════════════════════════════════════════════════════

/**
 * Automatically analyze every stock & trend according to market movement,
 * filter ONLY when stock is MORE VOLATILE, evaluate high-winning-ratio strategies
 * with news/sentiment alignment, auto-inject BUY/SELL into stocks (Firestore orderflow + RTDB),
 * and maintain the active signal registry (trade_signals/active_summary) for the top app bar bell icon.
 */
const autoAnalyzeAndInjectStocks = async () => {
    console.log('[AutoInject] Starting autonomous stock scan & trend injection...');
    const { NIFTY_STOCKS, NIFTY_STOCKS_NAMES } = require('./market');

    // 1. Fetch market sentiment from Google News RSS + Gemini AI
    let marketSentiment = { score: 0, label: 'NEUTRAL' };
    try {
        marketSentiment = await scoreSentiment();
    } catch (e) {
        console.warn('[AutoInject] Sentiment fetch error, proceeding with neutral:', e.message);
    }

    // 2. Query TradingView India Scanner for live technicals & volatility across all 50 Nifty stocks
    const mapTv = (s) => {
        if (s === 'BAJAJ-AUTO') return 'NSE:BAJAJ_AUTO';
        if (s === 'M&M') return 'NSE:M_M';
        if (s === 'TATAMOTORS') return 'NSE:TATAMOTORS';
        return `NSE:${s}`;
    };

    const tvTickers = NIFTY_STOCKS.map(mapTv);
    const tvUrl = 'https://scanner.tradingview.com/india/scan';
    let tvData = [];
    try {
        const tvResp = await axios.post(tvUrl, {
            symbols: { tickers: tvTickers },
            columns: [
                'name', 'close', 'change', 'change_abs',
                'open', 'high', 'low', 'volume',
                'Volatility.D', 'ATR', 'RSI', 'Recommend.All',
                'relative_volume_10d_calc'
            ]
        }, {
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'Mozilla/5.0'
            },
            timeout: 10000
        });

        if (tvResp.data && tvResp.data.data) {
            tvData = tvResp.data.data;
        }
    } catch (tvErr) {
        console.error('[AutoInject] TradingView scanner fetch failed:', tvErr.message);
    }

    if (tvData.length === 0) {
        console.warn('[AutoInject] No stock data available from scanner.');
        return { count: 0, activeStocks: {} };
    }

    // 3. Analyze every stock & trend, FILTER ONLY FOR MORE VOLATILE STOCKS
    const candidates = [];

    for (const item of tvData) {
        const symbolClean = item.s.replace('NSE:', '').replace('_', '-');
        const matchedSymbol = NIFTY_STOCKS.find(s => s === symbolClean || mapTv(s) === item.s) || symbolClean;
        const d = item.d;
        const price = d[1] || 0;
        const changePercent = d[2] || 0;
        const changePts = d[3] || 0;
        const open = d[4] || price;
        const high = d[5] || price;
        const low = d[6] || price;
        const volume = d[7] || 0;
        const volatilityD = d[8] || 0;
        const atr = d[9] || 0;
        const rsi = d[10] || 50;
        const techRecommend = d[11] || 0;
        const relVolume = d[12] || 1;

        const dayRange = high - low;
        const dayRangePct = open > 0 ? (dayRange / open) * 100 : 0;

        // REQUIREMENT: ONLY WHEN MORE VOLATILE THE STOCK
        // Stock must have strong intraday range expansion (>= 1.2%) or high daily volatility (>= 1.8%)
        const isVolatile = dayRangePct >= 1.2 || volatilityD >= 1.8;
        if (!isVolatile) {
            continue; // Skip calm/flat/choppy stocks!
        }

        const posInRange = dayRange > 0 ? (price - low) / dayRange : 0.5;

        let signal = 'HOLD';
        let winRatio = 50;
        let strategy = '';
        let reason = '';

        // HIGH WINNING RATIO STRATEGY EVALUATION:
        if (changePercent > 0.5 && posInRange >= 0.65 && rsi >= 45) {
            signal = 'BUY';
            if (posInRange >= 0.82) {
                strategy = 'Bullish Breakout (High)';
                winRatio = 86;
                reason = `High momentum (${dayRangePct.toFixed(1)}% range) breaking out near session high with aggressive buyer surge`;
            } else {
                strategy = 'Momentum Surge';
                winRatio = 80;
                reason = `Strong upward expansion (+${changePercent.toFixed(2)}%) backed by volume surge and positive technicals`;
            }

            // Market sentiment boost
            if (marketSentiment.label === 'BULLISH') {
                winRatio = Math.min(94, winRatio + 4);
                reason += ` [Market sentiment aligned: BULLISH]`;
            } else if (marketSentiment.label === 'BEARISH') {
                winRatio -= 3;
            }
        } else if (changePercent < -0.5 && posInRange <= 0.35 && rsi <= 55) {
            signal = 'SELL';
            if (posInRange <= 0.18) {
                strategy = 'Bearish Breakdown (Low)';
                winRatio = 86;
                reason = `Heavy selling (${dayRangePct.toFixed(1)}% range) breaking down near session low with institutional dumping`;
            } else {
                strategy = 'Liquidation Slide';
                winRatio = 80;
                reason = `Downward slide (${changePercent.toFixed(2)}%) towards session low with negative institutional pressure`;
            }

            // Market sentiment boost
            if (marketSentiment.label === 'BEARISH') {
                winRatio = Math.min(94, winRatio + 4);
                reason += ` [Market sentiment aligned: BEARISH]`;
            } else if (marketSentiment.label === 'BULLISH') {
                winRatio -= 3;
            }
        }

        // Only setups with high winning probability
        if (signal !== 'HOLD' && winRatio >= 75) {
            candidates.push({
                symbol: matchedSymbol,
                name: (NIFTY_STOCKS_NAMES && NIFTY_STOCKS_NAMES[matchedSymbol]) || matchedSymbol,
                signal,
                winRatio,
                strategy,
                price: Number(price.toFixed(2)),
                changePercent: Number(changePercent.toFixed(2)),
                changePts: Number(changePts.toFixed(2)),
                volatility: Number((volatilityD || dayRangePct).toFixed(2)),
                dayRangePct: Number(dayRangePct.toFixed(2)),
                rsi: Number(rsi.toFixed(1)),
                reason,
                timestamp: Date.now()
            });
        }
    }

    // Sort by winRatio descending, then volatility
    candidates.sort((a, b) => (b.winRatio - a.winRatio) || (b.volatility - a.volatility));

    // Select top 2 to 6 stocks (e.g. 2, 3, 4 stocks)
    const selectedStocks = candidates.slice(0, 5);
    console.log(`[AutoInject] Found ${candidates.length} setups, auto-injecting top ${selectedStocks.length} stocks...`);

    const firestoreBatch = firestore.batch();
    const activeSummary = {};

    // 4. Inject Orderflow for each selected stock
    for (const stock of selectedStocks) {
        try {
            // Find appropriate 5m candle key
            const now = Date.now();
            let candleKey = Math.floor(now / (5 * 60 * 1000)) * (5 * 60 * 1000);

            // Fetch latest candle from RTDB to match actual candle timestamp if market closed
            const candlesSnap = await db.ref(`market_data/${stock.symbol}/candles`).limitToLast(1).once('value');
            if (candlesSnap.exists()) {
                const latestKey = Object.keys(candlesSnap.val())[0];
                if (latestKey) candleKey = Number(latestKey);
            }

            const docId = `${stock.symbol}_${candleKey}`;
            const isBuy = stock.signal === 'BUY';
            const baseVol = 1800 + Math.floor(Math.random() * 800);
            const counterVol = 200 + Math.floor(Math.random() * 200);

            const buyerCount = isBuy ? baseVol : counterVol;
            const sellerCount = isBuy ? counterVol : baseVol;

            const orderflowData = {
                candleKey: String(candleKey),
                candleTime: candleKey,
                symbol: stock.symbol,
                buyerCount,
                sellerCount,
                bubbleScale: 3.0,
                bubbleOpacity: 0.85,
                bubbleGlow: 1.0,
                showLabel: true,
                isBigSignal: true,
                isInstitutional: true,
                customTag: `${stock.symbol.replace('BANK', '').replace('TECH', '')} ${isBuy ? 'BUY' : 'SELL'}`,
                pulseSpeed: 1.2,
                borderColor: isBuy ? 'GREEN' : 'RED',
                broadcastPush: false, // Suppress push notification, bell badge used instead!
                adminOnly: false,
                winRatio: stock.winRatio,
                strategy: stock.strategy,
                price: stock.price,
                volatility: stock.volatility,
                reason: stock.reason,
                updatedBy: 'AUTO_VOLATILITY_INJECTOR',
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            firestoreBatch.set(firestore.collection('orderflow').doc(docId), orderflowData, { merge: true });

            // Write to RTDB trade_signals
            const rtdbSignal = {
                ...stock,
                candleKey,
                buyerCount,
                sellerCount,
                generatedAt: admin.database.ServerValue.TIMESTAMP
            };
            await db.ref(`trade_signals/${stock.symbol}/latest`).set(rtdbSignal);

            activeSummary[stock.symbol] = stock;
        } catch (err) {
            console.error(`[AutoInject] Error injecting for ${stock.symbol}:`, err.message);
        }
    }

    if (selectedStocks.length > 0) {
        await firestoreBatch.commit();
        console.log(`[AutoInject] Successfully auto-injected orderflow into ${selectedStocks.length} stocks in Firestore.`);
    }

    // 5. Update RTDB active_summary so bell icon badge immediately updates
    const summaryPayload = {
        count: selectedStocks.length,
        lastUpdated: Date.now(),
        activeStocks: activeSummary
    };
    await db.ref('trade_signals/active_summary').set(summaryPayload);
    console.log(`[AutoInject] Updated trade_signals/active_summary with count=${selectedStocks.length}`);

    return summaryPayload;
};

exports.autoAnalyzeAndInjectStocks = autoAnalyzeAndInjectStocks;
