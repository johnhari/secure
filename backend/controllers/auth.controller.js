const admin = require('firebase-admin');
const emailService = require('../services/email.service');

// OTP Store with rate limiting (Use Redis for production)
const otpStore = new Map(); // email -> { otp, expiresAt, attempts }
const rateLimitStore = new Map(); // email -> { count, resetAt }

// Constants
const OTP_EXPIRY_MINUTES = 5;
const MAX_OTP_ATTEMPTS = 3;
const RATE_LIMIT_WINDOW_MINUTES = 10;
const MAX_OTPS_PER_WINDOW = 3;

/**
 * Check rate limit for OTP requests
 */
const checkRateLimit = (email) => {
    const now = Date.now();
    const limit = rateLimitStore.get(email);

    if (!limit || now > limit.resetAt) {
        rateLimitStore.set(email, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MINUTES * 60 * 1000 });
        return true;
    }

    if (limit.count >= MAX_OTPS_PER_WINDOW) {
        return false;
    }

    limit.count++;
    return true;
};

/**
 * Generate 6-digit OTP
 */
const generateOtp = () => {
    return Math.floor(100000 + Math.random() * 900000).toString();
};

/**
 * Validate email format
 */
const isValidEmail = (email) => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return email && emailRegex.test(email);
};

/**
 * Send OTP for registration
 * POST /api/auth/send-otp
 */
const sendOtp = async (req, res) => {
    try {
        const { email } = req.body;

        // Validate email
        if (!email || !isValidEmail(email)) {
            return res.status(400).json({ error: 'Valid email is required' });
        }

        const normalizedEmail = email.toLowerCase().trim();

        // Check rate limit
        if (!checkRateLimit(normalizedEmail)) {
            return res.status(429).json({
                error: 'Too many OTP requests. Please try again later.',
                retryAfter: RATE_LIMIT_WINDOW_MINUTES
            });
        }

        // Check if user already exists
        try {
            await admin.auth().getUserByEmail(normalizedEmail);
            return res.status(400).json({ error: 'Email already registered. Please login instead.' });
        } catch (error) {
            if (error.code !== 'auth/user-not-found') {
                throw error;
            }
            // User doesn't exist - proceed with registration
        }

        // Generate OTP
        const otp = generateOtp();
        const expiresAt = Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000;

        otpStore.set(normalizedEmail, { otp, expiresAt, attempts: 0 });

        // Send Email
        const sent = await emailService.sendEmail(
            normalizedEmail,
            'Your Orderflow Verification Code',
            `Your verification code is: ${otp}\n\nThis code will expire in ${OTP_EXPIRY_MINUTES} minutes.\n\nIf you didn't request this code, please ignore this email.`
        );

        if (sent) {
            res.status(200).json({
                message: 'OTP sent successfully',
                expiresIn: OTP_EXPIRY_MINUTES * 60 // seconds
            });
        } else {
            res.status(500).json({ error: 'Failed to send OTP. Please try again.' });
        }

    } catch (error) {
        console.error('Send OTP Error:', error);
        res.status(500).json({ error: 'An error occurred. Please try again.' });
    }
};

/**
 * Verify OTP and Register User
 * POST /api/auth/verify-register
 */
