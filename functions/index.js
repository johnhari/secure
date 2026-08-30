const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();

// Import function modules
const auth = require('./auth');
const adminFunctions = require('./admin');
const market = require('./market');
const notifications = require('./notifications');
const signals = require('./signals');

// ========================================
// AUTH FUNCTIONS
// ========================================

/**
 * Send OTP for registration or password reset
 */
exports.sendOtp = functions.https.onCall(async (data, context) => {
    return await auth.sendOtp(data);
});

/**
 * Verify OTP and register user
 */
exports.verifyAndRegister = functions.https.onCall(async (data, context) => {
    return await auth.verifyAndRegister(data);
});

/**
 * Initiate password reset
 */
exports.forgotPassword = functions.https.onCall(async (data, context) => {
    return await auth.forgotPassword(data);
});

/**
 * Reset password with OTP
 */
exports.resetPassword = functions.https.onCall(async (data, context) => {
    return await auth.resetPassword(data);
});

// ========================================
// ADMIN FUNCTIONS
// ========================================

/**
 * Get list of users (admin only)
 */
exports.getUsers = functions.https.onRequest(async (req, res) => {
    return await adminFunctions.getUsers(req, res);
});

/**
 * Update user approval status (admin only)
 */
exports.updateUserStatus = functions.https.onRequest(async (req, res) => {
    return await adminFunctions.updateUserStatus(req, res);
});

/**
 * Approve user via email token (public)
 */
exports.approveUserByToken = functions.https.onRequest(async (req, res) => {
    return await adminFunctions.approveUserByToken(req, res);
});

/**
 * Reject user via email token (public)
 */
exports.rejectUserByToken = functions.https.onRequest(async (req, res) => {
    return await adminFunctions.rejectUserByToken(req, res);
});

/**
 * Save orderflow data (admin only)
 */
exports.saveOrderflow = functions.runWith({ memory: '512MB' }).https.onRequest(async (req, res) => {
    return await adminFunctions.saveOrderflow(req, res);
});

// ========================================
// BACKGROUND FUNCTIONS
// ========================================

/**
 * Trigger when new user is created
 * Send admin notification email
 */
exports.onUserCreated = functions.firestore
    .document('users/{userId}')
    .onCreate(async (snap, context) => {
        const userData = snap.data();

        // Skip superuser
        if (userData.email === 'jivaspcet@gmail.com') {
            return null;
        }

        // #10: Atomically increment totalInstalls and pendingCount
        const db = admin.firestore();
        await db.collection('stats').doc('user_counters').set({
            totalInstalls: admin.firestore.FieldValue.increment(1),
            pendingCount: admin.firestore.FieldValue.increment(1),
        }, { merge: true });

        // Send notification email
        await notifications.sendAdminNotification(userData);

        return null;
    });

/**
 * Scheduled function to fetch market data
 * Runs every 1 minute during market hours
 */
exports.fetchMarketData = functions.runWith({ memory: '512MB' }).pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
        return await market.fetchAndUpdateMarketData();
    });

/**
 * On-demand market data fetch (HTTPS callable).
 * Called by Flutter app on startup — bypasses market-hours gate.
 * Always fetches the last 3 trading days and writes to RTDB.
 */
exports.getMarketData = functions.runWith({ memory: '512MB' }).https.onCall(async (data, context) => {
    const symbol = (data && data.symbol) ? data.symbol : 'NIFTY50';
    return await market.fetchAndReturnCandles(symbol);
});

/**
 * On-demand market heatmap fetch (HTTPS callable).
 * Returns the aggregated Nifty 50 heatmap data.
 */
exports.getHeatmapData = functions.runWith({ memory: '512MB' }).https.onCall(async (data, context) => {
    return await market.fetchHeatmapData();
});

// ========================================
// AI TRADE SIGNAL FUNCTIONS
// ========================================

/**
 * Scheduled function to generate AI trade signals.
 * Runs every 5 minutes during market hours.
 */
