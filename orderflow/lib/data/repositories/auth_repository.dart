import 'package:cloud_firestore/cloud_firestore.dart';
import '../datasources/authentication_datasource.dart';
import '../../domain/entities/user_profile.dart';
import '../../core/services/device_service.dart';
import '../../core/constants/app_constants.dart';


class AuthRepository {
  final AuthenticationDataSource _authDataSource;
  final FirebaseFirestore _firestore;

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

  /// Set callback for session invalidation
  void setSessionInvalidationCallback(void Function() callback) {
    _authDataSource.setSessionInvalidationCallback(callback);
  }

  /// Check if email is verified
  Future<bool> isEmailVerified() async {
    return await _authDataSource.isEmailVerified();
  }

  /// Get current user profile
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _authDataSource.getCurrentUser();
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final isMasterAdmin = AppConstants.isMasterAdmin(user.email);

      if (doc.exists) {
        final data = doc.data()!;
        return UserProfile.fromJson({
          ...data,
          'uid': user.uid,
          if (isMasterAdmin) 'role': 'admin',
          if (isMasterAdmin) 'isApproved': true,
        });
      }

      // Create profile
      final profile = UserProfile(
        uid: user.uid,
        role: isMasterAdmin ? UserRole.admin : UserRole.viewer,
        email: user.email,
        phoneNumber: user.phoneNumber,
        isApproved: isMasterAdmin ? true : false,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('users').doc(user.uid).set(profile.toJson());
      return profile;
    } catch (e, stackTrace) {
      print('getCurrentUserProfile error: $e');
      print(stackTrace);
      return null;
    }
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
        await _firestore.collection('users').doc(user.uid).update(updates);
      }
    } catch (e) {
      throw AuthException('Failed to update profile: $e');
    }
  }

  /// Bind unique hardware device ID to user profile (supports 1 Phone + 1 Windows device)
  Future<void> bindHardwareId(String uid, String deviceId, {bool isWindows = false, bool isMobile = false}) async {
    try {
      final updates = <String, dynamic>{
        'boundDeviceId': deviceId,
      };
      if (isWindows) {
        updates['boundWindowsDeviceId'] = deviceId;
      } else if (isMobile) {
        updates['boundMobileDeviceId'] = deviceId;
      }
      await _firestore.collection('users').doc(uid).update(updates);
    } catch (e) {
      print('AuthRepository: bindHardwareId error: $e');
    }
  }

  /// Update device info in Firestore for performance monitoring
  Future<void> updateDeviceInfo() async {
    final user = _authDataSource.getCurrentUser();
    if (user == null) return;

    try {
      final deviceInfo = await DeviceService.getDeviceInfo();
      await _firestore.collection('users').doc(user.uid).update({
        'deviceInfo': deviceInfo,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Silently fail - non-critical
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

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _authDataSource.getCurrentUser() != null;
  }

  /// Auth state stream
  Stream get authStateStream => _authDataSource.authStateChanges;
}
