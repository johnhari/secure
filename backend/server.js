require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const WebSocket = require('ws');
const admin = require('firebase-admin');
const rateLimit = require('express-rate-limit');

// Initialize Firebase Admin
const serviceAccount = require(process.env.FIREBASE_SERVICE_ACCOUNT_PATH);
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: `https://${serviceAccount.project_id}-default-rtdb.firebaseio.com`
});

// Import services and routes
const { initializeYahoo } = require('./services/yahoo.service');
const SimulationService = require('./services/simulation.service');
const { setupStreamHandler } = require('./websocket/stream.handler');
const adminRoutes = require('./routes/admin.routes');
const authRoutes = require('./routes/auth.routes');
const authMiddleware = require('./middleware/auth.middleware');

// Ensure Admin User 'jivaspcet@gmail.com' has specific password and admin role
const ensureAdminUser = async () => {
    const email = 'jivaspcet@gmail.com';
    const password = '143000';
    try {
        let userRecord;
        try {
            userRecord = await admin.auth().getUserByEmail(email);
            await admin.auth().updateUser(userRecord.uid, {
                password: password,
                emailVerified: true
            });
            console.log(`[Auth] Admin user ${email} password updated/verified.`);
        } catch (e) {
            if (e.code === 'auth/user-not-found') {
                userRecord = await admin.auth().createUser({
                    email: email,
                    password: password,
                    emailVerified: true
                });
                console.log(`[Auth] Admin user ${email} created with default password.`);
            } else {
                throw e;
            }
        }

        // Also ensure Firestore profile has admin role
        const db = admin.firestore();
        const usersCollection = process.env.FIRESTORE_COLLECTION_USERS || 'users';
        await db.collection(usersCollection).doc(userRecord.uid).set({
            uid: userRecord.uid,
            email: email,
            role: 'admin',
            isApproved: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(`[Auth] Admin user ${email} Firestore profile ensured with admin role.`);

    } catch (e) {
        console.error('[Auth] Error ensuring admin user:', e);
    }
};
ensureAdminUser();

// Create Express app
const app = express();
const server = http.createServer(app);

// Middleware
app.use(cors({
    origin: '*', // In production, specify allowed origins
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    credentials: true
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rate limiting
const limiter = rateLimit({
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 900000, // 15 minutes
    max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
    message: 'Too many requests from this IP, please try again later.'
});

app.use('/api', limiter);

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Auth routes (public)
app.use('/api/auth', authRoutes);

// Admin routes (protected)
app.use('/api/admin', authMiddleware.verifyToken, authMiddleware.verifyAdmin, adminRoutes);

// WebSocket server
const wss = new WebSocket.Server({
    server,
    path: '/stream'
});

// Initialize data service
let dataService;
(async () => {
    try {
        console.log('Initializing m.Stock real-time service...');
        const { initializeMStock } = require('./services/mstock.service');
        dataService = await initializeMStock();
        console.log('m.Stock service initialized (Primary Source)');
    } catch (mstockError) {
        console.warn('m.Stock service failed:', mstockError.message);
        try {
            console.log('Falling back to Yahoo Finance service...');
            dataService = await initializeYahoo();
            console.log('Yahoo Finance service initialized (Secondary Source)');
        } catch (yahooError) {
            console.error('Yahoo Finance service also failed:', yahooError.message);
            console.log('Falling back to Simulation Mode...');
            dataService = new SimulationService();
            dataService.start();
        }
    }

    // Setup WebSocket stream handler
    setupStreamHandler(wss, dataService);
})();

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Error:', err);
    res.status(err.status || 500).json({
        error: {
            message: err.message || 'Internal server error',
            status: err.status || 500
        }
    });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`WebSocket endpoint: ws://localhost:${PORT}/stream`);
    console.log(`Environment: ${process.env.NODE_ENV}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM signal received: closing HTTP server');
    server.close(() => {
        console.log('HTTP server closed');
        process.exit(0);
    });
});

module.exports = { app, server, admin };
