const admin = require('firebase-admin');
const functions = require('firebase-functions');

const db = admin.firestore();

/**
 * Verify Firebase Auth token from request
 */
const verifyToken = async (req) => {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        throw new functions.https.HttpsError('unauthenticated', 'No token provided');
    }

    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await admin.auth().verifyIdToken(token);

    // Get user profile
    const userDoc = await db.collection('users').doc(decodedToken.uid).get();

    return {
        uid: decodedToken.uid,
        email: decodedToken.email,
        profile: userDoc.exists ? userDoc.data() : null,
        role: userDoc.exists ? userDoc.data().role : 'viewer'
    };
};

/**
 * Verify admin role
 */
const verifyAdmin = (user) => {
    if (user.role !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Admin access required');
    }
};

/**
 * Get Users (Admin Only)
 */
exports.getUsers = async (req, res) => {
    try {
        // Set CORS headers
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');

        if (req.method === 'OPTIONS') {
            return res.status(204).send('');
        }

        // Verify authentication
        const user = await verifyToken(req);
        verifyAdmin(user);

        const { isApproved } = req.query;
        let query = db.collection('users');

        if (isApproved !== undefined) {
            query = query.where('isApproved', '==', isApproved === 'true');
        }

        const snapshot = await query.limit(50).get();
        const users = snapshot.docs.map(doc => doc.data());

        res.json({ success: true, count: users.length, users });
    } catch (error) {
        console.error('Error fetching users:', error);
        res.status(error.code === 'permission-denied' ? 403 : 500).json({
            error: error.message || 'Failed to fetch users'
        });
    }
};

/**
 * Update User Status (Admin Only)
 */
exports.updateUserStatus = async (req, res) => {
    try {
        // Set CORS headers
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'PUT, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');

        if (req.method === 'OPTIONS') {
            return res.status(204).send('');
        }

        // Verify authentication
        const user = await verifyToken(req);
        verifyAdmin(user);

        const uid = req.path.split('/').pop();
        const { isApproved } = req.body;

        if (isApproved === undefined) {
            return res.status(400).json({ error: 'isApproved field is required' });
        }

        // Get previous state to compute delta for counter doc (#10)
        const userDoc = await db.collection('users').doc(uid).get();
        const wasApproved = userDoc.exists ? userDoc.data().isApproved : false;

        await db.collection('users').doc(uid).update({
            isApproved: isApproved,
            approvedAt: isApproved ? admin.firestore.FieldValue.serverTimestamp() : null,
            approvedBy: isApproved ? user.uid : null
        });

        // #10: Keep counter doc in sync atomically
        const approvedDelta = (isApproved && !wasApproved) ? 1 : (!isApproved && wasApproved) ? -1 : 0;
        const pendingDelta = -approvedDelta; // pendng = total - approved
        if (approvedDelta !== 0) {
            await db.collection('stats').doc('user_counters').set({
                approvedCount: admin.firestore.FieldValue.increment(approvedDelta),
                pendingCount: admin.firestore.FieldValue.increment(pendingDelta),
            }, { merge: true });
        }

        res.json({
            success: true,
            message: `User ${isApproved ? 'approved' : 'rejected'} successfully`
        });
    } catch (error) {
        console.error('Error updating user status:', error);
        res.status(500).json({ error: 'Failed to update user status' });
    }
};

/**
 * Approve User by Token (Public)
 */
exports.approveUserByToken = async (req, res) => {
    try {
        const token = req.path.split('/').pop(); // Extract token from path

        // Get token from Firestore
        const tokenDoc = await db.collection('approval_tokens').doc(token).get();

        if (!tokenDoc.exists) {
            return res.status(400).send(getErrorPage('Invalid or Expired Link'));
        }

        const tokenData = tokenDoc.data();

        // Check expiry
        if (Date.now() > tokenData.expiresAt.toMillis()) {
            await db.collection('approval_tokens').doc(token).delete();
            return res.status(400).send(getErrorPage('Link Expired'));
        }

        // Check if already used
        if (tokenData.used) {
            return res.status(400).send(getErrorPage('Link Already Used'));
        }

        // Check action type
        if (tokenData.action !== 'approve') {
            return res.status(400).send(getErrorPage('Invalid Action'));
        }

        // Update user status
        await db.collection('users').doc(tokenData.uid).update({
            isApproved: true,
            approvedAt: admin.firestore.FieldValue.serverTimestamp(),
            approvedBy: 'email_link'
        });

        // Mark token as used
        await db.collection('approval_tokens').doc(token).update({ used: true });

        // Get user info
        const userDoc = await db.collection('users').doc(tokenData.uid).get();
        const userData = userDoc.data();

        res.send(getSuccessPage(userData.email, tokenData.uid));
    } catch (error) {
        console.error('Error approving user:', error);
        res.status(500).send(getErrorPage('Server Error'));
    }
};

/**
 * Reject User by Token (Public)
 */