exports.generateTradeSignals = functions.runWith({ memory: '512MB', timeoutSeconds: 120 }).pubsub
    .schedule('every 5 minutes')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
        try {
            const results = await signals.generateAllSignals();

            // Send FCM notification for high-confidence signals
            for (const [instrument, signal] of Object.entries(results)) {
                if (signal.confidence >= 75 && signal.signal !== 'HOLD') {
                    await notifications.broadcastTradeSignal(signal);
                }
            }

            return null;
        } catch (err) {
            console.error('[Signals] Scheduled generation error:', err);
            return null;
        }
    });

/**
 * On-demand trade signal generation (HTTPS callable).
 * Generate signal for a specific instrument immediately.
 */
exports.getTradeSignal = functions.runWith({ memory: '512MB', timeoutSeconds: 60 }).https.onCall(async (data, context) => {
    const instrument = (data && data.instrument) ? data.instrument : 'NIFTY50';
    return await signals.generateSignalForInstrument(instrument);
});


/**
 * Clean up expired approval tokens
 * Runs daily at midnight
 */
exports.cleanupExpiredTokens = functions.pubsub
    .schedule('0 0 * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const expired = await db.collection('approval_tokens')
            .where('expiresAt', '<', now)
            .get();

        const batch = db.batch();
        expired.docs.forEach(doc => {
            batch.delete(doc.ref);
        });

        await batch.commit();
        console.log(`Cleaned up ${expired.size} expired tokens`);

        return null;
    });

/**
 * Clean up old candlestick and orderflow data
 * Runs daily at 2:00 AM, keeps only last 10 days
 */
exports.cleanupOldData = functions.pubsub
    .schedule('0 2 * * *')  // 2:00 AM daily
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
        const db = admin.firestore();
        const rtdb = admin.database();
        const twoDaysAgo = Date.now() - (10 * 24 * 60 * 60 * 1000); // Extended to 10 days (240h) to cover weekends and ensure 5 working days data

        console.log(`[CLEANUP] Starting data cleanup. Deleting data older than ${new Date(twoDaysAgo).toISOString()}`);

        // 1. Cleanup Firestore orderflow data
        try {
            const oldOrderflow = await db.collection('orderflow')
                .where('candleTime', '<', twoDaysAgo)
                .get();

            if (!oldOrderflow.empty) {
                let batch = db.batch();
                let count = 0;
                let totalDeleted = 0;

                for (const doc of oldOrderflow.docs) {
                    batch.delete(doc.ref);
                    count++;

                    if (count === 500) {  // Firestore batch limit
                        await batch.commit();
                        totalDeleted += count;
                        console.log(`[CLEANUP] Deleted ${count} orderflow documents (total: ${totalDeleted})`);
                        batch = db.batch();
                        count = 0;
                    }
                }

                if (count > 0) {
                    await batch.commit();
                    totalDeleted += count;
                }

                console.log(`[CLEANUP] Orderflow cleanup complete. Deleted ${totalDeleted} documents`);
            } else {
                console.log('[CLEANUP] No old orderflow data to delete');
            }
        } catch (error) {
            console.error('[CLEANUP] Error cleaning orderflow data:', error);
        }

        // 2. Cleanup RTDB candlestick data
        try {
            const instruments = ['NIFTY50', 'BANKNIFTY', 'FINNIFTY', 'MIDCAPNIFTY'];

            for (const instrument of instruments) {
                const candlesRef = rtdb.ref(`market_data/${instrument}/candles`);
                const snapshot = await candlesRef.once('value');

                if (snapshot.exists()) {
                    const candles = snapshot.val();
                    const updates = {};
                    let deletedCount = 0;

                    // Mark old candles for deletion
                    for (const [key, value] of Object.entries(candles)) {
                        const candleTime = parseInt(key);
                        if (candleTime < twoDaysAgo) {
                            updates[key] = null;  // Delete this candle
                            deletedCount++;
                        }
                    }

                    if (deletedCount > 0) {
                        await candlesRef.update(updates);
                        console.log(`[CLEANUP] Deleted ${deletedCount} old candles for ${instrument}`);
                    } else {
                        console.log(`[CLEANUP] No old candles to delete for ${instrument}`);
                    }
                }
            }
        } catch (error) {
            console.error('[CLEANUP] Error cleaning candlestick data:', error);
        }

        console.log('[CLEANUP] Data cleanup complete');
        return null;
    });

