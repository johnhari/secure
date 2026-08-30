# Security Checklist

## API Key Protection

### ✅ Backend Security
- [x] m.Stock API credentials stored in `.env` file only
- [x] `.env` file added to `.gitignore`
- [x] Firebase service account key stored locally, not committed
- [x] No sensitive credentials in source code

### ✅ Flutter App Security
- [x] No API keys hardcoded in Dart code
- [x] Backend URL configurable in constants file
- [x] Firebase credentials in `google-services.json` (public project ID is acceptable)
- [x] ProGuard enabled for release builds (minifyEnabled: true)

## Authentication & Authorization

### ✅ Firebase Authentication
- [x] Phone OTP authentication implemented
- [x] ID token verification on backend for every request
- [x] Token expiration handled properly
- [x] Single-device enforcement using Realtime Database

### ✅ Role-Based Access Control
- [x] User roles stored in Firestore (not client-side)
- [x] Admin endpoints protected with `verifyAdmin` middleware
- [x] Admin panel UI hidden for non-admin users
- [x] Deep link protection for admin routes
- [x] Firestore security rules enforce role-based writes

## Network Security

### ✅ HTTPS/WSS (Production)
- [ ] Use HTTPS for API endpoints in production
- [ ] Use WSS (secure WebSocket) in production
- [ ] Enable CORS with specific origins only
- [ ] Add SSL certificate pinning (optional, advanced)

### ✅ Rate Limiting
- [x] Express rate limiter configured (100 requests per 15 minutes)
- [x] Rate limit applied to `/api` routes
- [x] WebSocket connection limits (per user)

## Data Security

### ✅ Database Security
- [x] Firestore security rules deployed
- [x] Realtime Database rules deployed
- [x] User can only write to their own session
- [x] Only admins can write orderflow data
- [x] All authenticated users can read candle data

### ✅ Session Management
- [x] Active device ID stored per user
- [x] Session invalidation on new device login
- [x] Last seen timestamp updated periodically
- [x] Session listener auto-logout on invalidation

## Code Security

### ✅ Input Validation
- [x] Phone number validation on login
- [x] OTP code validation
- [x] Buyer/seller count validation (numeric, positive)
- [x] Candle key validation
- [x] SQL injection prevention (using Firestore SDK)

### ✅ Error Handling
- [x] Try-catch blocks in critical sections
- [x] Graceful error messages (no stack traces to client)
- [x] Backend errors logged server-side
- [x] Client errors shown in user-friendly format

## Deployment Security

### ✅ Environment Separation
- [ ] Use separate Firebase projects for dev/staging/production
- [ ] Use separate Firestore databases for different environments
- [ ] Never use production credentials in development

### ✅ Credential Rotation
- [ ] Rotate m.Stock API password every 90 days
- [ ] Rotate TOTP secret if compromised
- [ ] Regenerate Firebase service account key annually
- [ ] Monitor Firebase console for unusual activity

### ✅ APK Security
- [x] Decompile APK and verify no secrets present
- [x] Check for hardcoded URLs or tokens
- [x] Verify ProGuard obfuscation is working
- [ ] Consider using additional APK encryption tools

## Monitoring & Logging

### ✅ Logging
- [x] Backend logs WebSocket connections
- [x] Backend logs authentication attempts
- [x] Backend logs admin actions
- [x] No sensitive data in logs (passwords, tokens)

### ✅ Crash Reporting (Optional)
- [ ] Integrate Firebase Crashlytics
- [ ] Monitor crash reports for security issues
- [ ] Set up alerts for unusual activity

## Compliance & Best Practices

### ✅ Firebase Security Best Practices
- [x] Multi-factor authentication enabled for Firebase Console access
- [x] Security rules regularly reviewed
- [x] Anonymous auth disabled (only phone auth enabled)
- [x] User data export/deletion endpoints (GDPR compliance)

### ✅ Regular Security Audits
- [ ] Review security rules monthly
- [ ] Check for outdated dependencies (`npm audit`, `flutter pub outdated`)
- [ ] Test single-device enforcement regularly
- [ ] Verify admin access controls

## Penetration Testing Checklist

Before production deployment, test:
- [ ] Can a viewer user access admin endpoints?
- [ ] Can a user modify another user's session?
- [ ] Can orderflow data be written without authentication?
- [ ] Can WebSocket connection be hijacked?
- [ ] Can rate limiting be bypassed?
- [ ] Can expired tokens be reused?
- [ ] Can the same user login on multiple devices simultaneously?

## Emergency Response Plan

If credentials are compromised:
1. Immediately rotate affected credentials
2. Revoke all active Firebase sessions
3. Deploy new version with updated credentials
4. Monitor logs for unauthorized access
5. Notify affected users if necessary

## Notes

- Keep this checklist updated as new security measures are added
- Review this checklist before every production deployment
- Assign security responsibility to specific team members
- Schedule regular security training for developers
