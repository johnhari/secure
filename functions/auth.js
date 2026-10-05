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
 * Send branded HTML Email Verification with Action Button
 */
const sendBrandedVerificationEmail = async (email) => {
    const config = functions.config();
    const actionCodeSettings = {
        url: 'https://orderflowterminal.web.app/terminal/index.html#/login?verified=true',
        handleCodeInApp: true,
    };

    let verificationLink = '#';
    try {
        verificationLink = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);
    } catch (err) {
        console.error('[Email] generateEmailVerificationLink error:', err);
    }

    if (config.email && config.email.user && config.email.password) {
        const transporter = nodemailer.createTransport({
            service: 'gmail',
            auth: {
                user: config.email.user,
                pass: config.email.password
            }
        });

        await transporter.sendMail({
            from: `"BIG SHOT OrderFlow Terminal" <${config.email.user}>`,
            to: email,
            subject: '🔐 Verify Your Email Address — BIG SHOT OrderFlow Terminal',
            html: `
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Verify Email - BIG SHOT OrderFlow</title>
                </head>
                <body style="margin: 0; padding: 0; background-color: #080B10; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #FFFFFF;">
                    <table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #080B10; padding: 40px 10px;">
                        <tr>
                            <td align="center">
                                <table width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width: 560px; background: rgba(15, 23, 36, 0.95); border: 1px solid rgba(0, 255, 157, 0.3); border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.8); overflow: hidden;">
                                    <!-- Header Banner -->
                                    <tr>
                                        <td align="center" style="padding: 32px 20px 20px; background: linear-gradient(180deg, rgba(0, 255, 157, 0.08) 0%, rgba(15, 23, 36, 0) 100%);">
                                            <div style="width: 70px; height: 70px; background: #000000; border-radius: 50%; border: 2px solid #00ff9d; box-shadow: 0 0 20px rgba(0,255,157,0.3); display: inline-block; overflow: hidden; vertical-align: middle;">
                                                <img src="https://orderflowterminal.web.app/assets/images/logo_bigshot.jpg" alt="BIG SHOT" width="70" height="70" style="width: 100%; height: 100%; object-fit: cover; display: block;" />
                                            </div>
                                            <h1 style="margin: 16px 0 4px; font-size: 22px; font-weight: 900; color: #00ff9d; letter-spacing: 1.5px; text-transform: uppercase;">
                                                BIG SHOT ORDERFLOW
                                            </h1>
                                            <p style="margin: 0; font-size: 12px; color: #94A3B8; font-weight: 700; letter-spacing: 1px;">
                                                INSTITUTIONAL GRADE TRADING TERMINAL
                                            </p>
                                        </td>
                                    </tr>

                                    <!-- Main Body -->
                                    <tr>
                                        <td style="padding: 24px 32px 36px; text-align: center;">
                                            <h2 style="margin: 0 0 12px; font-size: 20px; font-weight: 800; color: #FFFFFF;">
                                                Verify Your Email Address
                                            </h2>
                                            <p style="margin: 0 0 28px; font-size: 14px; line-height: 1.6; color: #CBD5E1;">
                                                Welcome to BIG SHOT OrderFlow Terminal! Please click the authorization button below to verify your email address and activate your account.
                                            </p>

                                            <!-- CTA Button -->
                                            <div style="margin: 32px 0;">
                                                <a href="${verificationLink}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #00ff9d 0%, #00b359 100%); color: #000000; font-size: 15px; font-weight: 900; padding: 16px 36px; text-decoration: none; border-radius: 30px; letter-spacing: 0.8px; box-shadow: 0 0 25px rgba(0, 255, 157, 0.4); text-transform: uppercase;">
                                                    VERIFY EMAIL &amp; AUTHORIZE ACCESS &rarr;
                                                </a>
                                            </div>

                                            <!-- Direct Link Box -->
                                            <div style="background: rgba(255, 255, 255, 0.03); border: 1px dashed rgba(255, 255, 255, 0.15); border-radius: 12px; padding: 14px; margin-top: 28px; text-align: left;">
                                                <p style="margin: 0 0 6px; font-size: 11px; color: #94A3B8; font-weight: 700; text-transform: uppercase;">
                                                    Direct Verification Link:
                                                </p>
                                                <p style="margin: 0; font-size: 11px; color: #00ff9d; word-break: break-all; font-family: monospace;">
                                                    ${verificationLink}
                                                </p>
                                            </div>

                                            <div style="margin-top: 28px; padding-top: 20px; border-top: 1px solid rgba(255,255,255,0.08); text-align: center;">
                                                <p style="margin: 0; font-size: 12px; color: #64748B; line-height: 1.5;">
                                                    If you did not request this account registration, please ignore this email.
                                                    <br>This link is valid for 24 hours.
                                                </p>
                                            </div>
                                        </td>
                                    </tr>

                                    <!-- Footer -->
                                    <tr>
                                        <td align="center" style="padding: 16px 20px; background: rgba(0, 0, 0, 0.4); border-top: 1px solid rgba(255, 255, 255, 0.05);">
                                            <p style="margin: 0; font-size: 11px; color: #475569;">
                                                &copy; 2026 BIG SHOT OrderFlow Terminal. All rights reserved.
                                            </p>
                                        </td>
                                    </tr>
                                </table>
                            </td>
                        </tr>
                    </table>
                </body>
                </html>
            `
        });
        console.log(`[Email] Branded verification email sent to ${email}`);
    }

    return verificationLink;
};

exports.sendBrandedVerificationEmail = sendBrandedVerificationEmail;

/**
 * Send Verification Email Function (Callable)
 */
exports.sendVerificationEmail = async (data) => {
    const { email } = data;
    if (!email) {
        throw new functions.https.HttpsError('invalid-argument', 'Email is required');
    }
    const link = await sendBrandedVerificationEmail(email.toLowerCase().trim());
    return { success: true, link };
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
        from: `"BIG SHOT OrderFlow Terminal" <${config.email.user}>`,
        to: email,
        subject: '🔐 Your Verification OTP - BIG SHOT OrderFlow',
        html: `
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; background: #080B10; color: #fff; border-radius: 16px; overflow: hidden; border: 1px solid rgba(0,255,157,0.3);">
                <div style="background: linear-gradient(135deg, #00ff9d 0%, #00b359 100%); padding: 24px; text-align: center;">
                    <h1 style="color: #000; margin: 0; font-size: 24px; font-weight: 900; letter-spacing: 1px;">BIG SHOT ORDERFLOW</h1>
                </div>
                <div style="padding: 30px; text-align: center;">
                    <h2 style="color: #fff; margin-top: 0;">Your Verification OTP</h2>
                    <div style="background: rgba(255,255,255,0.05); padding: 20px; border-radius: 12px; text-align: center; margin: 20px 0; border: 1px solid rgba(0,255,157,0.2);">
                        <h1 style="color: #00ff9d; font-size: 44px; margin: 0; letter-spacing: 8px; font-weight: 900;">${otp}</h1>
                    </div>
                    <p style="color: #94A3B8; font-size: 14px;">This OTP will expire in ${OTP_EXPIRY_MINUTES} minutes.</p>
                    <p style="color: #64748B; font-size: 12px; margin-top: 20px;">If you didn't request this OTP, please ignore this email.</p>
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
