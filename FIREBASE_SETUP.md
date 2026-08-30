# Firebase Setup Guide for Orderflow

## Overview

Your Firebase project: **mst7-3fb55**

This guide will help you enable and configure all required Firebase services.

---

## Step 1: Install Firebase CLI (if not already installed)

```bash
npm install -g firebase-tools
```

**Verify installation:**
```bash
firebase --version
```

---

## Step 2: Login to Firebase

```bash
firebase login
```

This will open a browser window for authentication.

---

## Step 3: Initialize Firebase in Project (Already Done)

The project is already initialized with:
- `.firebaserc` - Project configuration
- `firebase.json` - Service configurations
- `firestore.rules` - Firestore security rules
- `database.rules.json` - Realtime Database rules

---

## Step 4: Enable Required Firebase Services

### Via Firebase Console (https://console.firebase.google.com)

#### A. Enable Authentication

1. Go to Firebase Console → Your Project (mst7-3fb55)
2. Click **Authentication** in left sidebar
3. Click **Get Started**
4. Go to **Sign-in method** tab
5. Enable **Phone** provider:
   - Click on "Phone"
   - Toggle "Enable"
   - Click "Save"

**Test Phone Numbers (Optional for Development):**
- You can add test phone numbers in Phone authentication settings
- Example: +91 1234567890 → OTP: 123456

#### B. Enable Firestore Database

1. Click **Firestore Database** in left sidebar
2. Click **Create database**
3. Select **Start in production mode** (we have custom rules)
4. Choose location: **asia-south1** (Mumbai) or closest to you
5. Click "Enable"

#### C. Enable Realtime Database

1. Click **Realtime Database** in left sidebar
2. Click **Create database**
3. Choose location: **asia-southeast1** or same as Firestore
4. Select **Start in locked mode** (we have custom rules)
5. Click "Enable"

---

## Step 5: Deploy Security Rules

From the `ADVANCEORDERFLOW` directory:

### Deploy All Rules
```bash
firebase deploy
```

### Deploy Only Firestore Rules
```bash
firebase deploy --only firestore:rules
```

### Deploy Only Realtime Database Rules
```bash
firebase deploy --only database
```

**Expected Output:**
```
✔  Deploy complete!

Project Console: https://console.firebase.google.com/project/mst7-3fb55/overview
```

---

## Step 6: Download Service Account Key (for Backend)

1. Go to Firebase Console → Project Settings (⚙️ icon)
2. Click **Service accounts** tab
3. Click **Generate new private key**
4. Click **Generate key**
5. Save the downloaded JSON file as:
   ```
   backend/serviceAccountKey.json
   ```

**⚠️ IMPORTANT:** Never commit this file to Git (already in .gitignore)

---

## Step 7: Create Admin User

After deploying rules and running the app for the first time:

1. Login with your phone number in the app
2. Go to Firebase Console → Firestore Database
3. Find the auto-created user document in `users` collection
4. Edit the document and change `role` field:
   ```
   role: "admin"
   ```
5. Save the document
6. Restart the Flutter app to see the Admin Panel

---

## Step 8: Verify Configuration

### Check Firestore Rules
```bash
firebase firestore:rules get
```

### Check Realtime Database Rules
```bash
firebase database:get /
```

### Test Authentication
1. Run the Flutter app
2. Enter phone number
3. Receive OTP
4. Login successfully

---

## Quick Reference: Firebase Services URLs

- **Console:** https://console.firebase.google.com/project/mst7-3fb55
- **Authentication:** https://console.firebase.google.com/project/mst7-3fb55/authentication
- **Firestore:** https://console.firebase.google.com/project/mst7-3fb55/firestore
- **Realtime Database:** https://console.firebase.google.com/project/mst7-3fb55/database
- **Project Settings:** https://console.firebase.google.com/project/mst7-3fb55/settings/general

---

## Troubleshooting

### Issue: "Permission denied" when deploying rules
**Solution:** Make sure you're logged in with correct account
```bash
firebase logout
firebase login
```

### Issue: "Firestore database not created"
**Solution:** Create database first via Firebase Console (Step 4B)

### Issue: "Service account key doesn't work"
**Solution:** 
- Make sure file path in `.env` is correct
- File should be named `serviceAccountKey.json`
- Check JSON format is valid

### Issue: "Phone authentication not working"
**Solution:**
- Verify Phone provider is enabled in Firebase Console
- Check SHA-1 fingerprint is added (for Android)
- For testing, add test phone numbers

---

## Security Checklist

- [x] Firestore rules deployed (role-based access)
- [x] Realtime Database rules deployed (session control)
- [ ] Service account key downloaded and placed in backend/
- [ ] Phone authentication enabled
- [ ] Admin user created in Firestore
- [ ] Test phone numbers added (optional, for dev)

---

## Next Steps After Firebase Setup

1. ✅ Download service account key → `backend/serviceAccountKey.json`
2. ✅ Complete `backend/.env` with m.Stock credentials
3. ✅ Run backend: `cd backend && npm install && npm start`
4. ✅ Run Flutter: `cd orderflow && flutter pub get && flutter run`
5. ✅ Login with phone OTP
6. ✅ Make yourself admin in Firestore
7. ✅ Test admin panel functionality

---

## Firebase CLI Cheat Sheet

```bash
# Login
firebase login

# List projects
firebase projects:list

# Deploy everything
firebase deploy

# Deploy only Firestore
firebase deploy --only firestore

# Deploy only Database
firebase deploy --only database

# View logs
firebase functions:log

# Open console
firebase open
```
