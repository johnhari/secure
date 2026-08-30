# Walkthrough - Real-Time Stock Signal Monitor & Index Propagation

I have implemented a live Stock Signal Radar feature, a Nifty index propagation data-injection prompt, and a Profile Subscription Management card with UPI payment integration.

## Changes

### 1. Global Signals Query Stream
- **[orderflow_service.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/domain/services/orderflow_service.dart)**: Added `getGlobalSignalsStream()`, querying active Firestore orderflow documents from the last 48 hours and sorting them chronologically.
- **[providers.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/providers/providers.dart)**: Created the Riverpod `globalSignalsProvider` to listen to the new global stream.

### 2. User Interface Integration
- **[chart_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/chart_screen.dart)**:
  - Added a glowing campaign icon button (`Icons.campaign_rounded`) to the AppBar's action buttons.
  - Implemented `_showSignalsBottomSheet()` which shows a bottom sheet styled with glassmorphism and the cyberpunk theme. It contains a real-time list of all stock signals.
  - Tapping on any signal in the sheet executes haptic feedback, closes the sheet, and seamlessly switches the active chart view to the tapped stock.

### 3. Nifty Index Propagation Prompt
- **[admin_panel_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/admin_panel_screen.dart)**:
  - Modified the standard `_saveOrderflow()` (Form & Ghost Mode) and the quick-fire `_injectQuickSignal()` methods to detect if the selected instrument is `NIFTY50`.
  - Added an interactive confirmation dialog asking: *"Do you also want to inject this data in FINNIFTY, SENSEX, and BANKNIFTY?"*.
  - If approved, it propagates the exact same signal values (volumes, triggers, flags) to all three other indices.
- **[chart_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/chart_screen.dart)**:
  - Added the same confirmation prompt dialog inside the long-press `_saveOrderflow()` injection handler when the active chart is `NIFTY50`.

### 4. Subscription Management & UPI Payments
- **[profile_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/profile_screen.dart)**:
  - Added a new **"Subscription Details"** card showing the user's name, phone number, active subscription balance (days remaining), and exact expiration date.
  - Implemented a **"Pay Next Month Subscription"** action button that triggers a customized bottom sheet with options for **Google Pay**, **PhonePe**, and **Paytm**.
  - Displays a **"Choose Your Plan"** selector featuring:
    - **1 Month Membership**: ₹4,999
    - **3 Month Membership**: ₹9,999 *(Popular)*
    - **6 Month Membership**: ₹19,999
    - **1 Year Membership**: ₹49,999
  - Integrated custom deep link URI schemes (`phonepe://`, `paytmmp://`, `upi://`) to open respective external apps to securely complete payments to UPI ID `online.secure.payment@upi` with the exact selected plan amount.

### 5. Daily Price Change Fix
- **[chart_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/chart_screen.dart)**:
  - Fixed a calculation issue where the price change percentage was relative to the very first historical candle loaded in the cache (from days ago).
  - Implemented daily/session relative calculation that automatically extracts today's first candle and yesterday's close price (if available in the cache) to correctly compute the actual intraday price movement.

### 6. App Icon & Favicon Adjustments
- **Android Adaptive Launcher Icon**:
  - Resized the original logo artwork to fit within Android's **66% safe zone** (preventing cropping and a zoomed-in look on device home screens). Centered it inside a transparent canvas (`logo_padded.png`) and updated [pubspec.yaml](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/pubspec.yaml).
  - Regenerated the native launcher icons dynamically.
- **Web Favicon**:
  - Resized the high-resolution logo to a standard 128x128 PNG to replace the default Flutter `favicon.png` in [web/favicon.png](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/web/favicon.png).

### 7. User Profile Icon & Routing
- **[main.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/main.dart)**: Registered `/profile` route mapping to `ProfileScreen`.
- **[chart_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/chart_screen.dart)**: Added a **User Profile** button (`Icons.person_rounded`) next to the search icon in the AppBar, allowing all users to quickly open their account and subscription options.

### 8. Permanent Access & UPI Package Visibility Fix
- **[profile_screen.dart](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/lib/presentation/screens/profile_screen.dart)**:
  - Resolved a layout bug where users with lifetime access (represented as a `null` `expiryDate` in the database) were displayed as "Expired / No Active Balance".
  - The profile page now correctly displays **"PERMANENT ACCESS"** in green for these accounts, with the Expiry Date marked as **"Permanent / Lifetime"**.
  - Optimized the payment launcher code to directly trigger deep links via a try-catch fallback rather than failing instantly on `canLaunchUrl`.
- **[AndroidManifest.xml](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/orderflow/android/app/src/main/AndroidManifest.xml)**: Declared the required deep-link schemes (`upi`, `phonepe`, `paytmmp`) under the `<queries>` element, enabling package visibility so Android 11+ devices can query and redirect to Google Pay, PhonePe, and Paytm successfully.

---

## Verification Results

### Automated Code Analysis & Build
- `flutter analyze` was executed, confirming the new code compiles cleanly with no syntax errors.
- Compiled a fresh release APK containing all the new features and fixes successfully.

### Output Artifacts
- Deployed APK: [app-release.apk](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/app-release.apk)
- Version 0307 Archive: [app-release_0307.apk](file:///c:/Users/PUTIN/Desktop/ADVANCEORDERFLOW/app-release_0307.apk)