const verifyAndRegister = async (req, res) => {
    try {
        const { email, otp, password } = req.body;

        // Validate inputs
        if (!email || !isValidEmail(email)) {
            return res.status(400).json({ error: 'Valid email is required' });
        }
        if (!otp || otp.length !== 6) {
            return res.status(400).json({ error: 'Valid 6-digit OTP is required' });
        }
        if (!password || password.length < 6) {
            return res.status(400).json({ error: 'Password must be at least 6 characters' });
        }

        const normalizedEmail = email.toLowerCase().trim();
        const storedData = otpStore.get(normalizedEmail);

        if (!storedData) {
            return res.status(400).json({ error: 'OTP not found. Please request a new one.' });
        }

        // Check expiry
        if (Date.now() > storedData.expiresAt) {
            otpStore.delete(normalizedEmail);
            return res.status(400).json({ error: 'OTP expired. Please request a new one.' });
        }

        // Check attempts
        if (storedData.attempts >= MAX_OTP_ATTEMPTS) {
            otpStore.delete(normalizedEmail);
            return res.status(400).json({ error: 'Too many invalid attempts. Please request a new OTP.' });
        }

        // Verify OTP
        if (storedData.otp !== otp) {
            storedData.attempts++;
            const remainingAttempts = MAX_OTP_ATTEMPTS - storedData.attempts;
            return res.status(400).json({
                error: `Invalid OTP. ${remainingAttempts} attempt(s) remaining.`
            });
        }

        // OTP Verified - Create User
        const userRecord = await admin.auth().createUser({
            email: normalizedEmail,
            password: password,
            emailVerified: true
        });

        // Clear OTP
        otpStore.delete(normalizedEmail);

        // Create user profile in Firestore
        const db = admin.firestore();
        const newUserProfile = {
            uid: userRecord.uid,
            email: normalizedEmail,
            role: 'viewer',
            isApproved: false, // NEW: Requires admin approval
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection(process.env.FIRESTORE_COLLECTION_USERS || 'users')
            .doc(userRecord.uid)
            .set(newUserProfile);

        // Notify admins about new registration (FCM + Email)
        notifyAdminsOfNewUser(newUserProfile);

        res.status(201).json({
            message: 'Registration successful. Please wait for admin approval.',
            uid: userRecord.uid,
            email: userRecord.email
        });

    } catch (error) {
        console.error('Verify OTP Error:', error);
        if (error.code === 'auth/email-already-exists') {
            return res.status(400).json({ error: 'Email already registered. Please login.' });
        }
        res.status(500).json({ error: 'Registration failed. Please try again.' });
    }
};

/**
 * Send OTP for Password Reset
 * POST /api/auth/forgot-password
 */
const forgotPassword = async (req, res) => {
    try {
        const { email } = req.body;

        if (!email || !isValidEmail(email)) {
            return res.status(400).json({ error: 'Valid email is required' });
        }

        const normalizedEmail = email.toLowerCase().trim();

        // Check rate limit
        if (!checkRateLimit(normalizedEmail)) {
            return res.status(429).json({
                error: 'Too many requests. Please try again later.',
                retryAfter: RATE_LIMIT_WINDOW_MINUTES
            });
        }

        // Check if user exists
        try {
            await admin.auth().getUserByEmail(normalizedEmail);
        } catch (error) {
            if (error.code === 'auth/user-not-found') {
                // Don't reveal if email exists for security
                return res.status(200).json({ message: 'If the email exists, a reset code has been sent.' });
            }
            throw error;
        }

        // Generate OTP
        const otp = generateOtp();
        const expiresAt = Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000;

        otpStore.set(`reset_${normalizedEmail}`, { otp, expiresAt, attempts: 0 });

        // Send Email
        const sent = await emailService.sendEmail(
            normalizedEmail,
            'Password Reset Code - Orderflow',
            `Your password reset code is: ${otp}\n\nThis code will expire in ${OTP_EXPIRY_MINUTES} minutes.\n\nIf you didn't request this, please ignore this email.`
        );

        if (sent) {
            res.status(200).json({
                message: 'Reset code sent successfully',
                expiresIn: OTP_EXPIRY_MINUTES * 60
            });
        } else {
            res.status(500).json({ error: 'Failed to send reset code. Please try again.' });
        }

    } catch (error) {
        console.error('Forgot Password Error:', error);
        res.status(500).json({ error: 'An error occurred. Please try again.' });
    }
};

/**
 * Reset Password with OTP
 * POST /api/auth/reset-password
 */
const resetPassword = async (req, res) => {
    try {
        const { email, otp, newPassword } = req.body;

        if (!email || !isValidEmail(email)) {
            return res.status(400).json({ error: 'Valid email is required' });
        }
        if (!otp || otp.length !== 6) {
            return res.status(400).json({ error: 'Valid 6-digit OTP is required' });
        }
        if (!newPassword || newPassword.length < 6) {
            return res.status(400).json({ error: 'Password must be at least 6 characters' });
        }

        const normalizedEmail = email.toLowerCase().trim();
        const storedData = otpStore.get(`reset_${normalizedEmail}`);

        if (!storedData) {
            return res.status(400).json({ error: 'Reset code not found. Please request a new one.' });
        }

        if (Date.now() > storedData.expiresAt) {
            otpStore.delete(`reset_${normalizedEmail}`);
            return res.status(400).json({ error: 'Reset code expired. Please request a new one.' });
        }

        if (storedData.attempts >= MAX_OTP_ATTEMPTS) {
            otpStore.delete(`reset_${normalizedEmail}`);
            return res.status(400).json({ error: 'Too many invalid attempts. Please request a new code.' });
        }

        if (storedData.otp !== otp) {
            storedData.attempts++;
            const remainingAttempts = MAX_OTP_ATTEMPTS - storedData.attempts;
            return res.status(400).json({
                error: `Invalid code. ${remainingAttempts} attempt(s) remaining.`
            });
        }

        // Get user and update password
        const userRecord = await admin.auth().getUserByEmail(normalizedEmail);
        await admin.auth().updateUser(userRecord.uid, { password: newPassword });

        // Clear reset OTP
        otpStore.delete(`reset_${normalizedEmail}`);

        res.status(200).json({ message: 'Password reset successful. Please login with your new password.' });

    } catch (error) {
        console.error('Reset Password Error:', error);
        res.status(500).json({ error: 'Password reset failed. Please try again.' });
    }
};

const fcmService = require('../services/fcm.service');

/**
 * Notify all admin users about a new registration
 */
const notifyAdminsOfNewUser = async (userProfile) => {
    try {
        const db = admin.firestore();
        const adminsSnapshot = await db.collection(process.env.FIRESTORE_COLLECTION_USERS || 'users')
            .where('role', '==', 'admin')
            .get();

        if (adminsSnapshot.empty) {
            console.log('No admins found to notify');
            return;
        }

        const title = '🆕 New User Registered';
        const body = `User ${userProfile.email} is waiting for approval.`;

        adminsSnapshot.forEach(doc => {
            const adminData = doc.data();
            if (adminData.fcmToken) {
                fcmService.sendToUser(adminData.uid, title, body, {
                    type: 'new_user_registration',
                    userUid: userProfile.uid
                });
            }
        });

        // Also send email notification
        await emailService.sendNewUserNotification(userProfile);
    } catch (error) {
        console.error('Error notifying admins:', error);
    }
};

module.exports = {
    sendOtp,
    verifyAndRegister,
    forgotPassword,
    resetPassword
};