exports.rejectUserByToken = async (req, res) => {
    try {
        const token = req.path.split('/').pop();

        // Get token from Firestore
        const tokenDoc = await db.collection('approval_tokens').doc(token).get();

        if (!tokenDoc.exists) {
            return res.status(400).send(getErrorPage('Invalid or Expired Link'));
        }

        const tokenData = tokenDoc.data();

        // Check expiry
        if (Date.now() > tokenData.expiresAt.toMillis()) {
            await db.collection('approval_tokens').doc(token).delete();
            return res.status(400).send(getErrorPage('Link Expired'));
        }

        // Check if used
        if (tokenData.used) {
            return res.status(400).send(getErrorPage('Link Already Used'));
        }

        // Check action
        if (tokenData.action !== 'reject') {
            return res.status(400).send(getErrorPage('Invalid Action'));
        }

        // Update user status
        await db.collection('users').doc(tokenData.uid).update({
            isApproved: false,
            rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
            rejectedBy: 'email_link'
        });

        // Mark token as used
        await db.collection('approval_tokens').doc(token).update({ used: true });

        // Get user info
        const userDoc = await db.collection('users').doc(tokenData.uid).get();
        const userData = userDoc.data();

        res.send(getRejectedPage(userData.email, tokenData.uid));
    } catch (error) {
        console.error('Error rejecting user:', error);
        res.status(500).send(getErrorPage('Server Error'));
    }
};

/**
 * Save Orderflow Data (Admin Only)
 */
exports.saveOrderflow = async (req, res) => {
    try {
        // Set CORS headers
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');

        if (req.method === 'OPTIONS') {
            return res.status(204).send('');
        }

        // Verify authentication
        const user = await verifyToken(req);
        verifyAdmin(user);

        const { candleKey, buyerCount, sellerCount, isBigSignal, isMediumSignal, broadcastPush } = req.body;

        if (!candleKey || buyerCount === undefined || sellerCount === undefined) {
            return res.status(400).json({ error: 'candleKey, buyerCount, and sellerCount are required' });
        }

        await db.collection('orderflow').doc(candleKey).set({
            candleKey,
            buyerCount,
            sellerCount,
            isBigSignal: isBigSignal || false,
            isMediumSignal: isMediumSignal || false,
            broadcastPush: broadcastPush === undefined ? true : !!broadcastPush,
            updatedBy: user.uid,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        res.json({ success: true, message: 'Orderflow data saved successfully' });
    } catch (error) {
        console.error('Error saving orderflow:', error);
        res.status(500).json({ error: 'Failed to save orderflow data' });
    }
};

// ============================================
// HTML RESPONSE TEMPLATES
// ============================================

function getErrorPage(title) {
    return `
        <!DOCTYPE html>
        <html>
        <head>
            <title>${title}</title>
            <style>
                body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
                .container { background: white; padding: 40px; border-radius: 10px; text-align: center; max-width: 500px; }
                h1 { color: #dc2626; }
                p { color: #4b5563; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>❌ ${title}</h1>
                <p>This approval link is invalid, expired, or has already been used.</p>
                <p>Please request a new link or use the mobile app.</p>
            </div>
        </body>
        </html>
    `;
}

function getSuccessPage(email, uid) {
    return `
        <!DOCTYPE html>
        <html>
        <head>
            <title>User Approved</title>
            <style>
                body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
                .container { background: white; padding: 40px; border-radius: 10px; text-align: center; max-width: 500px; }
                h1 { color: #10b981; margin-bottom: 20px; }
                .user-info { background: #f3f4f6; padding: 20px; border-radius: 8px; margin: 20px 0; }
                .user-info p { margin: 10px 0; color: #1f2937; }
                .success-icon { font-size: 64px; margin-bottom: 20px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="success-icon">✅</div>
                <h1>User Approved Successfully!</h1>
                <div class="user-info">
                    <p><strong>Email:</strong> ${email}</p>
                    <p><strong>User ID:</strong> ${uid}</p>
                </div>
                <p style="color: #6b7280; font-size: 14px;">The user can now access the BIG SHOT OrderFlow application.</p>
            </div>
        </body>
        </html>
    `;
}

function getRejectedPage(email, uid) {
    return `
        <!DOCTYPE html>
        <html>
        <head>
            <title>User Rejected</title>
            <style>
                body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
                .container { background: white; padding: 40px; border-radius: 10px; text-align: center; max-width: 500px; }
                h1 { color: #dc2626; margin-bottom: 20px; }
                .user-info { background: #f3f4f6; padding: 20px; border-radius: 8px; margin: 20px 0; }
                .user-info p { margin: 10px 0; color: #1f2937; }
                .reject-icon { font-size: 64px; margin-bottom: 20px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="reject-icon">❌</div>
                <h1>User Rejected</h1>
                <div class="user-info">
                    <p><strong>Email:</strong> ${email}</p>
                    <p><strong>User ID:</strong> ${uid}</p>
                </div>
                <p style="color: #6b7280; font-size: 14px;">The user will not be able to access the BIG SHOT OrderFlow application.</p>
            </div>
        </body>
        </html>
    `;
}
