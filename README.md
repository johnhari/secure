# Orderflow - Production-Ready Flutter Application

A production-ready Flutter application for Android that displays live candlestick charts for NIFTY50 and BANKNIFTY with orderflow analysis. Features include real-time m.Stock API integration, Firebase authentication with single-device enforcement, and an admin panel for managing orderflow data.

## Features

### End User Features
- ✅ Phone OTP-based login (Firebase Authentication)
- ✅ Real-time candlestick charts for NIFTY50 and BANKNIFTY
- ✅ 5-minute timeframe candles
- ✅ Live orderflow data visualization (buyer/seller counts)
- ✅ Dark and light theme support
- ✅ Smooth 60fps chart performance with zoom/pan
- ✅ Automatic WebSocket reconnection
- ✅ Offline caching with Hive

### Admin Features
- ✅ Admin panel for entering buyer/seller counts
- ✅ Role-based access control
- ✅ Orderflow data persistence until market close
- ✅ Easy candle selection interface

### Security Features
- ✅ **Single-device enforcement** (one user per device, GPay-style)
- ✅ Secure backend with Firebase token verification
- ✅ No API keys embedded in APK
- ✅ Rate limiting and abuse protection
- ✅ Firestore and Realtime Database security rules

## Architecture

### Backend (Node.js)
```
backend/
├── server.js                  # Main entry point
├── middleware/
│   └── auth.middleware.js     # Firebase token verification
├── services/
│   ├── mstock.service.js      # m.Stock API integration
│   ├── candle.aggregator.js   # Tick to OHLC converter
│   └── orderflow.service.js   # Orderflow data management
├── routes/
│   └── admin.routes.js        # Admin REST endpoints
└── websocket/
    └── stream.handler.js      # WebSocket streaming logic
```

### Flutter App (Clean Architecture)
```
orderflow/
├── lib/
│   ├── core/
│   │   ├── constants/         # App constants
│   │   ├── theme/             # Dark/light themes
│   │   └── utils/             # Device utilities
│   ├── data/
│   │   ├── datasources/       # WebSocket, HTTP, local cache
│   │   ├── models/            # Data models
│   │   └── repositories/      # Repository implementations
│   ├── domain/
│   │   └── entities/          # Domain entities
│   └── presentation/
│       ├── providers/         # Riverpod state management
│       ├── screens/           # UI screens
│       └── widgets/           # Reusable widgets
└── android/
    └── app/
        ├── build.gradle       # Android configuration
        └── google-services.json
```

## Prerequisites

### Backend
- Node.js 18 or higher
- Firebase project with Firestore and Realtime Database
- m.Stock API credentials

### Flutter
- Flutter SDK 3.0 or higher
- Android SDK (API 23+)
- Android Studio or VS Code

## Setup Instructions

### 1. Backend Setup

#### Install Dependencies
```bash
cd backend
npm install
```

#### Configure Environment Variables
Copy `.env.example` to `.env` and fill in your credentials:

```env
PORT=3000
NODE_ENV=development

# Firebase
FIREBASE_SERVICE_ACCOUNT_PATH=./serviceAccountKey.json

# m.Stock API
MSTOCK_APP_CODE=your_app_code
MSTOCK_USER_ID=your_user_id
MSTOCK_PASSWORD=your_password
MSTOCK_TOTP_SECRET=your_totp_secret

# Market Configuration
MARKET_OPEN_TIME=09:15
MARKET_CLOSE_TIME=15:40
TIMEZONE=Asia/Kolkata
```

#### Download Firebase Service Account Key
1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate New Private Key"
3. Save as `serviceAccountKey.json` in the `backend` folder

#### Run Backend
```bash
npm start
```

For development with auto-reload:
```bash
npm run dev
```

Backend will run on `http://localhost:3000`

### 2. Flutter App Setup

#### Install Dependencies
```bash
cd orderflow
flutter pub get
```

#### Configure Backend URL
For **Android Emulator**, the default URLs in `app_constants.dart` work:
```dart
static const String backendUrl = 'http://10.0.2.2:3000';
static const String wsUrl = 'ws://10.0.2.2:3000/stream';
```