/**
 * Trigger when orderflow data is added or updated
 * Broadcasts notification to users
 */
exports.onOrderflowUpdated = functions.runWith({ memory: '512MB' }).firestore
    .document('orderflow/{candleKey}')
    .onWrite(async (change, context) => {
        const newData = change.after.exists ? change.after.data() : null;
        const oldData = change.before.exists ? change.before.data() : null;

        const candleKey = context.params.candleKey;
        console.log(`[Trigger] onOrderflowUpdated for ${candleKey}`);

        // Handle deletions (revocations)
        if (!newData) {
            console.log(`[Trigger] Data deleted for ${candleKey}.`);
            if (oldData && oldData.symbol === 'NIFTY50') {
                const timestamp = oldData.candleKey;
                console.log(`[Trigger] NIFTY50 data revoked at ${timestamp}. Revoking from other stocks...`);
                const db = admin.firestore();
                const batch = db.batch();
                const { NIFTY_STOCKS } = require('./market');
                for (const stockSymbol of NIFTY_STOCKS) {
                    const docId = `${stockSymbol}_${timestamp}`;
                    batch.delete(db.collection('orderflow').doc(docId));
                }
                await batch.commit();
                console.log(`[Trigger] Successfully revoked matching propagated orderflow for all stocks at ${timestamp}.`);
            }
            return null;
        }

        // Broadcast if new data or significant numeric update
        const isNew = !oldData;
        const countsChanged = isNew ||
            newData.buyerCount !== oldData.buyerCount ||
            newData.sellerCount !== oldData.sellerCount;
        const signalChanged = !oldData || newData.isBigSignal !== oldData.isBigSignal;
        const shouldPush = newData.broadcastPush === true && newData.adminOnly !== true;

        console.log(`[Trigger] ${candleKey}: countsChanged=${countsChanged}, signalChanged=${signalChanged}, shouldPush=${shouldPush}`);

        if (shouldPush) {
            console.log(`[Trigger] Broadcasting update for ${candleKey}`);
            await notifications.broadcastOrderflowUpdate({
                ...newData,
                candleKey: candleKey
            });
        } else {
            console.log(`[Trigger] Skipping broadcast for ${candleKey}: broadcastPush not enabled or adminOnly.`);
        }

        // Propagate if NIFTY50 manual injection and not adminOnly
        if (newData.symbol === 'NIFTY50' && newData.updatedBy !== 'SYSTEM_PROPAGATION' && newData.adminOnly !== true) {
            try {
                const market = require('./market');
                await market.propagateOrderflow(newData);
            } catch (err) {
                console.error('[Trigger] Error in propagateOrderflow:', err);
            }
        }

        return null;
    });

/**
 * Trigger when global config is updated
 * Broadcasts sentiment notification to users
 */
exports.onConfigUpdated = functions.firestore
    .document('global_config/active_configuration')
    .onWrite(async (change, context) => {
        const newData = change.after.exists ? change.after.data() : null;
        const oldData = change.before.exists ? change.before.data() : null;

        if (!newData) return null;

        // Broadcast if sentiment or ticker message changed
        const sentimentChanged = !oldData || newData.sentiment !== oldData.sentiment;
        const tickerChanged = !oldData || newData.tickerMessage !== oldData.tickerMessage;

        if (sentimentChanged || tickerChanged) {
            // await notifications.broadcastSentimentUpdate(newData);
            console.log('[FCM] Sentiment/Ticker changed. Skipping push notification per request.');
        }

        return null;
    });
