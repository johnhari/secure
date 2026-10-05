import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/device_utils.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/notification_service.dart';

/// Custom exceptions for authentication
class AuthException implements Exception {
  final String message;
  final String? code;
  AuthException(this.message, [this.code]);
  
  @override
  String toString() => message;
}

class NetworkException extends AuthException {
  NetworkException([String message = 'Network error. Please check your connection.']) 
      : super(message, 'network_error');
}

class AuthenticationDataSource {
  final firebase_auth.FirebaseAuth? _firebaseAuth;
  final FirebaseDatabase? _database;
  StreamSubscription? _sessionListener;
  StreamSubscription? _forceLogoutListener;
  Timer? _sessionCheckTimer;
  Timer? _tokenRefreshTimer;
  
  /// Admin flag — when true, skip all single-device session enforcement
  /// so admin can be logged in on both Android and Desktop simultaneously.
  bool _isAdmin = false;

  /// Dual-device flag — when true, allows 1 PC and 1 Mobile simultaneously
  bool _allowDualDevice = false;
  
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _tokenRefreshInterval = Duration(minutes: 30);

  String? _lastLoggedInUid;
  String? _lastLoggedInEmail;
  String? _lastIdToken;

  String? get lastLoggedInUid {
    if (_lastLoggedInUid != null) return _lastLoggedInUid;
    final auth = _firebaseAuth;
    if (kIsWeb || auth == null) return null;
    try {
      return auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  String? get lastLoggedInEmail {
    if (_lastLoggedInEmail != null) return _lastLoggedInEmail;
    final auth = _firebaseAuth;
    if (kIsWeb || auth == null) return null;
    try {
      return auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  String? get lastIdToken => _lastIdToken;

  AuthenticationDataSource({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseDatabase? database,
  })  : _firebaseAuth = firebaseAuth ?? (kIsWeb ? null : firebase_auth.FirebaseAuth.instance),
        _database = database ?? (kIsWeb ? null : FirebaseDatabase.instance);

  /// Helper to get current platform key ('windows', 'mobile', 'web')
  String _getPlatformKey() {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'windows';
    return 'mobile';
  }

  /// Set admin flag to bypass single-device session enforcement.
  void setAdminMode(bool isAdmin) {
    _isAdmin = isAdmin;
  }

  /// Set dual-device mode (1 Mobile + 1 PC access).
  void setAllowDualDevice(bool allow) {
    _allowDualDevice = allow;
  }

  /// Check if the user is approved for 1 Mobile + 1 PC (dual device) access
  Future<bool> _isDualDeviceAllowed(String uid) async {
    if (_isAdmin) return true;
    if (_allowDualDevice) return true;

    // 1. Check Firestore user profile
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final isAllowed = data['allowDualDevice'] == true ||
              data['allowDualDevice'] == 'true' ||
              data['allow1Mobile1Pc'] == true ||
              data['allow1Mobile1Pc'] == 'true';
          if (isAllowed) {
            _allowDualDevice = true;
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('Session: _isDualDeviceAllowed firestore check error: $e');
    }

    // 2. Check RTDB session root for allowDualDevice flag or active slot nodes ('pc' or 'mobile')
    try {
      if (_database != null) {
        final snap = await _database!
            .ref('${AppConstants.sessionsPath}/$uid')
            .get()
            .timeout(const Duration(seconds: 4));
        if (snap.exists) {
          final sval = snap.value;
          final sdata = _extractMap(sval);
          if (sdata != null) {
            final isAllowed = sdata['allowDualDevice'] == true ||
                sdata['allowDualDevice'] == 'true' ||
                sdata['allow1Mobile1Pc'] == true ||
                sdata['allow1Mobile1Pc'] == 'true' ||
                sdata.containsKey('pc') ||
                sdata.containsKey('mobile');
            if (isAllowed) {
              _allowDualDevice = true;
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Session: _isDualDeviceAllowed rtdb check error: $e');
    }

    return _allowDualDevice;
  }

  /// Sign in with email and password
  /// Returns a message if logged in on another device (session will be terminated there)
  Future<String?> signInWithEmailAndPassword(String email, String password) async {
    final normalizedEmail = email.toLowerCase().trim();
    final isMasterAdmin = AppConstants.isMasterAdmin(normalizedEmail);
    if (isMasterAdmin) {
      _isAdmin = true;
    }

    if (kIsWeb) {
      return _signInViaRestApi(normalizedEmail, password, isMasterAdmin);
    }

    // Native platforms (Android, iOS, Windows, macOS)
    final auth = _firebaseAuth;
    if (auth == null) {
      throw AuthException('Auth service not initialized');
    }

    try {
      final userCredential = await auth.signInWithEmailAndPassword(
        email: normalizedEmail, 
        password: password,
      );
      final user = userCredential.user;

      if (user != null && !user.emailVerified && !isMasterAdmin) {
        try {
          await user.sendEmailVerification();
        } catch (_) {}
        await auth.signOut();
        throw AuthException('Email not verified. A new verification link has been sent to your email.');
      }

      String? sessionMessage;
      final db = _database;
      if (user != null && !isMasterAdmin && db != null) {
        try {
          final currentDeviceId = await DeviceUtils.getDeviceId();
          final isDual = await _isDualDeviceAllowed(user.uid);
          final slot = DeviceUtils.getDeviceSlot();
          final sessionRef = db.ref('${AppConstants.sessionsPath}/${user.uid}');
          
          final sessionSnapshot = await sessionRef.get().timeout(const Duration(seconds: 4));
          final data = _extractMap(sessionSnapshot.value);
          if (data != null) {
            final bool effectiveDual = isDual ||
                data['allowDualDevice'] == true ||
                data['allowDualDevice'] == 'true' ||
                data['allow1Mobile1Pc'] == true ||
                data['allow1Mobile1Pc'] == 'true' ||
                data.containsKey('pc') ||
                data.containsKey('mobile');

            if (effectiveDual) {
              _allowDualDevice = true;
              // Dual-device (1 Mobile + 1 PC): Check conflicts only on this device slot ('pc' or 'mobile')
              Map<String, dynamic>? slotData;
              if (data[slot] is Map) {
                slotData = _extractMap(data[slot]);
              } else if (data['slot'] == slot) {
                slotData = data;
              }
              if (slotData != null) {
                final activeDeviceId = slotData['activeDeviceId']?.toString();
                final prevDevice = slotData['deviceName']?.toString() ?? slotData['platform']?.toString() ?? 'another ${DeviceUtils.getDeviceTypeName()}';
                if (activeDeviceId != null && activeDeviceId != currentDeviceId) {
                  sessionMessage = 'DUPLICATE_SESSION_OVERWRITE:$prevDevice';
                }
              }
            } else {
              String? activeDeviceId;
              String? prevDevice;
              if (data['activeDeviceId'] != null) {
                activeDeviceId = data['activeDeviceId']?.toString();
                prevDevice = data['deviceName']?.toString() ?? data['platform']?.toString() ?? 'another device';
              } else if (data['pc'] is Map) {
                final p = _extractMap(data['pc']);
                activeDeviceId = p?['activeDeviceId']?.toString();
                prevDevice = p?['deviceName']?.toString() ?? 'PC';
              } else if (data['mobile'] is Map) {
                final m = _extractMap(data['mobile']);
                activeDeviceId = m?['activeDeviceId']?.toString();
                prevDevice = m?['deviceName']?.toString() ?? 'Mobile';
              }

              if (activeDeviceId != null && activeDeviceId != currentDeviceId) {
                sessionMessage = 'DUPLICATE_SESSION_OVERWRITE:$prevDevice';
              }
            }
          }
        } catch (e) {
          print('Session check non-critical error: $e');
        }

        try {
          await _registerDeviceSession();
        } catch (e) {
          print('_registerDeviceSession non-critical error: $e');
        }

        try {
          NotificationService.saveTokenToFirestore().catchError((_) => null);
        } catch (_) {}
      }

      return sessionMessage;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Web: Direct REST API sign-in to eliminate dart2js JS interop TypeErrors
  Future<String?> _signInViaRestApi(String email, String password, bool isMasterAdmin) async {
    debugPrint('SIGN IN REST: Authenticating $email via REST API...');
    final url = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_firebaseApiKey',
    );
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      final msg = body['error']?['message']?.toString() ?? 'INVALID_LOGIN_CREDENTIALS';
      final upper = msg.toUpperCase();
      debugPrint('SIGN IN REST error: $msg');
      if (upper.contains('EMAIL_NOT_FOUND')) {
        throw AuthException('No account found with this email.', 'user-not-found');
      }
      if (upper.contains('INVALID_PASSWORD') || upper.contains('INVALID_LOGIN_CREDENTIALS')) {
        throw AuthException('Incorrect password. Please try again.', 'wrong-password');
      }
      if (upper.contains('USER_DISABLED')) {
        throw AuthException('This account has been disabled by an administrator.', 'user-disabled');
      }
      if (upper.contains('TOO_MANY_ATTEMPTS')) {
        throw AuthException('Too many failed attempts. Please try again later.', 'too-many-requests');
      }
      throw AuthException('Invalid email or password. Please verify credentials.', 'invalid-credential');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final uid = data['localId']?.toString();
    final idToken = data['idToken']?.toString();
    final emailVerified = data['emailVerified'] == true || data['email_verified'] == true;

    if (uid == null || idToken == null) {
      throw AuthException('Authentication failed. No user ID returned.', 'no-uid');
    }

    _lastLoggedInUid = uid;
    _lastLoggedInEmail = email;
    _lastIdToken = idToken;

    debugPrint('SIGN IN REST: Authentication successful for uid: $uid');

    // Attempt to sync JS SDK in background (ignore any TypeError)
    final auth = _firebaseAuth;
    if (auth != null) {
      try {
        auth.signInWithEmailAndPassword(email: email, password: password).then((_) {}, onError: (_) {});
      } catch (_) {}
    }

    String? sessionMessage;
    if (_database != null && !isMasterAdmin) {
      try {
        final currentDeviceId = await DeviceUtils.getDeviceId();
        final isDual = await _isDualDeviceAllowed(uid);
        final slot = DeviceUtils.getDeviceSlot();
        final sessionRef = _database!.ref('${AppConstants.sessionsPath}/$uid');
        
        final sessionSnapshot = await sessionRef.get().timeout(const Duration(seconds: 4));
        final sdata = _extractMap(sessionSnapshot.value);
        if (sdata != null) {
          final bool effectiveDual = isDual ||
              sdata['allowDualDevice'] == true ||
              sdata['allowDualDevice'] == 'true' ||
              sdata['allow1Mobile1Pc'] == true ||
              sdata['allow1Mobile1Pc'] == 'true' ||
              sdata.containsKey('pc') ||
              sdata.containsKey('mobile');

          if (effectiveDual) {
            _allowDualDevice = true;
            Map<String, dynamic>? slotData;
            if (sdata[slot] is Map) {
              slotData = _extractMap(sdata[slot]);
            } else if (sdata['slot'] == slot) {
              slotData = sdata;
            }
            if (slotData != null) {
              final activeDeviceId = slotData['activeDeviceId']?.toString();
              final prevDevice = slotData['deviceName']?.toString() ?? slotData['platform']?.toString() ?? 'another ${DeviceUtils.getDeviceTypeName()}';
              if (activeDeviceId != null && activeDeviceId != currentDeviceId) {
                sessionMessage = 'DUPLICATE_SESSION_OVERWRITE:$prevDevice';
              }
            }
          } else {
            String? activeDeviceId;
            String? prevDevice;
            if (sdata['activeDeviceId'] != null) {
              activeDeviceId = sdata['activeDeviceId']?.toString();
              prevDevice = sdata['deviceName']?.toString() ?? sdata['platform']?.toString() ?? 'another device';
            } else if (sdata['pc'] is Map) {
              final p = _extractMap(sdata['pc']);
              activeDeviceId = p?['activeDeviceId']?.toString();
              prevDevice = p?['deviceName']?.toString() ?? 'PC';
            } else if (sdata['mobile'] is Map) {
              final m = _extractMap(sdata['mobile']);
              activeDeviceId = m?['activeDeviceId']?.toString();
              prevDevice = m?['deviceName']?.toString() ?? 'Mobile';
            }

            if (activeDeviceId != null && activeDeviceId != currentDeviceId) {
              sessionMessage = 'DUPLICATE_SESSION_OVERWRITE:$prevDevice';
            }
          }
        }
      } catch (e) {
        print('Session check non-critical error: $e');
      }

      try {
        await _registerDeviceSession();
      } catch (e) {
        print('_registerDeviceSession non-critical error: $e');
      }
    }

    return sessionMessage;
  }

  /// Web helper: verify login credentials via Firebase REST API
  Future<Map<String, dynamic>?> _verifyCredentialsViaRest(String email, String password) async {
    try {
      final url = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_firebaseApiKey',
      );
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        final msg = body['error']?['message']?.toString() ?? 'INVALID_LOGIN_CREDENTIALS';
        final upper = msg.toUpperCase();
        if (upper.contains('EMAIL_NOT_FOUND')) {
          throw AuthException('No account found with this email.', 'user-not-found');
        }
        if (upper.contains('INVALID_PASSWORD') || upper.contains('INVALID_LOGIN_CREDENTIALS')) {
          throw AuthException('Incorrect password. Please try again.', 'wrong-password');
        }
        if (upper.contains('USER_DISABLED')) {
          throw AuthException('This account has been disabled by an administrator.', 'user-disabled');
        }
        if (upper.contains('TOO_MANY_ATTEMPTS')) {
          throw AuthException('Too many failed attempts. Please try again later.', 'too-many-requests');
        }
        throw AuthException('Invalid email or password. Please verify credentials.', 'invalid-credential');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _lastLoggedInUid = data['localId']?.toString();
      _lastLoggedInEmail = data['email']?.toString();
      _lastIdToken = data['idToken']?.toString();
      return data;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Invalid email or password. Please verify credentials.', 'invalid-credential');
    }
  }

  /// Firebase Web API Key for REST API calls
  static const String _firebaseApiKey = 'AIzaSyB1_n0v8ug6tRgAOJCGtZL81QaURyaM7GE';

  /// Register with email and password (sends verification email, saves profile to Firestore)
  /// On web, uses Firebase REST API directly to avoid dart2js JS interop TypeErrors.
  Future<bool> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();

    if (kIsWeb) {
      return _registerViaRestApi(
        email: normalizedEmail,
        password: password,
        name: name,
        phoneNumber: phoneNumber,
      );
    }

    // Native (Android/iOS/Desktop) — use the Firebase Auth plugin directly
    final auth = _firebaseAuth;
    if (auth == null) {
      throw AuthException('Auth service not initialized');
    }
    try {
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user != null) {
        try { await user.updateDisplayName(name.trim()); } catch (e) {
          debugPrint('Warning: updateDisplayName failed: $e');
        }
        await _saveUserProfile(user.uid, normalizedEmail, name, phoneNumber);
        try { await user.sendEmailVerification(); } catch (evErr) {
          debugPrint('Warning: sendEmailVerification failed: $evErr');
        }
        try { await auth.signOut(); } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e, isRegistration: true);
    }
  }

  /// Web: Direct Firebase Auth REST API Registration
  /// Bypasses the Flutter Web JS SDK plugin completely to eliminate minification TypeErrors
  Future<bool> _registerViaRestApi({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
  }) async {
    debugPrint('REGISTER REST: Starting direct REST registration for $email...');
    try {
      // Step 1: Create Account via Identity Toolkit REST API
      final signUpUrl = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey',
      );
      final signUpResp = await http.post(
        signUpUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (signUpResp.statusCode != 200) {
        final errBody = jsonDecode(signUpResp.body);
        final errMsg = errBody['error']?['message']?.toString() ?? 'Registration failed';
        debugPrint('REGISTER REST error: $errMsg');
        throw _mapRestApiError(errMsg);
      }

      final signUpData = jsonDecode(signUpResp.body) as Map<String, dynamic>;
      final uid = signUpData['localId']?.toString();
      final idToken = signUpData['idToken']?.toString();

      if (uid == null || idToken == null) {
        throw AuthException('Failed to create account. Please try again.');
      }
      debugPrint('REGISTER REST: User created with UID: $uid');

      // Step 2: Update Display Name via Identity Toolkit REST API
      try {
        final updateUrl = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:update?key=$_firebaseApiKey',
        );
        await http.post(
          updateUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'idToken': idToken,
            'displayName': name,
            'returnSecureToken': false,
          }),
        );
      } catch (updateErr) {
        debugPrint('Warning: REST update displayName failed: $updateErr');
      }

      // Step 3: Save User Profile in Firestore
      await _saveUserProfile(uid, email, name, phoneNumber);

      // Step 4: Send Verification Email via Identity Toolkit REST API
      try {
        final verifyUrl = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$_firebaseApiKey',
        );
        final verifyResp = await http.post(
          verifyUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'requestType': 'VERIFY_EMAIL',
            'idToken': idToken,
          }),
        );
        debugPrint('REGISTER REST: Verification email sent (status: ${verifyResp.statusCode})');
      } catch (evErr) {
        debugPrint('Warning: REST sendEmailVerification failed: $evErr');
      }

      // Step 5: Sign out (clear any local auth state)
      final localAuth = _firebaseAuth;
      if (localAuth != null) {
        try { await localAuth.signOut(); } catch (_) {}
      }

      return true;
    } catch (e) {
      if (e is AuthException) rethrow;
      if (e is NetworkException) rethrow;
      throw _mapFirebaseAuthError(e, isRegistration: true);
    }
  }

