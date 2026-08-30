const crypto = require('crypto');

/**
 * Token Service for generating secure approval tokens
 */
class TokenService {
    constructor() {
        this.tokens = new Map(); // token -> { uid, action, expiresAt }
        this.secret = process.env.APPROVAL_TOKEN_SECRET || 'default-secret-change-me';

        // Clean up expired tokens every hour
        setInterval(() => this.cleanupExpiredTokens(), 60 * 60 * 1000);
    }

    /**
     * Generate a secure approval token
     * @param {string} uid - User ID to approve/reject
     * @param {string} action - 'approve' or 'reject'
     * @param {number} expiryHours - Hours until token expires (default: 24)
     * @returns {string} - Secure token
     */
    generateToken(uid, action, expiryHours = 24) {
        // Create a unique token
        const token = crypto.randomBytes(32).toString('hex');

        // Store token with metadata
        const expiresAt = Date.now() + (expiryHours * 60 * 60 * 1000);
        this.tokens.set(token, {
            uid,
            action,
            expiresAt,
            createdAt: Date.now()
        });

        return token;
    }

    /**
     * Verify and consume a token
     * @param {string} token - Token to verify
     * @returns {Object|null} - Token data if valid, null otherwise
     */
    verifyToken(token) {
        const data = this.tokens.get(token);

        if (!data) {
            return null; // Token doesn't exist
        }

        if (Date.now() > data.expiresAt) {
            this.tokens.delete(token); // Clean up expired token
            return null; // Token expired
        }

        // Token is valid - consume it (one-time use)
        this.tokens.delete(token);
        return data;
    }

    /**
     * Clean up expired tokens
     */
    cleanupExpiredTokens() {
        const now = Date.now();
        let cleaned = 0;

        for (const [token, data] of this.tokens.entries()) {
            if (now > data.expiresAt) {
                this.tokens.delete(token);
                cleaned++;
            }
        }

        if (cleaned > 0) {
            console.log(`[TokenService] Cleaned up ${cleaned} expired tokens`);
        }
    }

    /**
     * Get token statistics
     */
    getStats() {
        return {
            totalTokens: this.tokens.size,
            tokens: Array.from(this.tokens.entries()).map(([token, data]) => ({
                token: token.substring(0, 8) + '...', // Partial token for security
                uid: data.uid,
                action: data.action,
                expiresIn: Math.floor((data.expiresAt - Date.now()) / 1000 / 60) + ' minutes'
            }))
        };
    }
}

module.exports = new TokenService();
