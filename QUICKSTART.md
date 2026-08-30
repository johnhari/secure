# 🚀 Quick Start Guide

## Firebase Setup (5 minutes)

### Option 1: Automated Setup (Recommended)
Double-click: **`setup-firebase.bat`**

This will:
- ✅ Login to Firebase (if needed)
- ✅ Deploy Firestore rules
- ✅ Deploy Realtime Database rules

### Option 2: Manual Setup
```bash
# Install Firebase CLI (if not installed)
npm install -g firebase-tools

# Login
firebase login

# Deploy rules
firebase deploy
```

---

## Enable Firebase Services in Console

🔗 **Firebase Console:** https://console.firebase.google.com/project/mst7-3fb55

### 1. Enable Phone Authentication (2 min)
1. Go to **Authentication** → **Sign-in method**
2. Enable **Phone** provider
3. Click Save

### 2. Create Firestore Database (1 min)
1. Go to **Firestore Database**
2. Click **Create database**
3. Choose **Production mode**
4. Select location: **asia-south1** (Mumbai)

### 3. Create Realtime Database (1 min)
1. Go to **Realtime Database**
2. Click **Create database**
3. Choose **Locked mode**
4. Select same location

### 4. Download Service Account Key (1 min)
1. Go to **Project Settings** (⚙️) → **Service accounts**
2. Click **Generate new private key**
3. Save as: `backend/serviceAccountKey.json`

---

## Backend Setup

```bash
cd backend

# Install dependencies
npm install

# Configure .env file with:
# - m.Stock credentials (app code, user ID, password)
# - TOTP secret is already set

# Run backend
npm start
```

**Backend should now be running on:** http://localhost:3000

---

## Flutter App Setup

```bash
cd orderflow

# Install dependencies
flutter pub get

# Run on Android emulator
flutter run

# Build APK
flutter build apk --release
```

---

## First Login & Admin Setup

1. **Launch the app** → Enter your phone number
2. **Receive OTP** → Enter code → Login
3. **Go to Firebase Console** → **Firestore Database** → `users` collection
4. **Find your user** → Edit → Change `role` to `"admin"`
5. **Restart app** → You'll see the "Admin Panel" FAB

---

## Testing

✅ Login with phone OTP
✅ Chart displays (once backend is connected to m.Stock)
✅ Switch between NIFTY50/BANKNIFTY
✅ Admin panel accessible
✅ Save orderflow data
✅ Data appears on chart

---

## Troubleshooting

**Backend won't start?**
- Check `.env` has all m.Stock credentials
- Verify `serviceAccountKey.json` exists

**Flutter build errors?**
- Run: `flutter clean && flutter pub get`
- Check `google-services.json` is in `android/app/`

**Can't login?**
- Verify Phone auth is enabled in Firebase Console
- Check internet connection

**WebSocket connection fails?**
- Backend must be running first
- For physical device, update IP in `app_constants.dart`

---

## Quick Reference

| Service | URL |
|---------|-----|
| Firebase Console | https://console.firebase.google.com/project/mst7-3fb55 |
| Backend API | http://localhost:3000 |
| WebSocket | ws://localhost:3000/stream |

---

## Full Documentation

- **Complete Setup:** `FIREBASE_SETUP.md`
- **API Reference:** `API_EXAMPLES.md`
- **Security:** `SECURITY.md`
- **Project Overview:** `README.md`

---

**Status:** ✅ All Firebase services configured and ready!
