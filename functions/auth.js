const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const functions = require('firebase-functions');

// OTP Store (using Firestore for serverless environment)
const db = admin.firestore();

// Constants
const OTP_EXPIRY_MINUTES = 5;
const MAX_OTP_ATTEMPTS = 3;
const RATE_LIMIT_WINDOW_MINUTES = 10;
const MAX_OTPS_PER_WINDOW = 3;

/**
 * Check rate limit for OTP requests
 */
const checkRateLimit = async (email) => {
    const now = Date.now();
    const rateLimitRef = db.collection('rate_limits').doc(email);
    const rateLimitDoc = await rateLimitRef.get();

    if (!rateLimitDoc.exists) {
        // First request
        await rateLimitRef.set({
            count: 1,
            resetAt: now + (RATE_LIMIT_WINDOW_MINUTES * 60 * 1000)
        });
        return true;
    }

    const rateLimit = rateLimitDoc.data();

    if (now > rateLimit.resetAt) {
        // Reset window
        await rateLimitRef.set({
            count: 1,
            resetAt: now + (RATE_LIMIT_WINDOW_MINUTES * 60 * 1000)
        });
        return true;
    }

    if (rateLimit.count >= MAX_OTPS_PER_WINDOW) {
        throw new functions.https.HttpsError(
            'resource-exhausted',
            `Too many OTP requests. Please try again after ${Math.ceil((rateLimit.resetAt - now) / 60000)} minutes.`
        );
    }

    await rateLimitRef.update({
        count: admin.firestore.FieldValue.increment(1)
    });

    return true;
};

/**
 * Generate 6-digit OTP
 */
const generateOTP = () => {
    return Math.floor(100000 + Math.random() * 900000).toString();
};

/**
 * Send OTP via email
 */
const sendOtpEmail = async (email, otp) => {
    const config = functions.config();

    const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {
            user: config.email.user,
            pass: config.email.password
        }
    });

    await transporter.sendMail({
        from: `"BIG SHOT OrderFlow" <${config.email.user}>`,
        to: email,
        subject: 'Your OTP for BIG SHOT OrderFlow',
        html: `
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; text-align: center;">
                    <h1 style="color: white; margin: 0;">BIG SHOT OrderFlow</h1>
                </div>
                <div style="padding: 30px; background-color: #f9fafb;">
                    <h2>Your One-Time Password</h2>
                    <div style="background: white; padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0;">
                        <h1 style="color: #667eea; font-size: 48px; margin: 0; letter-spacing: 8px;">${otp}</h1>
                    </div>
                    <p>This OTP will expire in ${OTP_EXPIRY_MINUTES} minutes.</p>
                    <p style="color: #6b7280; font-size: 12px;">If you didn't request this OTP, please ignore this email.</p>
                </div>
            </div>
        `
    });
};

/**
 * Send OTP Function
 */
