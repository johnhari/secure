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
