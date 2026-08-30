import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/device_utils.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/user_profile.dart';
import '../../core/constants/app_constants.dart';
import 'providers.dart';


enum AuthStatus { initial, loading, authenticated, guest, unauthenticated, error }

class AuthState {
  final UserProfile? user;
  final AuthStatus status;
  final String? error;

  const AuthState({
    this.user,
    this.status = AuthStatus.initial,
    this.error,
  });

  bool get isLoading => status == AuthStatus.loading;
  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isGuest => status == AuthStatus.guest;

  AuthState copyWith({
    UserProfile? user,
    AuthStatus? status,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      status: status ?? this.status,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  Timer? _lastSeenTimer;
  StreamSubscription? _authStateSub;
  int _lastVerificationMinutes = 0;

  AuthNotifier(this._authRepository) : super(const AuthState()) {
    _authRepository.setSessionInvalidationCallback(() {
      _lastSeenTimer?.cancel();
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Logged out: Your account is being used on another device.',
      );
    });

    // Listen for external auth state changes
    _authStateSub = _authRepository.authStateStream.listen((user) {
      if (user == null && state.isAuthenticated) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    });

    _checkInitialAuth();
  }

  String? _checkAccess(UserProfile? profile) {
    if (profile == null) return 'Session error. Please login again.';
    
    if (profile.isAdmin || AppConstants.isMasterAdmin(profile.email)) return null; // Admins always have access

    if (profile.isCanceled) {
      return 'ACCESS DENIED: Your account has been suspended by the administrator.';
    }

    if (!profile.isApproved) {
      return 'PENDING_APPROVAL';
    }

    if (profile.expiryDate != null) {
      // Use UTC comparison to prevent timezone-related premature logouts
      if (DateTime.now().toUtc().isAfter(profile.expiryDate!.toUtc())) {
        return 'SUBSCRIPTION EXPIRED: Please renew your access to continue using the terminal.';
      }
    }

    return null;
  }

  /// Enforce hardware ID lock (Supports 1 Phone + 1 Windows system concurrently)
  Future<String?> _checkHardwareLock(UserProfile profile) async {
    if (profile.isAdmin || AppConstants.isMasterAdmin(profile.email)) return null; // Admins bypass HWID lock

    // Check for VM (Anti-VM detection)
    try {
      final isVM = await DeviceUtils.isRunningInVM();
      if (isVM) {
        return 'SECURITY VIOLATION: Virtual Machine Detected.\n\nTo prevent license misuse and cloning, this terminal is restricted to running on physical systems only.';
      }
    } catch (_) {}

    final currentDeviceId = await DeviceUtils.getDeviceId();
    final bool isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final bool isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    if (isWindows) {
      if (profile.boundWindowsDeviceId == null || profile.boundWindowsDeviceId!.isEmpty) {
        if (profile.boundDeviceId == currentDeviceId) {
          await _authRepository.bindHardwareId(profile.uid, currentDeviceId, isWindows: true, isMobile: false);
          return null;
        }
        await _authRepository.bindHardwareId(profile.uid, currentDeviceId, isWindows: true, isMobile: false);
        return null;
      }

      if (profile.boundWindowsDeviceId != currentDeviceId) {
        return 'HARDWARE LOCKOUT: This account is permanently registered to another Windows system.\n\nTo transfer your license, please contact the administrator.';
      }
      return null;
    }

    if (isMobile) {
      if (profile.boundMobileDeviceId == null || profile.boundMobileDeviceId!.isEmpty) {
        if (profile.boundDeviceId == currentDeviceId) {
          await _authRepository.bindHardwareId(profile.uid, currentDeviceId, isWindows: false, isMobile: true);
          return null;
        }
        await _authRepository.bindHardwareId(profile.uid, currentDeviceId, isWindows: false, isMobile: true);
        return null;
      }

      if (profile.boundMobileDeviceId != currentDeviceId) {
        return 'HARDWARE LOCKOUT: This account is permanently registered to another Phone device.\n\nTo transfer your license, please contact the administrator.';
      }
      return null;
    }

    // Fallback for Web or unclassified platform
    if (profile.boundDeviceId == null || profile.boundDeviceId!.isEmpty) {
      await _authRepository.bindHardwareId(profile.uid, currentDeviceId, isWindows: false, isMobile: false);
      return null;
    }

    if (profile.boundDeviceId != currentDeviceId &&
        profile.boundWindowsDeviceId != currentDeviceId &&
        profile.boundMobileDeviceId != currentDeviceId) {
      return 'HARDWARE LOCKOUT: This account is permanently registered to another system.\n\nTo transfer your license, please contact the administrator.';
    }

    return null;
  }

  @override
  void dispose() {
    _lastSeenTimer?.cancel();
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialAuth() async {
    try {
      if (_authRepository.isAuthenticated()) {
        state = state.copyWith(status: AuthStatus.loading);
        
        // Step 1: Fetch profile and email verification in parallel (with timeout)
        // Profile is needed first to set admin mode before session check
        final result = await Future.any([
          Future.wait([
            _authRepository.isEmailVerified(),
            _authRepository.getCurrentUserProfile(),
          ]),
          Future.delayed(const Duration(seconds: 5)).then((_) => throw TimeoutException('Auth check took too long')),
        ]);

        final isEmailVerified = result[0] as bool;
        final profile = result[1] as UserProfile?;
        
        if (!isEmailVerified) {
          await _authRepository.signOut();
          state = const AuthState(status: AuthStatus.unauthenticated);
          return;
        }

        // Step 2: Set admin mode BEFORE checking session
        // This ensures admin bypasses single-device session enforcement
        if (profile != null && profile.isAdmin) {
          _authRepository.setAdminMode(true);
        }

        // Step 3: Now check session (respects admin mode)
        final isValid = await _authRepository.checkSession();
        
        if (isValid) {
          // Check access permissions
          final accessError = _checkAccess(profile);
          if (accessError != null) {
            await _authRepository.signOut();
            state = state.copyWith(
              status: AuthStatus.unauthenticated,
              error: accessError,
            );
            return;
          }

          // Check hardware lock (One User, One System)
          if (profile != null) {
            final hwError = await _checkHardwareLock(profile);
            if (hwError != null) {
              await _authRepository.signOut();
              state = state.copyWith(
                status: AuthStatus.unauthenticated,
                error: hwError,
              );
              return;
            }
          }

          state = AuthState(
            user: profile,
            status: AuthStatus.authenticated,
          );
          _startLastSeenTimer();
          _authRepository.startSessionListener();
          _authRepository.updateDeviceInfo();
        } else {
          await _authRepository.signOut();
          state = const AuthState(status: AuthStatus.unauthenticated);
        }
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      print('AuthNotifier: Error or timeout in _checkInitialAuth: $e');
      // Fallback to unauthenticated so user can at least proceed as Guest
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Returns a message if user was logged in on another device
  Future<String?> signIn(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      final sessionMessage = await _authRepository.signIn(email, password);
      final profile = await _authRepository.getCurrentUserProfile();

      // Set admin mode for ongoing session checks (admin bypasses single-device restriction)
      if (profile != null && profile.isAdmin) {
        _authRepository.setAdminMode(true);
      }
      
      if (profile != null && !profile.isApproved) {
        try {
          final devName = await DeviceUtils.getDeviceName();
          final devDetails = await DeviceUtils.getDeviceDetails();
          await FirebaseFirestore.instance.collection('users').doc(profile.uid).update({
            'registeredDeviceName': devName,
            'registeredDeviceDetails': devDetails,
          });
        } catch (_) {}
      }

      // Check access permissions
      final accessError = _checkAccess(profile);
      if (accessError != null) {
        await _authRepository.signOut();
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: accessError,
        );
        return accessError;
      }

      // Check hardware lock (One User, One System)
      final hwError = await _checkHardwareLock(profile!);
      if (hwError != null) {
        await _authRepository.signOut();
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: hwError,
        );
        return hwError;
      }

      state = AuthState(
        user: profile,
        status: AuthStatus.authenticated,
      );
      _startLastSeenTimer();
      _authRepository.updateDeviceInfo();
      return sessionMessage;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      final verificationSent = await _authRepository.register(
        email: email,
        password: password,
        name: name,
        phoneNumber: phoneNumber,
      );
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return verificationSent;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      await _authRepository.sendPasswordResetEmail(email);
      state = state.copyWith(status: AuthStatus.unauthenticated);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> updateProfile({String? name, String? phoneNumber}) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      await _authRepository.updateUserProfile(name: name, phoneNumber: phoneNumber);
      final profile = await _authRepository.getCurrentUserProfile();
      state = state.copyWith(
        user: profile,
        status: AuthStatus.authenticated,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  void _startLastSeenTimer() {
    _lastSeenTimer?.cancel();
    _lastVerificationMinutes = 0;
    _lastSeenTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      // 1. Update last seen in DB
      _authRepository.updateLastSeen();

      // 2. Immediate Local Expiry Check (Zero network DB cost, enforced every minute)
      if (state.user != null) {
        final accessError = _checkAccess(state.user);
        if (accessError != null) {
          timer.cancel();
          signOut(error: accessError);
          return;
        }
      }

      // 3. Periodic Authorization & Expiry Verification from Firestore (Every 5 minutes)
      _lastVerificationMinutes++;
      if (_lastVerificationMinutes >= 5) {
        _lastVerificationMinutes = 0;
        
        try {
          final profile = await _authRepository.getCurrentUserProfile();
          if (profile != null) {
            final accessError = _checkAccess(profile);
            if (accessError != null) {
              timer.cancel();
              signOut(error: accessError);
            } else {
              state = state.copyWith(user: profile);
            }
          }
        } catch (_) {}
      }
    });
  }



  Future<void> signOut({String? error}) async {
    _lastSeenTimer?.cancel();
    await _authRepository.signOut();
    state = AuthState(
      status: AuthStatus.unauthenticated,
      error: error,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