exports.sendOtp = async (data) => {
    const { email } = data;

    if (!email) {
        throw new functions.https.HttpsError('invalid-argument', 'Email is required');
    }

    const normalizedEmail = email.toLowerCase().trim();

    // Check rate limit
    await checkRateLimit(normalizedEmail);

    // Generate OTP
    const otp = generateOTP();
    const expiresAt = Date.now() + (OTP_EXPIRY_MINUTES * 60 * 1000);

    // Store OTP in Firestore
    await db.collection('otps').doc(normalizedEmail).set({
        otp,
        expiresAt,
        attempts: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Send email
    await sendOtpEmail(normalizedEmail, otp);

    return {
        success: true,
        message: `OTP sent to ${normalizedEmail}. Valid for ${OTP_EXPIRY_MINUTES} minutes.`
    };
};

/**
 * Verify OTP and Register User
 */
exports.verifyAndRegister = async (data) => {
    const { email, otp, password } = data;

    if (!email || !otp || !password) {
        throw new functions.https.HttpsError('invalid-argument', 'Email, OTP, and password are required');
    }

    const normalizedEmail = email.toLowerCase().trim();

    // Get OTP from Firestore
    const otpDoc = await db.collection('otps').doc(normalizedEmail).get();

    if (!otpDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'OTP not found or expired');
    }

    const otpData = otpDoc.data();

    // Check expiry
    if (Date.now() > otpData.expiresAt) {
        await db.collection('otps').doc(normalizedEmail).delete();
        throw new functions.https.HttpsError('deadline-exceeded', 'OTP has expired');
    }

    // Check attempts
    if (otpData.attempts >= MAX_OTP_ATTEMPTS) {
        await db.collection('otps').doc(normalizedEmail).delete();
        throw new functions.https.HttpsError('permission-denied', 'Maximum OTP attempts exceeded');
    }

    // Verify OTP
    if (otpData.otp !== otp) {
        await db.collection('otps').doc(normalizedEmail).update({
            attempts: admin.firestore.FieldValue.increment(1)
        });
        const remainingAttempts = MAX_OTP_ATTEMPTS - (otpData.attempts + 1);
        throw new functions.https.HttpsError(
            'invalid-argument',
            `Invalid OTP. ${remainingAttempts} attempt(s) remaining.`
        );
    }

    // Create user in Firebase Auth
    const userRecord = await admin.auth().createUser({
        email: normalizedEmail,
        password: password,
        emailVerified: true
    });

    // Delete OTP
    await db.collection('otps').doc(normalizedEmail).delete();

    // Create user profile in Firestore
    await db.collection('users').doc(userRecord.uid).set({
        uid: userRecord.uid,
        email: normalizedEmail,
        role: 'viewer',
        isApproved: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return {
        success: true,
        message: 'Registration successful. Please wait for admin approval.',
        uid: userRecord.uid
    };
};

/**
 * Forgot Password Function
 */
exports.forgotPassword = async (data) => {
    const { email } = data;

    if (!email) {
        throw new functions.https.HttpsError('invalid-argument', 'Email is required');
    }

    const normalizedEmail = email.toLowerCase().trim();

    // Check if user exists
    try {
        await admin.auth().getUserByEmail(normalizedEmail);
    } catch (error) {
        throw new functions.https.HttpsError('not-found', 'No account found with this email');
    }

    // Check rate limit
    await checkRateLimit(`reset_${normalizedEmail}`);

    // Generate OTP
    const otp = generateOTP();
    const expiresAt = Date.now() + (OTP_EXPIRY_MINUTES * 60 * 1000);

    // Store reset OTP
    await db.collection('reset_otps').doc(normalizedEmail).set({
        otp,
        expiresAt,
        attempts: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Send email
    await sendOtpEmail(normalizedEmail, otp);

    return {
        success: true,
        message: `Reset OTP sent to ${normalizedEmail}`
    };
};

/**
 * Reset Password Function
 */
exports.resetPassword = async (data) => {
    const { email, otp, newPassword } = data;

    if (!email || !otp || !newPassword) {
        throw new functions.https.HttpsError('invalid-argument', 'Email, OTP, and new password are required');
    }

    const normalizedEmail = email.toLowerCase().trim();

    // Get reset OTP
    const otpDoc = await db.collection('reset_otps').doc(normalizedEmail).get();

    if (!otpDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Reset OTP not found or expired');
    }

    const otpData = otpDoc.data();

    // Check expiry
    if (Date.now() > otpData.expiresAt) {
        await db.collection('reset_otps').doc(normalizedEmail).delete();
        throw new functions.https.HttpsError('deadline-exceeded', 'Reset OTP has expired');
    }

    // Verify OTP
    if (otpData.otp !== otp) {
        await db.collection('reset_otps').doc(normalizedEmail).update({
            attempts: admin.firestore.FieldValue.increment(1)
        });
        throw new functions.https.HttpsError('invalid-argument', 'Invalid reset OTP');
    }

    // Update password
    const userRecord = await admin.auth().getUserByEmail(normalizedEmail);
    await admin.auth().updateUser(userRecord.uid, { password: newPassword });

    // Delete reset OTP
    await db.collection('reset_otps').doc(normalizedEmail).delete();

    return {
        success: true,
        message: 'Password reset successful'
    };
};
