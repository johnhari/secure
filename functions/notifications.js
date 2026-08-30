const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const functions = require('firebase-functions');
const crypto = require('crypto');

const db = admin.firestore();

/**
 * Generate approval token
 */
const generateToken = async (uid, action, expiryHours = 24) => {
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + (expiryHours * 60 * 60 * 1000)
    );

    await db.collection('approval_tokens').doc(token).set({
        uid,
        action,
        expiresAt,
        used: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return token;
};

/**
 * Send admin notification email
 */
exports.sendAdminNotification = async (userProfile) => {
    try {
        // Skip superuser
        if (userProfile.email === 'jivaspcet@gmail.com') {
            console.log('[Email] Skipping notification for superuser');
            return;
        }

        const config = functions.config();

        if (!config.email || !config.email.user || !config.email.password) {
            console.warn('[Email] Email service not configured. Skipping notification.');
            return;
        }

        // Generate tokens
        const approveToken = await generateToken(userProfile.uid, 'approve', 24);
        const rejectToken = await generateToken(userProfile.uid, 'reject', 24);

        // Build URLs - use the Cloud Functions URL
        const baseUrl = process.env.FUNCTION_REGION
            ? `https://${process.env.FUNCTION_REGION}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net`
            : 'https://us-central1-mst7-3fb55.cloudfunctions.net';

        const approveUrl = `${baseUrl}/approveUserByToken/${approveToken}`;
        const rejectUrl = `${baseUrl}/rejectUserByToken/${rejectToken}`;

        // Create email transporter
        const transporter = nodemailer.createTransporter({
            service: 'gmail',
            auth: {
                user: config.email.user,
                pass: config.email.password
            }
        });

        const adminEmail = config.admin?.email || 'jivaspcet@gmail.com';

        const mailOptions = {
            from: `"BIG SHOT OrderFlow" <${config.email.user}>`,
            to: adminEmail,
            subject: '🆕 New User Registration - Approval Required',
            html: `
                <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; text-align: center;">
                        <h1 style="color: white; margin: 0;">BIG SHOT OrderFlow</h1>
                    </div>
                    
                    <div style="padding: 30px; background-color: #f9fafb; border: 1px solid #e5e7eb;">
                        <h2 style="color: #1f2937; margin-top: 0;">New User Pending Approval</h2>
                        
                        <p style="color: #4b5563; font-size: 16px;">
                            A new user has registered and is waiting for your approval:
                        </p>
                        
                        <div style="background-color: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #667eea;">
                            <p style="margin: 5px 0;"><strong>Email:</strong> ${userProfile.email}</p>
                            <p style="margin: 5px 0;"><strong>User ID:</strong> ${userProfile.uid}</p>
                            <p style="margin: 5px 0;"><strong>Registration Date:</strong> ${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}</p>
                        </div>
                        
                        <div style="text-align: center; margin: 30px 0;">
                            <p style="color: #4b5563; font-size: 16px; margin-bottom: 20px;">
                                <strong>Quick Action:</strong> Click below to approve or reject
                            </p>
                            
                            <a href="${approveUrl}" style="display: inline-block; background: linear-gradient(135deg, #10b981, #059669); color: white; padding: 14px 32px; text-decoration: none; border-radius: 8px; font-weight: bold; margin: 10px; font-size: 16px; box-shadow: 0 4px 6px rgba(16, 185, 129, 0.3);">
                                ✅ Approve User
                            </a>
                            
                            <a href="${rejectUrl}" style="display: inline-block; background: linear-gradient(135deg, #ef4444, #dc2626); color: white; padding: 14px 32px; text-decoration: none; border-radius: 8px; font-weight: bold; margin: 10px; font-size: 16px; box-shadow: 0 4px 6px rgba(239, 68, 68, 0.3);">
                                ❌ Reject User
                            </a>
                        </div>
                        
                        <div style="background: #fef3c7; border-left: 4px solid #f59e0b; padding: 15px; border-radius: 4px; margin: 20px 0;">
                            <p style="margin: 0; color: #92400e; font-size: 13px;">
                                <strong>⚠️ Security Notice:</strong> These links expire in 24 hours and can only be used once.
                            </p>
                        </div>
                        
                        <p style="color: #4b5563; font-size: 14px; margin-top: 30px;">
                            <strong>Alternative Method:</strong> You can also approve users via the mobile app Admin Panel.
                        </p>
                        
                        <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e5e7eb; color: #6b7280; font-size: 12px;">
                            <p>This is an automated notification from BIG SHOT OrderFlow system.</p>
                            <p>Please do not reply to this email.</p>
                        </div>
                    </div>
                </div>
            `
        };

        await transporter.sendMail(mailOptions);
        console.log(`[Email] Notification sent to ${adminEmail} for new user: ${userProfile.email}`);

        // Also send FCM notification if available
        await sendFCMToAdmins(userProfile);

    } catch (error) {
        console.error('[Email] Failed to send notification:', error.message);
    }
};

/**
 * Send FCM notification to admin users
 */
const sendFCMToAdmins = async (userProfile) => {
    try {
        const adminsSnapshot = await db.collection('users')
            .where('role', '==', 'admin')
            .get();

        if (adminsSnapshot.empty) {
            console.log('[FCM] No admins found');
            return;
        }

        const title = '🆕 New User Registered';
        const body = `User ${userProfile.email} is waiting for approval.`;

        const tokens = [];
        adminsSnapshot.forEach(doc => {
            const adminData = doc.data();
            if (adminData.fcmToken) {
                tokens.push(adminData.fcmToken);
            }
        });

        if (tokens.length === 0) {
            console.log('[FCM] No admin FCM tokens found');
            return;
        }

        await admin.messaging().sendMulticast({
            tokens,
            notification: {
                title,
                body
            },
            data: {
                type: 'new_user_registration',
                userUid: userProfile.uid,
                userEmail: userProfile.email
            }
        });

        console.log(`[FCM] Notification sent to ${tokens.length} admin(s)`);
    } catch (error) {
        console.error('[FCM] Error sending notification:', error.message);
    }
};

/**
 * Broadcast orderflow update to all users via topics
 */
exports.broadcastOrderflowUpdate = async (candleData) => {
    try {
        if (candleData && candleData.adminOnly === true) {
            console.log('[FCM] AdminOnly active. Skipping Orderflow Broadcast.');
            return;
        }

        // --- MAINTENANCE MODE CHECK ---
        const configSnap = await db.collection('global_config').doc('active_configuration').get();
        const config = configSnap.data() || {};
        if (config.isMaintenanceMode) {
            console.log('[FCM] Maintenance Mode Active. Skipping Orderflow Broadcast.');
            return;
        }

        const { symbol, buyerCount, sellerCount, candleKey, candleTime, isBigSignal } = candleData;

        if (!symbol) {
            console.warn('[FCM] No symbol provided for broadcast. Skipping.');
            return;
        }

        // Format candle time (HH:mm IST) if present
        let timeLabel = '';
        const rawTime = candleTime || (candleKey && candleKey.includes('_') ? candleKey.split('_').last : candleKey);
        const parsedMs = Number(rawTime);
        if (parsedMs && !isNaN(parsedMs) && parsedMs > 0) {
            const actualMs = parsedMs < 10000000000 ? parsedMs * 1000 : parsedMs;
            const dt = new Date(actualMs);
            if (!isNaN(dt.getTime())) {
                const hours = String(dt.getHours()).padStart(2, '0');
                const minutes = String(dt.getMinutes()).padStart(2, '0');
                timeLabel = `[${hours}:${minutes}] `;
            }
        }

        const topic = 'global_alerts';
        const title = isBigSignal ? `${timeLabel}🌟 BIG SIGNAL: ${symbol}` : `${timeLabel}🚨 ${symbol} Orderflow Alert`;

        let body = isBigSignal ? '🌟 MAJOR INSTITUTIONAL MOVE: ' : 'INSTITUTIONAL: ';
        if (buyerCount > 0 && sellerCount > 0) {
            body += `Buyers: ${buyerCount} | Sellers: ${sellerCount}`;
        } else if (buyerCount > 0) {
            body += `Strong Buying Activity: ${buyerCount}`;
        } else if (sellerCount > 0) {
            body += `Strong Selling Activity: ${sellerCount}`;
        } else {
            body = `Orderflow update received for ${symbol}`;
        }

        const message = {
            notification: {
                title,
                body,
            },
            data: {
                type: 'orderflow_update',
                symbol,
                candleKey,
                buyerCount: buyerCount.toString(),
                sellerCount: sellerCount.toString(),
                isBigSignal: (!!isBigSignal).toString(),
            },
            topic: topic,
            android: {
                priority: 'high',
                notification: {
                    sound: 'default',
                    channelId: 'heavy_activity_alerts',
                }
            }
        };

        await admin.messaging().send(message);
        console.log(`[FCM] Broadcast notification sent to topic: ${topic}`);

    } catch (error) {
        console.error('[FCM] Error in broadcastOrderflowUpdate:', error.message);
    }
};
/**
 * Broadcast sentiment update to all users
 */
exports.broadcastSentimentUpdate = async (configData) => {
    try {
        // --- MAINTENANCE MODE CHECK ---
        // Note: configData here is the newData from the trigger, which includes isMaintenanceMode
        if (configData.isMaintenanceMode) {
            console.log('[FCM] Maintenance Mode Active. Skipping Sentiment Broadcast.');
            return;
        }

        const { sentiment, tickerMessage } = configData;

        const topic = 'global_alerts';
        const title = '📊 Market Sentiment Update';

        // Map sentiment keys to readable labels
        const labels = {
            'STRONG_BULLISH': '🚀 Strong Bullish',
            'BULLISH': '📈 Bullish',
            'SIDEWAY_BULLISH': '↗️ Sideway Bullish',
            'SIDEWAY': '↔️ Sideway',
            'SIDEWAY_BEARISH': '↘️ Sideway Bearish',
            'BEARISH': '📉 Bearish',
            'STRONG_BEARISH': '🔻 Strong Bearish',
            'VOLATILITY': '⚠️ High Volatility'
        };

        const sentimentLabel = labels[sentiment] || sentiment;
        const body = `MARKET ANALYSIS: ${sentimentLabel}${tickerMessage ? '\n\n' + tickerMessage : ''}`;

        const message = {
            notification: {
                title,
                body,
            },
            data: {
                type: 'sentiment_update',
                sentiment: sentiment || '',
                tickerMessage: tickerMessage || '',
            },
            topic: topic,
            android: {
                priority: 'high',
                notification: {
                    sound: 'default',
                    channelId: 'heavy_activity_alerts',
                }
            }
        };

        await admin.messaging().send(message);
        console.log(`[FCM] Sentiment broadcast sent to topic: ${topic}`);

    } catch (error) {
        console.error('[FCM] Error in broadcastSentimentUpdate:', error.message);
    }
};

/**
 * Broadcast AI trade signal to all users via FCM topic
 */
exports.broadcastTradeSignal = async (signalData) => {
    try {
        // --- MAINTENANCE MODE CHECK ---
        const configSnap = await db.collection('global_config').doc('active_configuration').get();
        const config = configSnap.data() || {};
        if (config.isMaintenanceMode) {
            console.log('[FCM] Maintenance Mode Active. Skipping Signal Broadcast.');
            return;
        }

        const { signal, confidence, instrument, reasoning } = signalData;

        const signalEmoji = {
            'STRONG_BUY': '🟢🟢',
            'BUY': '🟢',
            'HOLD': '⚪',
            'SELL': '🔴',
            'STRONG_SELL': '🔴🔴'
        };

        const emoji = signalEmoji[signal] || '⚪';
        const signalLabel = signal.replace('_', ' ');

        const topic = 'global_alerts';
        const title = `${emoji} AI SIGNAL: ${instrument} — ${signalLabel}`;
        const body = `${confidence}% confidence. ${reasoning}`;

        const message = {
            notification: { title, body },
            data: {
                type: 'trade_signal',
                signal: signal,
                instrument: instrument,
                confidence: confidence.toString(),
            },
            topic: topic,
            android: {
                priority: 'high',
                notification: {
                    sound: 'default',
                    channelId: 'heavy_activity_alerts',
                }
            }
        };

        await admin.messaging().send(message);
        console.log(`[FCM] Trade signal broadcast: ${instrument} ${signal} (${confidence}%)`);
    } catch (error) {
        console.error('[FCM] Error in broadcastTradeSignal:', error.message);
    }
};
