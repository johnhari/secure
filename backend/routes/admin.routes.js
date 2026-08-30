const express = require('express');
const OrderflowService = require('../services/orderflow.service');

const router = express.Router();
const orderflowService = new OrderflowService();

/**
 * POST /api/admin/orderflow
 * Save buyer/seller count for a candle
 */
router.post('/orderflow', async (req, res) => {
    try {
        const { candleKey, buyerCount, sellerCount, isBigSignal, broadcastPush } = req.body;

        // Validation
        if (!candleKey) {
            return res.status(400).json({ error: 'candleKey is required' });
        }

        if (buyerCount === undefined || sellerCount === undefined) {
            return res.status(400).json({ error: 'buyerCount and sellerCount are required' });
        }

        if (isNaN(buyerCount) || isNaN(sellerCount)) {
            return res.status(400).json({ error: 'buyerCount and sellerCount must be numbers' });
        }

        if (buyerCount < 0 || sellerCount < 0) {
            return res.status(400).json({ error: 'buyerCount and sellerCount must be positive' });
        }

        // Save orderflow data
        const result = await orderflowService.saveOrderflow(
            candleKey,
            buyerCount,
            sellerCount,
            req.user.uid,
            isBigSignal,
            null, // candleTime
            false, // isMediumSignal
            null, // footprint
            broadcastPush !== false // broadcastPush
        );

        res.json({
            success: true,
            data: result
        });
    } catch (error) {
    console.error('Error in POST /admin/orderflow:', error);
    res.status(500).json({ error: 'Failed to save orderflow data' });
}
});

/**
 * GET /api/admin/orderflow/:candleKey
 * Get orderflow data for a specific candle
 */
router.get('/orderflow/:candleKey', async (req, res) => {
    try {
        const { candleKey } = req.params;

        const data = await orderflowService.getOrderflow(candleKey);

        if (!data) {
            return res.status(404).json({ error: 'Orderflow data not found' });
        }

        res.json({
            success: true,
            data
        });
    } catch (error) {
        console.error('Error in GET /admin/orderflow/:candleKey:', error);
        res.status(500).json({ error: 'Failed to retrieve orderflow data' });
    }
});

/**
 * GET /api/admin/orderflow
 * Query orderflow data by symbol and date
 */
router.get('/orderflow', async (req, res) => {
    try {
        const { symbol, date } = req.query;

        if (!symbol) {
            return res.status(400).json({ error: 'symbol query parameter is required' });
        }

        const queryDate = date ? new Date(date) : new Date();

        const data = await orderflowService.getOrderflowBySymbolAndDate(symbol, queryDate);

        res.json({
            success: true,
            count: data.length,
            data
        });
    } catch (error) {
        console.error('Error in GET /admin/orderflow:', error);
        res.status(500).json({ error: 'Failed to query orderflow data' });
    }
});

/**
 * DELETE /api/admin/orderflow/cleanup
 * Delete old orderflow data
 */
router.delete('/orderflow/cleanup', async (req, res) => {
    try {
        const { beforeDate } = req.query;

        if (!beforeDate) {
            return res.status(400).json({ error: 'beforeDate query parameter is required' });
        }

        const count = await orderflowService.deleteOldOrderflow(new Date(beforeDate));

        res.json({
            success: true,
            deletedCount: count
        });
    } catch (error) {
        console.error('Error in DELETE /admin/orderflow/cleanup:', error);
        res.status(500).json({ error: 'Failed to delete old orderflow data' });
    }
});

const admin = require('firebase-admin');

/**
 * GET /api/admin/users
 * List all users or filter by status
 */