For **Physical Device**, update to your computer's IP:
```dart
static const String backendUrl = 'http://192.168.1.x:3000';
static const String wsUrl = 'ws://192.168.1.x:3000/stream';
```

#### Run on Android Emulator
```bash
flutter run
```

#### Build Release APK
```bash
flutter build apk --release
```

APK will be generated at: `build/app/outputs/flutter-apk/app-release.apk`

## Firebase Configuration

### Enable Authentication
1. Go to Firebase Console → Authentication
2. Enable Phone provider
3. Follow phone authentication setup

### Deploy Security Rules

#### Firestore Rules
```bash
firebase deploy --only firestore:rules
```

#### Realtime Database Rules
```bash
firebase deploy --only database
```

Or manually copy from `firestore.rules` and `database.rules.json`

### Create Admin User
In Firestore, manually create a user document:

```
Collection: users
Document ID: <user_uid>
Fields:
  - uid: <user_uid>
  - role: "admin"
  - createdAt: <timestamp>
  - phoneNumber: "+919876543210"
```

## Testing

### Test Backend Locally
```bash
cd backend
npm test
```

### Test Flutter App
```bash
cd orderflow
flutter test
```

### Manual Testing Checklist
- [ ] Login with phone OTP
- [ ] Single-device enforcement (login on two devices)
- [ ] Chart displays with live data
- [ ] Switch between NIFTY50 and BANKNIFTY
- [ ] Admin panel accessible (admin only)
- [ ] Save orderflow data
- [ ] Orderflow data appears on chart
- [ ] WebSocket reconnection works
- [ ] App handles backend downtime gracefully

## Usage

### End User Flow
1. Open app → Enter phone number
2. Receive OTP → Enter OTP
3. View chart → Select instrument (NIFTY50/BANKNIFTY)
4. Chart updates in real-time with 5-minute candles

### Admin Flow
1. Login as admin
2. Tap "Admin Panel" FAB
3. Select a candle from the list
4. Enter buyer count and seller count
5. Tap "Save Orderflow Data"
6. Data appears on chart immediately

## Security Best Practices

### Backend
- ✅ Never commit `.env` file
- ✅ Store m.Stock credentials server-side only
- ✅ Rotate Firebase service account keys regularly
- ✅ Use HTTPS in production
- ✅ Enable CORS only for known origins

### Flutter
- ✅ Never hardcode API keys in code
- ✅ Use ProGuard/R8 for code obfuscation
- ✅ Validate all user inputs
- ✅ Keep Firebase SDKs updated

## Troubleshooting

### Backend Connection Issues
- Check if backend is running: `curl http://localhost:3000/health`
- Verify Firebase credentials are correct
- Check m.Stock API credentials

### Flutter Build Issues
- Run `flutter clean && flutter pub get`
- Verify `google-services.json` is in `android/app/`
- Check Gradle build files for correct versions

### WebSocket Connection Issues
- For emulator: Use `10.0.2.2` instead of `localhost`
- For physical device: Ensure device is on same network as backend
- Check firewall settings

## API Endpoints

### WebSocket
- `ws://localhost:3000/stream?token=<firebase_id_token>`

### REST API (Admin Only)
- `POST /api/admin/orderflow` - Save orderflow data
- `GET /api/admin/orderflow/:candleKey` - Get orderflow for candle
- `GET /api/admin/orderflow?symbol=NIFTY50&date=2025-12-31` - Query orderflow

See `API_EXAMPLES.md` for detailed request/response formats.

## Tech Stack

### Backend
- Node.js + Express
- WebSocket (ws)
- Firebase Admin SDK
- m.Stock API
- Firestore

### Frontend
- Flutter 3.x
- Riverpod (State Management)
- Syncfusion Charts
- Firebase Auth + Realtime Database
- Hive (Local Cache)

## License

MIT License - See LICENSE file for details

## Support

For issues or questions, please create an issue in the GitHub repository.
