const admin = require('firebase-admin');

/**
 * Middleware to verify Firebase ID token
 */
const verifyToken = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;

        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({ error: 'Unauthorized: No token provided' });
        }

        const token = authHeader.split('Bearer ')[1];

        // Verify the token with Firebase Admin
        const decodedToken = await admin.auth().verifyIdToken(token);

        // Attach user info to request
        req.user = {
            uid: decodedToken.uid,
            email: decodedToken.email,
            phoneNumber: decodedToken.phone_number
        };

        // Fetch user profile from Firestore to get role
        const db = admin.firestore();
        const userDoc = await db.collection(process.env.FIRESTORE_COLLECTION_USERS || 'users')
            .doc(decodedToken.uid)
            .get();

        if (userDoc.exists) {
            req.user.role = userDoc.data().role || 'viewer';
            req.user.profile = userDoc.data();
        } else {
            // Create default viewer profile if doesn't exist
            req.user.role = 'viewer';
            await db.collection(process.env.FIRESTORE_COLLECTION_USERS || 'users')
                .doc(decodedToken.uid)
                .set({
                    uid: decodedToken.uid,
                    role: 'viewer',
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    email: decodedToken.email || null,
                    phoneNumber: decodedToken.phone_number || null
                });
        }

        next();
    } catch (error) {
        console.error('Token verification error:', error);

        if (error.code === 'auth/id-token-expired') {
            return res.status(401).json({ error: 'Token expired' });
        }

        return res.status(401).json({ error: 'Unauthorized: Invalid token' });
    }
};

/**
 * Middleware to verify admin role
 */
const verifyAdmin = (req, res, next) => {
    if (!req.user) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    const masterAdminEmails = ['jivaspcet@gmail.com', 'jivaspect@gmail.com', 'whatsapplivestatus@gmail.com'];
    if (req.user.role !== 'admin' || !masterAdminEmails.includes(req.user.email)) {
        return res.status(403).json({ error: 'Forbidden: Admin access required' });
    }


    next();
};

/**
 * Extract token and deviceId from WebSocket upgrade request
 */
const extractTokenFromWS = (request) => {
    try {
        const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
        const token = url.searchParams.get('token');
        const deviceId = url.searchParams.get('deviceId');
        return { token, deviceId };
    } catch (error) {
        console.error('Error extracting data from WebSocket:', error);
        return { token: null, deviceId: null };
    }
};

/**
 * Verify WebSocket token and return user info
 */
const verifyWSToken = async (token, deviceId) => {
    try {
        if (!token) {
            throw new Error('No token provided');
        }

        const decodedToken = await admin.auth().verifyIdToken(token);
        const uid = decodedToken.uid;

        // Fetch user profile from Firestore (single read, reused for both admin check and role)
        const firestore = admin.firestore();
        const userDoc = await firestore.collection(process.env.FIRESTORE_COLLECTION_USERS || 'users')
            .doc(uid)
            .get();

        let role = 'viewer';
        let isApproved = false;

        if (userDoc.exists) {
            const userData = userDoc.data();
            role = userData.role || 'viewer';
            isApproved = userData.isApproved === true;
        }

        // Check single-device session in Realtime Database
        // Admin users bypass this — they can be on both Android and Desktop
        const db = admin.database();
        const sessionRef = db.ref(`sessions/${uid}`);
        const snapshot = await sessionRef.get();

        if (snapshot.exists()) {
            const session = snapshot.val();

            if (role !== 'admin' && deviceId && session.activeDeviceId && session.activeDeviceId !== deviceId) {
                console.warn(`[Auth] Session mismatch for ${uid}. Expected ${session.activeDeviceId}, got ${deviceId}`);
                throw new Error('MULTIPLE_DEVICE_LOGIN');
            }
        }

        // Enforce approval (admins are always approved)
        if (!isApproved && role !== 'admin') {
            console.warn(`[Auth] User ${uid} is not approved.`);
            throw new Error('UNAPPROVED_USER');
        }

        return {
            uid: uid,
            email: decodedToken.email,
            phoneNumber: decodedToken.phone_number,
            role
        };
    } catch (error) {
        console.error('WebSocket token verification error:', error.message);
        throw error;
    }
};

module.exports = {
    verifyToken,
    verifyAdmin,
    extractTokenFromWS,
    verifyWSToken
};