router.get('/users', async (req, res) => {
    try {
        const { isApproved } = req.query;
        const db = admin.firestore();
        let query = db.collection('users');

        if (isApproved !== undefined) {
            query = query.where('isApproved', '==', isApproved === 'true');
        }

        const snapshot = await query.limit(50).get();
        const users = snapshot.docs.map(doc => doc.data());

        res.json({ success: true, count: users.length, users });
    } catch (error) {
        console.error('Error fetching users:', error);
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});

/**
 * PUT /api/admin/users/:uid/status
 * Approve or Reject a user
 */
router.put('/users/:uid/status', async (req, res) => {
    try {
        const { uid } = req.params;
        const { isApproved } = req.body;

        if (isApproved === undefined) {
            return res.status(400).json({ error: 'isApproved field is required' });
        }

        const db = admin.firestore();
        await db.collection('users').doc(uid).update({
            isApproved: isApproved,
            approvedAt: isApproved ? admin.firestore.FieldValue.serverTimestamp() : null,
            approvedBy: isApproved ? req.user.uid : null
        });

        res.json({ success: true, message: `User ${isApproved ? 'approved' : 'rejected'} successfully` });
    } catch (error) {
        console.error('Error updating user status:', error);
        res.status(500).json({ error: 'Failed to update user status' });
    }
});

/**
 * GET /api/admin/approve-user/:token
 * Approve user via email link (NO AUTH REQUIRED)
 */
router.get('/approve-user/:token', async (req, res) => {
    try {
        const { token } = req.params;
        const tokenService = require('../services/token.service');

        // Verify token
        const tokenData = tokenService.verifyToken(token);

        if (!tokenData) {
            return res.status(400).send(`
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Invalid Token</title>
                    <style>
                        body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
                        .container { background: white; padding: 40px; border-radius: 10px; text-align: center; max-width: 500px; }
                        h1 { color: #dc2626; }
                        p { color: #4b5563; }
                    </style>
                </head>
                <body>
                    <div class="container">
                        <h1>❌ Invalid or Expired Link</h1>
                        <p>This approval link is invalid or has already been used.</p>
                        <p>Please request a new approval link or use the mobile app.</p>
                    </div>
                </body>
                </html>
            `);
        }

        // Check action type
        if (tokenData.action !== 'approve') {
            return res.status(400).send('Invalid token action');
        }

        // Update user status
        const admin = require('firebase-admin');
        const db = admin.firestore();
        await db.collection('users').doc(tokenData.uid).update({
            isApproved: true,
            approvedAt: admin.firestore.FieldValue.serverTimestamp(),
            approvedBy: 'email_link'
        });

        // Get user info for success message
        const userDoc = await db.collection('users').doc(tokenData.uid).get();
        const userData = userDoc.data();

        res.send(`
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
                        <p><strong>Email:</strong> ${userData?.email || 'N/A'}</p>
                        <p><strong>User ID:</strong> ${tokenData.uid}</p>
                    </div>
                    <p style="color: #6b7280; font-size: 14px;">The user can now access the BIG SHOT OrderFlow application.</p>
                </div>
            </body>
            </html>
        `);

        console.log(`[Admin] User ${tokenData.uid} approved via email link`);
    } catch (error) {
        console.error('Error approving user:', error);
        res.status(500).send('Failed to approve user');
    }
});

/**
 * GET /api/admin/reject-user/:token
 * Reject user via email link (NO AUTH REQUIRED)
 */
router.get('/reject-user/:token', async (req, res) => {
    try {
        const { token } = req.params;
        const tokenService = require('../services/token.service');

        // Verify token
        const tokenData = tokenService.verifyToken(token);

        if (!tokenData) {
            return res.status(400).send(`
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Invalid Token</title>
                    <style>
                        body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
                        .container { background: white; padding: 40px; border-radius: 10px; text-align: center; max-width: 500px; }
                        h1 { color: #dc2626; }
                        p { color: #4b5563; }
                    </style>
                </head>
                <body>
                    <div class="container">
                        <h1>❌ Invalid or Expired Link</h1>
                        <p>This rejection link is invalid or has already been used.</p>
                        <p>Please request a new link or use the mobile app.</p>
                    </div>
                </body>
                </html>
            `);
        }

        // Check action type
        if (tokenData.action !== 'reject') {
            return res.status(400).send('Invalid token action');
        }

        // Update user status (keep isApproved as false, just mark as rejected)
        const admin = require('firebase-admin');
        const db = admin.firestore();
        await db.collection('users').doc(tokenData.uid).update({
            isApproved: false,
            rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
            rejectedBy: 'email_link'
        });

        // Get user info for message
        const userDoc = await db.collection('users').doc(tokenData.uid).get();
        const userData = userDoc.data();

        res.send(`
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
                        <p><strong>Email:</strong> ${userData?.email || 'N/A'}</p>
                        <p><strong>User ID:</strong> ${tokenData.uid}</p>
                    </div>
                    <p style="color: #6b7280; font-size: 14px;">The user will not be able to access the BIG SHOT OrderFlow application.</p>
                </div>
            </body>
            </html>
        `);

        console.log(`[Admin] User ${tokenData.uid} rejected via email link`);
    } catch (error) {
        console.error('Error rejecting user:', error);
        res.status(500).send('Failed to reject user');
    }
});

module.exports = router;