  /// Map Firebase REST API error messages to AuthException
  AuthException _mapRestApiError(String errorMessage) {
    final upper = errorMessage.toUpperCase();
    if (upper.contains('EMAIL_EXISTS') || upper.contains('ALREADY')) {
      return AuthException(
        'Verification link already sent to your mail ID. Please check your inbox (and spam folder) to verify your account, or log in.',
        'email-already-in-use',
      );
    }
    if (upper.contains('INVALID_EMAIL')) {
      return AuthException('Please enter a valid email address.', 'invalid-email');
    }
    if (upper.contains('WEAK_PASSWORD') || upper.contains('TOO_SHORT')) {
      return AuthException('Password is too weak. Please use at least 6 characters.', 'weak-password');
    }
    if (upper.contains('OPERATION_NOT_ALLOWED')) {
      return AuthException('Email/Password registration is not enabled.', 'operation-not-allowed');
    }
    if (upper.contains('TOO_MANY_ATTEMPTS')) {
      return AuthException('Too many failed attempts. Please try again later.', 'too-many-requests');
    }
    return AuthException('Registration failed: $errorMessage', 'unknown');
  }

  /// Save user profile to Firestore (used by both REST and plugin paths)
  Future<void> _saveUserProfile(String uid, String email, String name, String phoneNumber) async {
    try {
      String devName = 'Web Browser';
      String devDetails = 'Web Platform';
      try {
        devName = await DeviceUtils.getDeviceName();
        devDetails = await DeviceUtils.getDeviceDetails();
      } catch (dErr) {
        debugPrint('Warning: DeviceUtils failed on platform ($dErr)');
      }

      final firestore = FirebaseFirestore.instance;
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name.trim(),
        'email': email,
        'phoneNumber': phoneNumber.trim(),
        'role': 'viewer',
        'isApproved': false,
        'createdAt': DateTime.now().toIso8601String(),
        'registeredDeviceName': devName,
        'registeredDeviceDetails': devDetails,
      }, SetOptions(merge: true));
      debugPrint('REGISTER: Firestore profile saved for $email');
    } catch (fErr) {
      debugPrint('Warning: Firestore user profile set failed ($fErr)');
    }
  }

  /// Update user display name in Firebase Auth
  Future<void> updateProfile(String name) async {
    final auth = _firebaseAuth;
    if (auth == null) return;
    try {
      final user = auth.currentUser;
      if (user != null) {
        await user.updateDisplayName(name.trim());
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Resend verification email
  Future<void> resendVerificationEmail() async {
    final auth = _firebaseAuth;
    if (auth == null) return;
    final user = auth.currentUser;
    if (user != null && !user.emailVerified) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('sendVerificationEmail');
        await callable.call({'email': user.email});
        print('Branded email verification resent via Cloud Function');
      } catch (_) {
        try {
          final actionCodeSettings = firebase_auth.ActionCodeSettings(
            url: 'https://orderflowterminal.web.app/terminal/index.html#/login?verified=true',
            handleCodeInApp: true,
            androidPackageName: 'com.bigshot.orderflow',
            androidInstallApp: true,
            androidMinimumVersion: '1',
          );
          await user.sendEmailVerification(actionCodeSettings);
        } catch (_) {
          await user.sendEmailVerification();
        }
      }
    }
  }

  /// Send password reset email (only if email is registered)
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      final auth = _firebaseAuth;
      if (auth != null) {
        await auth.sendPasswordResetEmail(email: normalizedEmail);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Register device session (Strict single-device enforcement across ALL platforms: Mobile, iPhone, Mac, Windows, Web)
  /// If dual-device (1 Mobile + 1 PC) is approved, manages sessions per device slot ('pc' or 'mobile').
  /// Admin users skip session overwrite so they can manage on multiple devices.
  Future<void> _registerDeviceSession([DataSnapshot? existingSessionSnapshot]) async {
    try {
      final uid = lastLoggedInUid;
      if (uid == null || _database == null) return;

      final deviceId = await DeviceUtils.getDeviceId();
      final deviceName = await DeviceUtils.getDeviceName();
      final deviceDetails = await DeviceUtils.getDeviceDetails();
      final platformKey = _getPlatformKey();
      final slot = DeviceUtils.getDeviceSlot();
      final isDual = await _isDualDeviceAllowed(uid);
      _allowDualDevice = isDual;
      
      String sessionId;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        sessionId = const Uuid().v4();
        await prefs.setString('web_session_id', sessionId);
      } else {
        sessionId = const Uuid().v4();
      }
      _currentSessionId = sessionId;
      _currentRollingToken = sessionId;

      final sessionRef = _database!.ref('${AppConstants.sessionsPath}/$uid');
      
      if (_isAdmin) {
        try {
          await sessionRef.child('lastSeen').set(ServerValue.timestamp);
        } catch (_) {}
        _startForceLogoutListener(uid);
      } else if (isDual) {
        final sessionPayload = {
          'activeDeviceId': deviceId,
          'sessionId': sessionId,
          'deviceName': deviceName,
          'deviceDetails': deviceDetails,
          'platform': platformKey,
          'slot': slot,
          'rollingToken': sessionId,
          'rollingTokenIssuedAt': ServerValue.timestamp,
          'forceLogout': false,
          'lastSeen': ServerValue.timestamp,
          'createdAt': ServerValue.timestamp,
        };

        // Write directly to user's dedicated slot node ('pc' or 'mobile')
        await sessionRef.child(slot).set(sessionPayload);
        await sessionRef.update({
          'allowDualDevice': true,
          'allow1Mobile1Pc': true,
          'forceLogout': false,
        });

        // Remove any old legacy flat root keys
        sessionRef.child('activeDeviceId').remove().catchError((_) => null);
        sessionRef.child('sessionId').remove().catchError((_) => null);

        await startSessionListener(sessionId: sessionId, slot: slot);
        _startRollingTokenRefresh(uid, sessionId, slot: slot);
        _startForceLogoutListener(uid);
      } else {
        // Double check if RTDB already has dual access flag or child slots before overwriting root
        bool rtdbHasDual = false;
        try {
          final snap = await sessionRef.get().timeout(const Duration(seconds: 3));
          if (snap.exists) {
            final sdata = _extractMap(snap.value);
            if (sdata != null) {
              rtdbHasDual = sdata['allowDualDevice'] == true ||
                  sdata['allowDualDevice'] == 'true' ||
                  sdata['allow1Mobile1Pc'] == true ||
                  sdata['allow1Mobile1Pc'] == 'true' ||
                  sdata.containsKey('pc') ||
                  sdata.containsKey('mobile');
            }
          }
        } catch (_) {}

        if (rtdbHasDual) {
          _allowDualDevice = true;
          final sessionPayload = {
            'activeDeviceId': deviceId,
            'sessionId': sessionId,
            'deviceName': deviceName,
            'deviceDetails': deviceDetails,
            'platform': platformKey,
            'slot': slot,
            'rollingToken': sessionId,
            'rollingTokenIssuedAt': ServerValue.timestamp,
            'forceLogout': false,
            'lastSeen': ServerValue.timestamp,
            'createdAt': ServerValue.timestamp,
          };

          await sessionRef.child(slot).set(sessionPayload);
          await sessionRef.update({
            'allowDualDevice': true,
            'allow1Mobile1Pc': true,
            'forceLogout': false,
          });

          sessionRef.child('activeDeviceId').remove().catchError((_) => null);
          sessionRef.child('sessionId').remove().catchError((_) => null);

          await startSessionListener(sessionId: sessionId, slot: slot);
          _startRollingTokenRefresh(uid, sessionId, slot: slot);
          _startForceLogoutListener(uid);
        } else {
          final sessionPayload = {
            'activeDeviceId': deviceId,
            'sessionId': sessionId,
            'deviceName': deviceName,
            'deviceDetails': deviceDetails,
            'platform': platformKey,
            'slot': 'single',
            'rollingToken': sessionId,
            'rollingTokenIssuedAt': ServerValue.timestamp,
            'forceLogout': false,
            'lastSeen': ServerValue.timestamp,
            'createdAt': ServerValue.timestamp,
          };

          // Write directly to user's root session node to invalidate any other device/platform
          await sessionRef.set(sessionPayload);

          await startSessionListener(sessionId: sessionId, slot: null);
          _startRollingTokenRefresh(uid, sessionId, slot: null);
          _startForceLogoutListener(uid);
        }
      }

      _logIpGeolocation(uid).catchError((_) {});
    } catch (e) {
      print('AuthenticationDataSource: _registerDeviceSession non-critical error: $e');
    }
  }

  // ── Feature 3: Rolling Session Token ──────────────────────────────────────

  /// Starts a timer that refreshes the rolling token every 30 minutes.
  /// If another device takes over the session, the newer token wins and the older client logs out.
  void _startRollingTokenRefresh(String uid, String sessionId, {String? slot}) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(_tokenRefreshInterval, (timer) async {
      final currentUid = lastLoggedInUid;
      if (currentUid == null || _database == null) { timer.cancel(); return; }

      final sessionRef = slot != null
          ? _database!.ref('${AppConstants.sessionsPath}/$currentUid/$slot')
          : _database!.ref('${AppConstants.sessionsPath}/$currentUid');
      try {
        final snap = await sessionRef.child('rollingToken').get();
        if (snap.exists) {
          final serverToken = snap.value?.toString();
          if (serverToken != null && serverToken != _currentRollingToken) {
            timer.cancel();
            final targetLabel = slot != null ? (slot == 'mobile' ? 'Mobile' : 'PC') : 'another device';
            _onSessionInvalidated?.call('DUPLICATE_SESSION: Active $targetLabel session was transferred to another device');
            signOut(removeFromDatabase: false);
            return;
          }
        }

        final newToken = const Uuid().v4();
        _currentRollingToken = newToken;
        await sessionRef.update({
          'rollingToken': newToken,
          'rollingTokenIssuedAt': ServerValue.timestamp,
          'lastSeen': ServerValue.timestamp,
        });
      } catch (_) {
        // Network error — try next cycle
      }
    });
  }

  String? _currentRollingToken;

  // ── Feature 2: Force Logout Kill-Switch ───────────────────────────────────

  /// Listens for admin-triggered forceLogout flag in RTDB.
  void _startForceLogoutListener(String uid) {
    _forceLogoutListener?.cancel();
    if (_database == null) return;
    final ref = _database!.ref('${AppConstants.sessionsPath}/$uid/forceLogout');
    _forceLogoutListener = ref.onValue.listen((event) {
      if (event.snapshot.value == true) {
        _onSessionInvalidated?.call('ADMIN_FORCE_LOGOUT');
        signOut(removeFromDatabase: false);
      }
    });
  }

  // ── Feature 5: IP Geolocation Logging ─────────────────────────────────────

  /// Logs the user's IP geolocation (city, country) to Firestore for anomaly detection.
  Future<void> _logIpGeolocation(String uid) async {
    if (kIsWeb) return; // Skip on web to prevent mixed-content/CORS browser security blocks
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map) {
          final entry = {
            'ip': data['ip']?.toString() ?? '',
            'city': data['city']?.toString() ?? '',
            'region': data['region']?.toString() ?? '',
            'country': data['country_name']?.toString() ?? '',
            'timestamp': DateTime.now().toIso8601String(),
          };
          if (_database != null) {
            await _database!.ref('${AppConstants.sessionsPath}/$uid/lastGeo').set(entry);
          }
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('geoHistory')
              .add(entry);
        }
      }
    } catch (_) {
      // Silently fail — non-critical
    }
  }

  Map<String, dynamic>? _extractMap(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final Map<String, dynamic> result = {};
      value.forEach((k, v) => result[k.toString()] = v);
      return result;
    }
    try {
      final dynamic dyn = value;
      if (dyn is Iterable) return null;
      final Map<String, dynamic> result = {};
      dyn.forEach((dynamic k, dynamic v) {
        result[k.toString()] = v;
      });
      return result;
    } catch (_) {}
    return null;
  }

  /// Start listening for session invalidation for already logged in users across all devices.
  /// Admin users skip this entirely — they are allowed on multiple devices.
  Future<void> startSessionListener({String? sessionId, String? slot}) async {
    if (_isAdmin || _database == null) return; // Admin bypasses single-device enforcement
    
    final uid = lastLoggedInUid;
    if (uid == null) return;

    final isDual = _allowDualDevice || await _isDualDeviceAllowed(uid);
    _allowDualDevice = isDual;
    final deviceSlot = slot ?? (isDual ? DeviceUtils.getDeviceSlot() : null);

    if (sessionId != null) {
      _currentSessionId = sessionId;
      _listenForSessionInvalidation(uid, sessionId, deviceSlot);
    } else {
      final sessionRef = _database!.ref('${AppConstants.sessionsPath}/$uid');
      final snapshot = await sessionRef.get();
      
      final data = _extractMap(snapshot.value);
      if (data != null) {
        final deviceId = await DeviceUtils.getDeviceId();
        Map<String, dynamic>? slotData;
        if (isDual && deviceSlot != null) {
          if (data[deviceSlot] is Map) {
            slotData = _extractMap(data[deviceSlot]);
          } else if (data['slot'] == deviceSlot) {
            slotData = data;
          }
        } else {
          slotData = data;
        }

        if (isDual && deviceSlot != null && slotData == null) {
          // Dedicated slot ('pc' or 'mobile') is unoccupied — register session immediately
          await _registerDeviceSession();
          return;
        }

        final activeDeviceId = slotData?['activeDeviceId']?.toString();
        String? mySessionId;
        if (activeDeviceId == deviceId) {
          mySessionId = slotData?['sessionId']?.toString();
        }
        
        if (mySessionId != null) {
          _currentSessionId = mySessionId;
          _currentRollingToken = mySessionId;
          _listenForSessionInvalidation(uid, mySessionId, deviceSlot);
        } else {
          // Device mismatch — another device is currently active on this slot
          final label = isDual ? (deviceSlot == 'mobile' ? 'another Mobile' : 'another PC') : 'another device';
          _onSessionInvalidated?.call('ANOTHER_DEVICE_LOGIN: $label');
          await signOut(removeFromDatabase: false);
          return;
        }
      } else {
        await _registerDeviceSession();
      }
    }

    // Start periodic check as a safety net
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final isValid = await checkSession();
      if (!isValid) {
        timer.cancel();
        _onSessionInvalidated?.call('DUPLICATE_SESSION: Session expired or replaced');
        signOut(removeFromDatabase: false);
      }
    });
  }

  /// Listen for session invalidation (kicked out when user logs in on another device of the same slot)
  void _listenForSessionInvalidation(String uid, String currentSessionId, [String? slot]) {
    _sessionListener?.cancel();
    if (_database == null) return;

    final sessionRef = slot != null
        ? _database!.ref('${AppConstants.sessionsPath}/$uid/$slot')
        : _database!.ref('${AppConstants.sessionsPath}/$uid');

    _sessionListener = sessionRef.onValue.listen((event) {
      final data = _extractMap(event.snapshot.value);
      if (data == null) return;

      final sessionId = data['sessionId']?.toString();
      final forceLogout = data['forceLogout'] == true;
      final newDevice = data['deviceName']?.toString() ?? data['platform']?.toString() ?? (slot != null ? 'another $slot' : 'another device');

      if (forceLogout || (sessionId != null && sessionId != _currentSessionId)) {
        _sessionListener?.cancel();
        _sessionCheckTimer?.cancel();
        _tokenRefreshTimer?.cancel();
        _onSessionInvalidated?.call(forceLogout ? 'ADMIN_FORCE_LOGOUT' : 'ANOTHER_DEVICE_LOGIN:$newDevice');
        signOut(removeFromDatabase: false);
      }
    });
  }

  String? _currentSessionId;

  /// Callback when session is invalidated by another device
  void Function(String reason)? _onSessionInvalidated;

  /// Set callback for session invalidation
  void setSessionInvalidationCallback(void Function(String reason) callback) {
    _onSessionInvalidated = callback;
  }

  /// Check if current session is valid across all devices
  /// Admin always returns true — no single-device restriction.
  Future<bool> checkSession() async {
    if (_isAdmin || _database == null) return true; // Admin bypasses session check
    
    final uid = lastLoggedInUid;
    if (uid == null) return false;

    try {
      final deviceId = await DeviceUtils.getDeviceId();
      final isDual = _allowDualDevice || await _isDualDeviceAllowed(uid);
      _allowDualDevice = isDual;
      final slot = isDual ? DeviceUtils.getDeviceSlot() : null;

      final sessionRef = slot != null
          ? _database!.ref('${AppConstants.sessionsPath}/$uid/$slot')
          : _database!.ref('${AppConstants.sessionsPath}/$uid');
      
      final snapshot = await sessionRef.get().timeout(const Duration(seconds: 10));
      final data = _extractMap(snapshot.value);
      if (data != null) {
        final activeDeviceId = data['activeDeviceId']?.toString();
        final sessionId = data['sessionId']?.toString();

        if (activeDeviceId == deviceId && (_currentSessionId == null || sessionId == _currentSessionId)) {
          return true;
        }
        return false;
      }

      await _registerDeviceSession();
      return true;
    } catch (e) {
      // If it's a transient network error, don't log out immediately
      return true; 
    }
  }

  /// Update last seen timestamp
  Future<void> updateLastSeen() async {
    final uid = lastLoggedInUid;
    if (uid == null || _database == null) return;

    try {
      final slot = _allowDualDevice ? DeviceUtils.getDeviceSlot() : null;
      final sessionRef = slot != null
          ? _database!.ref('${AppConstants.sessionsPath}/$uid/$slot')
          : _database!.ref('${AppConstants.sessionsPath}/$uid');
      await sessionRef.update({'lastSeen': ServerValue.timestamp});
    } catch (e) {
      // Silently fail - non-critical operation
    }
  }

  /// Check if email is verified
  Future<bool> isEmailVerified() async {
    final auth = _firebaseAuth;
    if (kIsWeb || auth == null) return true;
    try {
      final user = auth.currentUser;
      if (user == null) return false;
      await user.reload();
      return auth.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sign out
  Future<void> signOut({bool removeFromDatabase = true}) async {
    final uid = lastLoggedInUid;
    final db = _database;

    if (uid != null && removeFromDatabase && db != null) {
      try {
        final isDual = _allowDualDevice || await _isDualDeviceAllowed(uid);
        if (isDual) {
          final slot = DeviceUtils.getDeviceSlot();
          await db.ref('${AppConstants.sessionsPath}/$uid/$slot').remove();
        } else {
          final sessionRef = db.ref('${AppConstants.sessionsPath}/$uid');
          await sessionRef.remove();
        }
      } catch (e) {
        // Continue with sign out even if session cleanup fails
      }
    }

    _lastLoggedInUid = null;
    _lastLoggedInEmail = null;
    _lastIdToken = null;
    _currentSessionId = null;
    _allowDualDevice = false;
    _sessionListener?.cancel();
    _forceLogoutListener?.cancel();
    _sessionCheckTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _currentRollingToken = null;
    DeviceUtils.clearCache();
    final auth = _firebaseAuth;
    if (auth != null) {
      try {
        await auth.signOut();
      } catch (_) {}
    }
  }

  /// Get current user (safe on all platforms)
  firebase_auth.User? getCurrentUser() {
    final auth = _firebaseAuth;
    if (kIsWeb || auth == null) return null;
    try {
      return auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Get ID token for API requests
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final auth = _firebaseAuth;
    if (kIsWeb || auth == null) return _lastIdToken;
    try {
      final user = auth.currentUser;
      if (user == null) return null;
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return _lastIdToken;
    }
  }

  /// Stream of auth state changes
  Stream<firebase_auth.User?> get authStateChanges {
    final auth = _firebaseAuth;
    if (kIsWeb || auth == null) return const Stream.empty();
    return auth.authStateChanges();
  }

  /// Map Firebase auth errors to user-friendly messages
  AuthException _mapFirebaseAuthError(dynamic e, {bool isRegistration = false}) {
    if (e is AuthException) return e;

    final String errString = e != null ? e.toString() : '';
    final String lower = errString.toLowerCase();

    if (lower.contains('email-already-in-use') || lower.contains('already-in-use') || lower.contains('already in use') || lower.contains('already registered') || lower.contains('email_exists')) {
      return AuthException('Verification link already sent to your mail ID. Please check your inbox (and spam folder) to verify your account, or log in.', 'email-already-in-use');
    }
    if (lower.contains('invalid-email') || lower.contains('invalid email') || lower.contains('invalid_email')) {
      return AuthException('Please enter a valid email address.', 'invalid-email');
    }
    if (lower.contains('weak-password') || lower.contains('weak password') || lower.contains('password must be') || lower.contains('weak_password')) {
      return AuthException('Password is too weak. Please use at least 6 characters.', 'weak-password');
    }
    if (lower.contains('user-not-found') || lower.contains('no user record') || lower.contains('user_not_found')) {
      return AuthException('No account found with this email.', 'user-not-found');
    }
    if (lower.contains('wrong-password') || lower.contains('invalid password') || lower.contains('wrong_password')) {
      return AuthException('Incorrect password.', 'wrong-password');
    }
    if (lower.contains('user-disabled') || lower.contains('user_disabled')) {
      return AuthException('This account has been disabled by an administrator.', 'user-disabled');
    }
    if (lower.contains('too-many-requests') || lower.contains('too_many_attempts_try_later')) {
      return AuthException('Too many failed attempts. Please try again later.', 'too-many-requests');
    }
    if (lower.contains('network-request-failed') || lower.contains('network') || lower.contains('socket') || lower.contains('connection')) {
      return NetworkException('Network error. Please check your internet connection.');
    }
    if (lower.contains('operation-not-allowed') || lower.contains('operation_not_allowed')) {
      return AuthException('Email/Password registration is not enabled in Firebase Console.', 'operation-not-allowed');
    }
    if (lower.contains('invalid-credential') || lower.contains('invalid login credentials') || lower.contains('invalid_login_credentials')) {
      if (isRegistration) {
        return AuthException('Registration failed. This email address may already be registered.', 'invalid-credential');
      }
      return AuthException('Invalid email or password. Please verify credentials.', 'invalid-credential');
    }

    final clean = errString
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll('Exception:', '')
        .replaceAll("Instance of 'AuthException'", '')
        .replaceAll("Instance of 'NetworkException'", '')
        .replaceAll("Instance of", '')
        .replaceAll('TypeError:', '')
        .trim();

    if (clean.isNotEmpty &&
        !clean.contains('minified:') &&
        !clean.contains('subtype of') &&
        !clean.contains('Null check operator')) {
      return AuthException(clean);
    }

    return AuthException(
      isRegistration 
          ? 'Registration failed. Please check your details and try again.' 
          : 'Authentication failed. Please check your credentials.',
    );
  }
}
