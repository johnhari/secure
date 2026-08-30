@echo off
echo ========================================
echo Firebase Services Setup for Orderflow
echo ========================================
echo.

REM Check if Firebase CLI is installed
where firebase >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Firebase CLI not found!
    echo Please install: npm install -g firebase-tools
    pause
    exit /b 1
)

echo [1/5] Checking Firebase login status...
firebase projects:list >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Not logged in. Opening login...
    firebase login
)

echo.
echo [2/5] Current Firebase project: mst7-3fb55
firebase use mst7-3fb55

echo.
echo [3/5] Deploying Firestore security rules...
firebase deploy --only firestore:rules

echo.
echo [4/5] Deploying Realtime Database security rules...
firebase deploy --only database

echo.
echo [5/5] Deployment complete!
echo.
echo ========================================
echo Next Steps:
echo ========================================
echo 1. Download Service Account Key from Firebase Console
echo 2. Save as backend/serviceAccountKey.json
echo 3. Enable Phone Authentication in Firebase Console
echo 4. Create Firestore and Realtime Database (if not exists)
echo.
echo Firebase Console: https://console.firebase.google.com/project/mst7-3fb55
echo.
pause
