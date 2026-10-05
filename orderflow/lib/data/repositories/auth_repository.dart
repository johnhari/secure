import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../datasources/authentication_datasource.dart';
import '../../domain/entities/user_profile.dart';
import '../../core/services/device_service.dart';
import '../../core/constants/app_constants.dart';


class AuthRepository {
  final AuthenticationDataSource _authDataSource;
  final FirebaseFirestore? _firestore;

  AuthRepository({
    required AuthenticationDataSource authDataSource,
    FirebaseFirestore? firestore,
  })  : _authDataSource = authDataSource,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Sign in with email and password
  /// Returns a message if user was logged in on another device
  Future<String?> signIn(String email, String password) async {
    if (email.isEmpty) throw AuthException('Email is required');
    if (password.isEmpty) throw AuthException('Password is required');
    return await _authDataSource.signInWithEmailAndPassword(email, password);
  }

  /// Register with email, password, name and phone (sends verification email)
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
  }) async {
    if (email.isEmpty) throw AuthException('Email is required');
    if (password.length < 6) throw AuthException('Password must be at least 6 characters');
    if (name.isEmpty) throw AuthException('Name is required');
    if (phoneNumber.isEmpty) throw AuthException('Phone number is required');
    return await _authDataSource.registerWithEmailAndPassword(
      email: email,
      password: password,
      name: name,
      phoneNumber: phoneNumber,
    );
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    if (email.isEmpty) throw AuthException('Email is required');
    await _authDataSource.sendPasswordResetEmail(email);
  }

  /// Check if session is valid
  Future<bool> checkSession() async {
    return await _authDataSource.checkSession();
  }

  /// Start session listener
  Future<void> startSessionListener() async {
    await _authDataSource.startSessionListener();
  }

  /// Set admin mode to bypass single-device session enforcement
  void setAdminMode(bool isAdmin) {
    _authDataSource.setAdminMode(isAdmin);
  }

  /// Set dual device (1 mobile + 1 pc) access mode
  void setAllowDualDevice(bool allow) {
    _authDataSource.setAllowDualDevice(allow);
  }

  /// Set callback for session invalidation
  void setSessionInvalidationCallback(void Function(String reason) callback) {
    _authDataSource.setSessionInvalidationCallback(callback);
  }

  /// Check if email is verified
  Future<bool> isEmailVerified() async {
    return await _authDataSource.isEmailVerified();
  }

  /// Get current user profile
  Future<UserProfile?> getCurrentUserProfile() async {
    final uid = _authDataSource.lastLoggedInUid;
    final email = _authDataSource.lastLoggedInEmail;
    if (uid == null) return null;

    final db = _firestore;
    if (db == null) {
      if (_authDataSource.lastIdToken != null) {
        final profileFromRest = await _fetchUserProfileViaRest(uid, _authDataSource.lastIdToken!, email);
        if (profileFromRest != null) return profileFromRest;
      }
      return null;
    }

    try {
      final doc = await db.collection('users').doc(uid).get();
      final isMasterAdmin = AppConstants.isMasterAdmin(email);

      if (doc.exists && doc.data() != null) {
        final rawData = doc.data();
        final Map<String, dynamic> data = {};
        if (rawData != null) {
          rawData.forEach((key, value) {
            data[key.toString()] = value;
          });
        }
        data['uid'] = uid;
        if (isMasterAdmin) {
          data['role'] = 'admin';
          data['isApproved'] = true;
        }
        return UserProfile.fromJson(data);
      }

      // If document not found directly or on Web, try REST API fallback
      if (kIsWeb && _authDataSource.lastIdToken != null) {
        final profileFromRest = await _fetchUserProfileViaRest(uid, _authDataSource.lastIdToken!, email);
        if (profileFromRest != null) return profileFromRest;
      }

      // Create profile fallback
      final profile = UserProfile(
        uid: uid,
        role: isMasterAdmin ? UserRole.admin : UserRole.viewer,
        email: email,
        isApproved: isMasterAdmin ? true : false,
        createdAt: DateTime.now(),
      );

      return profile;
    } catch (e, stackTrace) {
      print('getCurrentUserProfile error: $e');
      if (kIsWeb && _authDataSource.lastIdToken != null) {
        try {
          final profileFromRest = await _fetchUserProfileViaRest(uid, _authDataSource.lastIdToken!, email);
          if (profileFromRest != null) return profileFromRest;
        } catch (_) {}
      }
      return null;
    }
  }

  /// REST fallback for fetching Firestore user profile on Web
  Future<UserProfile?> _fetchUserProfileViaRest(String uid, String idToken, String? email) async {
    try {
      final url = Uri.parse('https://firestore.googleapis.com/v1/projects/mst7-3fb55/databases/(default)/documents/users/$uid');
      final resp = await http.get(url, headers: {'Authorization': 'Bearer $idToken'});
      if (resp.statusCode == 200) {
        final doc = jsonDecode(resp.body);
        final fields = doc['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          final Map<String, dynamic> data = {'uid': uid};
          fields.forEach((key, val) {
            if (val is Map) {
              if (val.containsKey('stringValue')) data[key] = val['stringValue'];
              else if (val.containsKey('booleanValue')) data[key] = val['booleanValue'];
              else if (val.containsKey('integerValue')) data[key] = int.tryParse(val['integerValue'].toString());
              else if (val.containsKey('timestampValue')) data[key] = val['timestampValue'];
            }
          });
          return UserProfile.fromJson(data);
        }
      }
    } catch (e) {
      print('REST user profile fetch failed: $e');
    }
    return null;
  }

  /// Update user profile in Firestore and Firebase Auth
  Future<void> updateUserProfile({String? name, String? phoneNumber}) async {
    final user = _authDataSource.getCurrentUser();
    if (user == null) throw AuthException('Not authenticated');

    try {
      final updates = <String, dynamic>{};
      if (name != null) {
        updates['name'] = name.trim();
        await _authDataSource.updateProfile(name);
      }
      if (phoneNumber != null) {
        updates['phoneNumber'] = phoneNumber.trim();
      }

      if (updates.isNotEmpty) {
        final db = _firestore;
        if (db != null) {
          await db.collection('users').doc(user.uid).update(updates);
        }
      }
    } catch (e) {
      throw AuthException('Failed to update profile: $e');
    }
  }

  /// Bind unique hardware device ID to user profile
  Future<void> bindHardwareId(String uid, String deviceId, {bool isWindows = false, bool isMobile = false}) async {
    final db = _firestore;
    if (kIsWeb || db == null) return;
    try {
      final updates = <String, dynamic>{
        'boundDeviceId': deviceId,
      };
      if (isWindows) {
        updates['boundWindowsDeviceId'] = deviceId;
      } else if (isMobile) {
        updates['boundMobileDeviceId'] = deviceId;
      }
      await db.collection('users').doc(uid).update(updates);
    } catch (e) {
      print('AuthRepository: bindHardwareId error: $e');
    }
  }

  /// Update device info in Firestore for performance monitoring
  Future<void> updateDeviceInfo() async {
    final db = _firestore;
    if (kIsWeb || db == null) return;
    final user = _authDataSource.getCurrentUser();
    if (user == null) return;

    try {
      final deviceInfo = await DeviceService.getDeviceInfo();
      await db.collection('users').doc(user.uid).update({
        'deviceInfo': deviceInfo,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('AuthRepository: updateDeviceInfo error: $e');
    }
  }

  /// Get ID token
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _authDataSource.getIdToken(forceRefresh: forceRefresh);
  }

  /// Update last seen
  Future<void> updateLastSeen() async {
    await _authDataSource.updateLastSeen();
  }

  /// Sign out
  Future<void> signOut() async {
    await _authDataSource.signOut();
  }

  /// Get current Firebase user
  firebase_auth.User? getCurrentUser() => _authDataSource.getCurrentUser();

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _authDataSource.getCurrentUser() != null;
  }

  /// Auth state stream
  Stream<firebase_auth.User?> get authStateStream => _authDataSource.authStateChanges;
}
