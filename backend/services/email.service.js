const nodemailer = require('nodemailer');

/**
 * Email Service for sending notifications
 */
class EmailService {
    constructor() {
        this.transporter = null;
        this.adminEmail = process.env.ADMIN_EMAIL || 'jivaspcet@gmail.com';
        this.initialize();
    }

    /**
     * Initialize email transporter
     */
    initialize() {
        try {
            // Create transporter using Gmail SMTP
            this.transporter = nodemailer.createTransport({
                service: 'gmail',
                auth: {
                    user: process.env.EMAIL_USER,
                    pass: process.env.EMAIL_PASSWORD // Use App Password for Gmail
                }
            });

            console.log('[Email] Email service initialized');
        } catch (error) {
            console.error('[Email] Failed to initialize email service:', error.message);
        }
    }

    /**
     * Send email notification to admin about new user registration
     * @param {Object} userProfile - New user profile data
     */
    async sendNewUserNotification(userProfile) {
        if (!this.transporter) {
            console.warn('[Email] Email service not configured. Skipping email notification.');
            return;
        }

        // Skip notification for superuser
        if (userProfile.email === 'jivaspcet@gmail.com') {
            console.log('[Email] Skipping notification for superuser');
            return;
        }

        try {
            const tokenService = require('./token.service');

            // Generate secure tokens for approve/reject actions
            const approveToken = tokenService.generateToken(userProfile.uid, 'approve', 24);
            const rejectToken = tokenService.generateToken(userProfile.uid, 'reject', 24);

            // Build approval URLs
            const backendUrl = process.env.BACKEND_URL || 'http://localhost:3000';
            const approveUrl = `${backendUrl}/api/admin/approve-user/${approveToken}`;
            const rejectUrl = `${backendUrl}/api/admin/reject-user/${rejectToken}`;

            const mailOptions = {
                from: `"BIG SHOT OrderFlow" <${process.env.EMAIL_USER}>`,
                to: this.adminEmail,
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
                                <strong>Alternative Method:</strong> You can also approve users via the mobile app:
                            </p>
                            <ol style="color: #4b5563; font-size: 14px;">
                                <li>Open the BIG SHOT OrderFlow mobile app</li>
                                <li>Navigate to the Admin Panel (tap the admin icon)</li>
                                <li>Go to the "Users" tab</li>
                                <li>Find this user and tap ✅ to approve or ❌ to reject</li>
                            </ol>
                            
                            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e5e7eb; color: #6b7280; font-size: 12px;">
                                <p>This is an automated notification from BIG SHOT OrderFlow system.</p>
                                <p>Please do not reply to this email.</p>
                            </div>
                        </div>
                    </div>
                `
            };

            await this.transporter.sendMail(mailOptions);
            console.log(`[Email] Notification sent to ${this.adminEmail} for new user: ${userProfile.email}`);
        } catch (error) {
            console.error('[Email] Failed to send notification:', error.message);
        }
    }

    /**
     * Generic send email function (legacy support)
     */
    async sendEmail(to, subject, text) {
        if (!this.transporter) {
            console.warn('[Email] Email service not configured.');
            return false;
        }

        try {
            const mailOptions = {
                from: process.env.EMAIL_USER,
                to: to,
                subject: subject,
                text: text
            };

            const info = await this.transporter.sendMail(mailOptions);
            console.log('[Email] Email sent: ' + info.response);
            return true;
        } catch (error) {
            console.error('[Email] Error sending email:', error);
            return false;
        }
    }
}

module.exports = new EmailService();
