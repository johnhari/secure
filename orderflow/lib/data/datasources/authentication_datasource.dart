import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FirebaseDatabase _database;
  StreamSubscription? _sessionListener;
  StreamSubscription? _forceLogoutListener;
  Timer? _sessionCheckTimer;
  Timer? _tokenRefreshTimer;
  
  /// Admin flag — when true, skip all single-device session enforcement
  /// so admin can be logged in on both Android and Desktop simultaneously.
  bool _isAdmin = false;
  
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _tokenRefreshInterval = Duration(minutes: 30);

  AuthenticationDataSource({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseDatabase? database,
  })  : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance;

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

  /// Sign in with email and password
  /// Returns a message if logged in on another device (session will be terminated there)
  Future<String?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      final userCredential = await _firebaseAuth
          .signInWithEmailAndPassword(
            email: normalizedEmail, 
            password: password,
          )
          .timeout(_requestTimeout, onTimeout: () {
            throw NetworkException('Login timed out. Please try again.');
          });
      
      final isMasterAdmin = AppConstants.isMasterAdmin(normalizedEmail);
      if (isMasterAdmin) {
        _isAdmin = true;
      }

      // Check if email is verified (bypassed for admin)
      if (userCredential.user != null && !userCredential.user!.emailVerified && !isMasterAdmin) {
        await userCredential.user!.sendEmailVerification();
        await _firebaseAuth.signOut();
        throw AuthException('Email not verified. A new verification link has been sent to your email.');
      }

      // Safe non-blocking session check
      String? sessionMessage;
      try {
        if (userCredential.user != null && !isMasterAdmin && !kIsWeb) {
          final currentDeviceId = await DeviceUtils.getDeviceId();
          final platformKey = _getPlatformKey();
          final sessionRef = _database.ref('${AppConstants.sessionsPath}/${userCredential.user!.uid}');
          
          final sessionSnapshot = await sessionRef.get().timeout(const Duration(seconds: 4));
          final data = _extractMap(sessionSnapshot.value);
          if (data != null) {
            final platformRaw = data[platformKey];
            final platformData = _extractMap(platformRaw);
            final activeDeviceId = (platformData != null ? platformData['activeDeviceId'] : data['activeDeviceId'])?.toString();
            
            if (activeDeviceId != null && activeDeviceId != currentDeviceId) {
               sessionMessage = 'You were logged in on another $platformKey device. That session has been terminated.';
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
      
      return sessionMessage;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Register with email and password (sends verification email, saves profile to Firestore)
  Future<bool> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
  }) async {
    try {
      final userCredential = await _firebaseAuth
          .createUserWithEmailAndPassword(
            email: email.toLowerCase().trim(),
            password: password,
          )
          .timeout(_requestTimeout, onTimeout: () {
            throw NetworkException('Registration timed out. Please try again.');
          });

      if (userCredential.user != null) {
        final user = userCredential.user!;
        
        // Update display name in Firebase Auth
        await user.updateDisplayName(name.trim());
        
        final devName = await DeviceUtils.getDeviceName();
        final devDetails = await DeviceUtils.getDeviceDetails();
        
        // Save profile to Firestore
        final firestore = FirebaseFirestore.instance;
        await firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name.trim(),
          'email': email.toLowerCase().trim(),
          'phoneNumber': phoneNumber.trim(),
          'role': 'viewer',
          'isApproved': false,
          'createdAt': DateTime.now().toIso8601String(),
          'registeredDeviceName': devName,
          'registeredDeviceDetails': devDetails,
        });
        
        // Send email verification
        await user.sendEmailVerification();
        
        // Sign out - user must verify email before logging in
        await _firebaseAuth.signOut();
        return true;
      }
      return false;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Update user display name in Firebase Auth
  Future<void> updateProfile(String name) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        await user.updateDisplayName(name.trim());
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Check if current user's email is verified
  Future<bool> isEmailVerified() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    if (AppConstants.isMasterAdmin(user.email)) return true;
    await user.reload(); // Refresh user data

    return user.emailVerified;
  }

  /// Resend verification email
  Future<void> resendVerificationEmail() async {
    final user = _firebaseAuth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Send password reset email (only if email is registered)
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      await _firebaseAuth.sendPasswordResetEmail(email: normalizedEmail);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Register device session (single-device per platform enforcement: 1 Phone + 1 Windows system)
  /// Admin users skip session overwrite so they can be on multiple devices.
  Future<void> _registerDeviceSession([DataSnapshot? existingSessionSnapshot]) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) return;

      final deviceId = await DeviceUtils.getDeviceId();
      final platformKey = _getPlatformKey();
      String sessionId;
      
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        sessionId = prefs.getString('web_session_id') ?? const Uuid().v4();
        await prefs.setString('web_session_id', sessionId);
      } else {
        sessionId = const Uuid().v4();
      }

      final sessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}');
      
      if (_isAdmin) {
        try {
          await sessionRef.child('lastSeen').set(ServerValue.timestamp);
          await sessionRef.child(platformKey).child('lastSeen').set(ServerValue.timestamp);
        } catch (_) {}
        _startForceLogoutListener(user.uid);
      } else {
        final platformPayload = {
          'activeDeviceId': deviceId,
          'sessionId': sessionId,
          'rollingToken': sessionId,
          'rollingTokenIssuedAt': ServerValue.timestamp,
          'lastSeen': ServerValue.timestamp,
          'createdAt': ServerValue.timestamp,
        };

        try {
          await sessionRef.update({
            'activeDeviceId': deviceId,
            'sessionId': sessionId,
            'rollingToken': sessionId,
            'rollingTokenIssuedAt': ServerValue.timestamp,
            'forceLogout': false,
            'lastSeen': ServerValue.timestamp,
            'createdAt': ServerValue.timestamp,
            platformKey: platformPayload,
          });
        } catch (_) {
          try {
            await sessionRef.child(platformKey).set(platformPayload);
          } catch (_) {}
        }

        await startSessionListener(sessionId: sessionId);
        _startRollingTokenRefresh(user.uid, sessionId);
        _startForceLogoutListener(user.uid);
      }

      _logIpGeolocation(user.uid).catchError((_) {});
    } catch (e) {
      print('AuthenticationDataSource: _registerDeviceSession non-critical error: $e');
    }
  }

  // ── Feature 3: Rolling Session Token ──────────────────────────────────────

  /// Starts a timer that refreshes the rolling token every 30 minutes.
  /// If two clients of the same platform hold the session, the newer token wins and the older client logs out.
  void _startRollingTokenRefresh(String uid, String sessionId) {
    _tokenRefreshTimer?.cancel();
    final platformKey = _getPlatformKey();
    _tokenRefreshTimer = Timer.periodic(_tokenRefreshInterval, (timer) async {
      final user = _firebaseAuth.currentUser;
      if (user == null) { timer.cancel(); return; }

      final platformRef = _database.ref('${AppConstants.sessionsPath}/$uid/$platformKey');
      try {
        final snap = await platformRef.child('rollingToken').get();
        if (snap.exists) {
          final serverToken = snap.value?.toString();
          if (serverToken != null && serverToken != _currentRollingToken) {
            timer.cancel();
            _onSessionInvalidated?.call();
            signOut(removeFromDatabase: false);
            return;
          }
        }

        final newToken = const Uuid().v4();
        _currentRollingToken = newToken;
        await platformRef.update({
          'rollingToken': newToken,
          'rollingTokenIssuedAt': ServerValue.timestamp,
          'lastSeen': ServerValue.timestamp,
        });
        await _database.ref('${AppConstants.sessionsPath}/$uid').update({
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
    final ref = _database.ref('${AppConstants.sessionsPath}/$uid/forceLogout');
    _forceLogoutListener = ref.onValue.listen((event) {
      if (event.snapshot.value == true) {
        _onSessionInvalidated?.call();
        signOut(removeFromDatabase: false);
      }
    });
  }

  // ── Feature 5: IP Geolocation Logging ─────────────────────────────────────

  /// Logs the user's IP geolocation (city, country) to Firestore for anomaly detection.
  /// Uses ip-api.com free tier (no key required, non-commercial use).
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
          // Store in RTDB session node
          await _database.ref('${AppConstants.sessionsPath}/$uid/lastGeo').set(entry);
          // Also append to Firestore geo history (admin can see login locations)
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

  /// Start listening for session invalidation for already logged in users
  /// Admin users skip this entirely — they are allowed on multiple devices.
  Future<void> startSessionListener({String? sessionId}) async {
    if (_isAdmin) return; // Admin bypasses single-device enforcement
    
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    final platformKey = _getPlatformKey();

    if (sessionId != null) {
      _currentSessionId = sessionId;
      _listenForSessionInvalidation(user.uid, sessionId);
    } else {
      final platformSessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}/$platformKey');
      final snapshot = await platformSessionRef.get();
      
      final data = _extractMap(snapshot.value);
      if (data != null) {
        final deviceId = await DeviceUtils.getDeviceId();
        final activeDeviceId = data['activeDeviceId']?.toString();
        
        String? mySessionId;
        if (activeDeviceId == deviceId) {
          mySessionId = data['sessionId']?.toString();
        }
        
        if (mySessionId != null) {
          _currentSessionId = mySessionId; // Store locally to compare in listener
          _listenForSessionInvalidation(user.uid, mySessionId);
        } else {
          // If device mismatch on this platform, log out native clients immediately.
          if (kIsWeb) {
            await _registerDeviceSession();
          } else {
            _onSessionInvalidated?.call();
            await signOut(removeFromDatabase: false);
          }
        }
      } else {
        // Fallback: check root session node if platform node not created yet
        final sessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}');
        final mainSnap = await sessionRef.get();
        final mainData = _extractMap(mainSnap.value);
        if (mainData != null) {
          final deviceId = await DeviceUtils.getDeviceId();
          final activeDeviceId = mainData['activeDeviceId']?.toString();
          if (activeDeviceId == deviceId) {
            final mySessionId = mainData['sessionId']?.toString();
            if (mySessionId != null) {
              _currentSessionId = mySessionId;
              _listenForSessionInvalidation(user.uid, mySessionId);
              return;
            }
          }
        }
        await _registerDeviceSession();
      }
    }

    // Start periodic check as a safety net (relaxed interval for Web stability)
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      final isValid = await checkSession();
      if (!isValid) {
        timer.cancel();
        _onSessionInvalidated?.call();
        signOut(removeFromDatabase: false);
      }
    });
  }

  /// Listen for session invalidation (kicked out by another device on the same platform)
  void _listenForSessionInvalidation(String uid, String currentSessionId) {
    _sessionListener?.cancel();

    final platformKey = _getPlatformKey();
    final platformSessionRef = _database.ref('${AppConstants.sessionsPath}/$uid/$platformKey');

    _sessionListener = platformSessionRef.onValue.listen((event) {
      final data = _extractMap(event.snapshot.value);
      if (data == null) return;

      final sessionId = data['sessionId']?.toString();

      // WEB STABILITY: If we just hijacked the session, our local currentSessionId 
      // might be outdated. We should NOT log out if the new ID is what we just set.
      if (sessionId != _currentSessionId) {
        // Double check if this is really a mismatch or just a delay in local state sync
        if (kIsWeb && sessionId != null) {
           // On Web, we are extra cautious. Only logout if the ID is totally different 
           // and doesn't match our persistent storage.
           _verifyAndLogout(uid, sessionId);
           return;
        }

        _onSessionInvalidated?.call();
        signOut(removeFromDatabase: false);
      }
    });
  }

  String? _currentSessionId;

  Future<void> _verifyAndLogout(String uid, String newSessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final persistentId = prefs.getString('web_session_id');
    
    if (newSessionId != persistentId) {
      _onSessionInvalidated?.call();
      signOut(removeFromDatabase: false);
    } else {
      // It's actually us! Update local reference.
      _currentSessionId = newSessionId;
    }
  }

  /// Callback when session is invalidated by another device
  void Function()? _onSessionInvalidated;

  /// Set callback for session invalidation
  void setSessionInvalidationCallback(void Function() callback) {
    _onSessionInvalidated = callback;
  }

  /// Check if current session is valid
  /// Admin always returns true — no single-device restriction.
  Future<bool> checkSession() async {
    if (_isAdmin) return true; // Admin bypasses session check
    
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;

    try {
      final deviceId = await DeviceUtils.getDeviceId();
      final platformKey = _getPlatformKey();
      final platformSessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}/$platformKey');
      
      // Use a timeout to prevent hanging on poor connections
      final snapshot = await platformSessionRef.get().timeout(const Duration(seconds: 10));

      final data = _extractMap(snapshot.value);
      if (data != null) {
        final activeDeviceId = data['activeDeviceId']?.toString();

        if (activeDeviceId == deviceId) {
          return true;
        }
      } else {
        // Check top-level session node for backward compatibility
        final sessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}');
        final mainSnapshot = await sessionRef.get().timeout(const Duration(seconds: 5));
        final mainData = _extractMap(mainSnapshot.value);
        if (mainData != null) {
          final activeDeviceId = mainData['activeDeviceId']?.toString();
          if (activeDeviceId == deviceId) {
            return true;
          }
        }
        await _registerDeviceSession();
        return true;
      }

      // --- WEB DOUBLE-LOGIN FIX ---
      if (kIsWeb) {
        print('AuthenticationDataSource: Web session mismatch detected. Claiming session for current device.');
        await _registerDeviceSession();
        // Update local session ID to prevent self-logout from the active listener
        final prefs = await SharedPreferences.getInstance();
        _currentSessionId = prefs.getString('web_session_id');
        return true;
      }

      return false;
    } catch (e) {
      // If it's a network error, don't log out immediately - assume valid
      return true; 
    }
  }

  /// Update last seen timestamp
  Future<void> updateLastSeen() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    try {
      final sessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}');
      await sessionRef.update({'lastSeen': ServerValue.timestamp});
    } catch (e) {
      // Silently fail - non-critical operation
    }
  }

  /// Sign out
  Future<void> signOut({bool removeFromDatabase = true}) async {
    final user = _firebaseAuth.currentUser;

    if (user != null && removeFromDatabase) {
      try {
        final sessionRef = _database.ref('${AppConstants.sessionsPath}/${user.uid}');
        await sessionRef.remove();
      } catch (e) {
        // Continue with sign out even if session cleanup fails
      }
    }

    _sessionListener?.cancel();
    _forceLogoutListener?.cancel();
    _sessionCheckTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _currentRollingToken = null;
    DeviceUtils.clearCache();
    await _firebaseAuth.signOut();
  }

  /// Get current user
  firebase_auth.User? getCurrentUser() => _firebaseAuth.currentUser;

  /// Get ID token for API requests
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return await user.getIdToken(forceRefresh);
  }

  /// Stream of auth state changes
  Stream<firebase_auth.User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Map Firebase auth errors to user-friendly messages
  AuthException _mapFirebaseAuthError(dynamic e) {
    final str = e.toString().toLowerCase();
    String? code;
    try {
      final dynamic dyn = e;
      code = dyn.code?.toString();
    } catch (_) {}

    if (code == 'user-not-found' || str.contains('user-not-found')) {
      return AuthException('No account found with this email.', code);
    }
    if (code == 'wrong-password' || str.contains('wrong-password')) {
      return AuthException('Incorrect password.', code);
    }
    if (code == 'invalid-email' || str.contains('invalid-email')) {
      return AuthException('Invalid email address.', code);
    }
    if (code == 'user-disabled' || str.contains('user-disabled')) {
      return AuthException('This account has been disabled.', code);
    }
    if (code == 'email-already-in-use' || str.contains('email-already-in-use')) {
      return AuthException('This email is already registered.', code);
    }
    if (code == 'weak-password' || str.contains('weak-password')) {
      return AuthException('Password is too weak. Use at least 6 characters.', code);
    }
    if (code == 'too-many-requests' || str.contains('too-many-requests')) {
      return AuthException('Too many attempts. Please try again later.', code);
    }
    if (code == 'network-request-failed' || str.contains('network') || str.contains('socket')) {
      return NetworkException();
    }
    if (code == 'invalid-credential' || str.contains('invalid-credential')) {
      return AuthException('Invalid email or password.', code);
    }
    return AuthException('Invalid email or password. Please try again.', code);
  }
}
