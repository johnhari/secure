# BIG SHOT ORDERFLOW - macOS & iOS Build and Deployment Guide

This guide explains how to build, run, and package the **BIG SHOT Orderflow** app for **macOS Desktop** and **iOS (iPhone & iPad)** with 100% full feature parity.

---

## 🚀 Overview of Supported Features on macOS & iOS

| Feature | macOS Desktop | iOS (iPhone / iPad) | Windows / Android Parity |
| :--- | :---: | :---: | :---: |
| **Live Orderflow Candlestick Charts** | ✅ Full Desktop View | ✅ Mobile Optimized View | 100% Identical |
| **Real-Time Volume & Activity Alerts** | ✅ Native Desktop Alerts | ✅ Push & Local Alerts | 100% Identical |
| **Voice Search / Quantum Radar** | ✅ Microphone & Speech | ✅ Microphone & Speech | 100% Identical |
| **Multi-Timeframe & Historical Replay** | ✅ Supported | ✅ Supported | 100% Identical |
| **Single-Device Session / HWID Lock** | ✅ Persistent System GUID | ✅ Vendor Identifier | 100% Identical |
| **Firebase Realtime DB & Firestore** | ✅ Connected | ✅ Connected | 100% Identical |
| **Admin Superuser Terminal** | ✅ Supported | ✅ Supported | 100% Identical |

---

## 🍏 1. Building for macOS Desktop (.DMG / .APP)

### Option A: Local Mac Machine

1. Open Terminal and navigate to the project directory:
   ```bash
   cd orderflow
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the macOS application directly:
   ```bash
   flutter run -d macos
   ```
4. Build the Release Application and `.dmg` installer:
   ```bash
   bash make_dmg.sh
   ```
   *Output file will be created at:* `orderflow/build/macos/dmg/Orderflow-Installer.dmg`

---

## 📱 2. Building for iOS (.IPA / TestFlight / Direct Install)

### Option A: Local Mac Machine

1. Ensure Xcode and CocoaPods are installed.
2. Navigate to the iOS folder and install CocoaPods dependencies:
   ```bash
   cd orderflow/ios
   pod install
   cd ..
   ```
3. Run on iOS Simulator or connected iPhone:
   ```bash
   flutter run -d ios
   ```
4. Build the Release IPA:
   ```bash
   bash build_ios.sh
   # Or directly:
   flutter build ipa --release
   ```
   *Output archive will be created at:* `orderflow/build/ios/ipa/*.ipa`

---

## ☁️ 3. Automated Cloud Builds (No Mac Required)

### Option A: GitHub Actions (Direct 1-Click Cloud Build)
This repository includes ready-to-run GitHub Actions workflows:
- **macOS DMG**: [build_macos_dmg.yml](file:///.github/workflows/build_macos_dmg.yml) builds `Orderflow-Installer.dmg`
- **iOS IPA**: [build_ios.yml](file:///.github/workflows/build_ios.yml) builds `Orderflow-iOS-Release.ipa`

**How to run:**
1. Push code to your GitHub repository:
   ```bash
   git push origin main
   ```
2. Go to **Actions** tab in your GitHub repository.
3. Select **"Build macOS DMG Installer"** or **"Build iOS IPA & Archive"** and click **Run workflow**.
4. Once finished, download the build artifacts (`.dmg` or `.ipa`) directly from GitHub!

### Option B: Codemagic CI/CD
The included [codemagic.yaml](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/codemagic.yaml) provides automated pipelines:
- **`ios-release`**: Builds signed `.ipa` and submits to TestFlight or creates direct installer.
- **`macos-release`**: Builds `.app` and packages `.dmg` for macOS desktop.
- **`android-release`**: Builds `.apk` and `.aab` for Android.

---

## 🛡️ Native Permissions Configured
- **macOS Entitlements:** Client network (`com.apple.security.network.client`), User file storage (`com.apple.security.files.user-selected.read-write`), Audio input (`com.apple.security.device.audio-input`).
- **iOS Info.plist:** Speech recognition (`NSSpeechRecognitionUsageDescription`), Microphone (`NSMicrophoneUsageDescription`), Photo library access (`NSPhotoLibraryUsageDescription`), Camera (`NSCameraUsageDescription`), Background fetch (`UIBackgroundModes`).
