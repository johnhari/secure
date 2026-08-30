const admin = require('firebase-admin');

/**
 * FCM Service - Handles sending push notifications
 */
class FCMService {
    constructor() {
        this.messaging = admin.messaging();
        this.db = admin.firestore();
    }

    /**
     * Send notification to a specific user
     */
    async sendToUser(uid, title, body, data = {}) {
        try {
            const userDoc = await this.db.collection('users').doc(uid).get();
            if (!userDoc.exists) {
                console.log(`User ${uid} not found for notification`);
                return;
            }

            const userData = userDoc.data();
            const token = userData.fcmToken;

            if (!token) {
                console.log(`No FCM token found for user ${uid}`);
                return;
            }

            const message = {
                notification: {
                    title,
                    body
                },
                data: {
                    ...data,
                    click_action: 'FLUTTER_NOTIFICATION_CLICK'
                },
                token
            };

            const response = await this.messaging.send(message);
            console.log(`Notification sent to ${uid}: ${response}`);
            return response;
        } catch (error) {
            console.error(`Error sending notification to ${uid}:`, error);
        }
    }

    /**
     * Send notification for heavy activity
     */
    async sendHeavyActivityAlert(symbol, type, count) {
        const title = `🚨 Heavy ${type} Activity!`;
        const body = `${symbol} detected ${count} ${type}s in the last 5 minutes.`;

        // Send to a topic instead of individual users to be efficient
        const topic = `alerts_${symbol.toLowerCase()}`;

        try {
            const message = {
                notification: {
                    title,
                    body
                },
                data: {
                    symbol,
                    type,
                    count: count.toString(),
                    click_action: 'FLUTTER_NOTIFICATION_CLICK'
                },
                topic
            };

            const response = await this.messaging.send(message);
            console.log(`Heavy activity alert sent to topic ${topic}: ${response}`);
            return response;
        } catch (error) {
            console.error('Error sending topic notification:', error);
        }
    }
}

module.exports = new FCMService();
