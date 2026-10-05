import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../core/utils/device_utils.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/datasources/authentication_datasource.dart';
import '../../domain/entities/user_profile.dart';
import '../../core/constants/app_constants.dart';


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
  StreamSubscription<firebase_auth.User?>? _authStateSub;
  int _lastVerificationMinutes = 0;

  AuthNotifier(this._authRepository) : super(const AuthState(status: AuthStatus.unauthenticated)) {
    _authRepository.setSessionInvalidationCallback((reason) {
      _lastSeenTimer?.cancel();
      String err;
      if (reason.startsWith('ANOTHER_DEVICE_LOGIN:')) {
        final device = reason.replaceFirst('ANOTHER_DEVICE_LOGIN:', '').trim();
        err = 'DUPLICATE_SESSION: Your account was logged in on $device. This previous session was automatically terminated.';
      } else if (reason == 'ADMIN_FORCE_LOGOUT') {
        err = 'ADMIN_LOGOUT: Your session was terminated by the administrator.';
      } else {
        err = 'DUPLICATE_SESSION: Your account is being used on another device. Only 1 active session is allowed at a time.';
      }
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: err,
      );
    });

    // Listen for external auth state changes (Native platforms only)
    if (!kIsWeb) {
      try {
        _authStateSub = _authRepository.authStateStream.listen((firebase_auth.User? user) {
          if (user == null && state.isAuthenticated) {
            state = const AuthState(status: AuthStatus.unauthenticated);
          }
        }, onError: (err) {
          debugPrint('AuthNotifier: authStateStream error: $err');
        });
      } catch (e) {
        debugPrint('AuthNotifier: authStateStream listener init error: $e');
      }

      _checkInitialAuth();
    }
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

  /// Enforce security checks (Anti-VM detection)
  /// Single-device policy across all platforms (Mobile, iPhone, Mac, Windows, Web) is enforced via RTDB real-time session invalidation
  Future<String?> _checkHardwareLock(UserProfile profile) async {
    if (kIsWeb) return null; // Web sessions
    if (profile.isAdmin || AppConstants.isMasterAdmin(profile.email)) return null; // Admins bypass

    // Check for VM (Anti-VM detection)
    try {
      final isVM = await DeviceUtils.isRunningInVM();
      if (isVM) {
        return 'SECURITY VIOLATION: Virtual Machine Detected.\n\nTo prevent license misuse and cloning, this terminal is restricted to running on physical systems only.';
      }
    } catch (_) {}

    final currentDeviceId = await DeviceUtils.getDeviceId();
    try {
      await _authRepository.bindHardwareId(
        profile.uid,
        currentDeviceId,
        isWindows: DeviceUtils.isPc(),
        isMobile: DeviceUtils.isMobile(),
      );
    } catch (_) {}

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
        
        final bool isEmailVerified = await _authRepository.isEmailVerified().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );

        final UserProfile? profile = await _authRepository.getCurrentUserProfile().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        
        if (!isEmailVerified) {
          await _authRepository.signOut();
          state = const AuthState(status: AuthStatus.unauthenticated);
          return;
        }

        // Step 2: Set admin mode and device access mode BEFORE checking session
        // This ensures admin bypasses single-device session enforcement
        if (profile != null) {
          if (profile.isAdmin) {
            _authRepository.setAdminMode(true);
          }
          _authRepository.setAllowDualDevice(profile.allowDualDevice);
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
          if (profile != null && !kIsWeb) {
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
          _authRepository.updateDeviceInfo().catchError((_) => null);
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
    debugPrint("AUTH_NOTIFIER.signIn: Setting state to loading...");
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      debugPrint("AUTH_NOTIFIER.signIn: Calling _authRepository.signIn...");
      final sessionMessage = await _authRepository.signIn(email, password);
      debugPrint("AUTH_NOTIFIER.signIn: _authRepository.signIn succeeded! sessionMessage: $sessionMessage");
      
      UserProfile? profile;
      try {
        debugPrint("AUTH_NOTIFIER.signIn: Fetching user profile...");
        profile = await _authRepository.getCurrentUserProfile();
        debugPrint("AUTH_NOTIFIER.signIn: User profile fetched: ${profile?.email}, isApproved: ${profile?.isApproved}");
      } catch (e) {
        debugPrint('AuthNotifier: getCurrentUserProfile error: $e');
      }

      if (profile == null) {
        debugPrint("AUTH_NOTIFIER.signIn: Profile was null, fallback creation...");
        final currentUser = _authRepository.getCurrentUser();
        if (currentUser != null || kIsWeb) {
          final isMaster = AppConstants.isMasterAdmin(email);
          profile = UserProfile(
            uid: currentUser?.uid.toString() ?? _authRepository.getCurrentUserProfile().toString(),
            role: isMaster ? UserRole.admin : UserRole.viewer,
            email: currentUser?.email?.toString() ?? email,
            phoneNumber: currentUser?.phoneNumber?.toString(),
            isApproved: isMaster ? true : false,
            createdAt: DateTime.now(),
          );
        } else {
          throw AuthException('Failed to load user profile. Please check connection.');
        }
      }

      // Set admin mode and device access mode for ongoing session checks
      if (profile.isAdmin) {
        _authRepository.setAdminMode(true);
      }
      _authRepository.setAllowDualDevice(profile.allowDualDevice);
      
      if (!kIsWeb && !profile.isApproved) {
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
        debugPrint("AUTH_NOTIFIER.signIn: Access check failed: $accessError");
        await _authRepository.signOut();
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: accessError,
        );
        return accessError;
      }

      // Check hardware lock (One User, One System)
      if (!kIsWeb) {
        final hwError = await _checkHardwareLock(profile);
        if (hwError != null) {
          await _authRepository.signOut();
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            error: hwError,
          );
          return hwError;
        }
      }

      debugPrint("AUTH_NOTIFIER.signIn: Setting state to authenticated!");
      state = AuthState(
        user: profile,
        status: AuthStatus.authenticated,
      );
      try {
        _startLastSeenTimer();
      } catch (_) {}
      try {
        _authRepository.updateDeviceInfo().catchError((_) => null);
      } catch (_) {}
      return sessionMessage;
    } catch (e, st) {
      debugPrint("AUTH_NOTIFIER.signIn ERROR: $e");
      debugPrint("AUTH_NOTIFIER.signIn STACKTRACE: $st");
      String cleanError;
      if (e is AuthException) {
        cleanError = e.message;
      } else {
        cleanError = e.toString();
        if (cleanError.contains('TypeError') || cleanError.contains('minified:') || cleanError.contains('subtype of') || cleanError.contains('Instance of')) {
          cleanError = 'Invalid email or password. Please verify credentials.';
        } else {
          cleanError = cleanError.replaceAll(RegExp(r'\[.*?\]'), '').replaceAll('Exception:', '').trim();
        }
      }
      state = state.copyWith(
        status: AuthStatus.error,
        error: cleanError,
      );
      throw AuthException(cleanError);
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
      String cleanError;
      if (e is AuthException) {
        cleanError = e.message;
      } else {
        cleanError = e.toString();
        if (cleanError.contains('TypeError') || cleanError.contains('minified:') || cleanError.contains('subtype of') || cleanError.contains('Instance of')) {
          cleanError = 'Registration failed. Please verify all details.';
        } else {
          cleanError = cleanError.replaceAll(RegExp(r'\[.*?\]'), '').replaceAll('Exception:', '').trim();
        }
      }
      state = state.copyWith(
        status: AuthStatus.error,
        error: cleanError,
      );
      throw AuthException(cleanError);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _authRepository.sendPasswordResetEmail(email);
    } catch (e) {
      String cleanError;
      if (e is AuthException) {
        cleanError = e.message;
      } else {
        cleanError = e.toString();
        if (cleanError.contains('TypeError') || cleanError.contains('minified:') || cleanError.contains('subtype of') || cleanError.contains('Instance of')) {
          cleanError = 'Password reset failed. Please check your email.';
        } else {
          cleanError = cleanError.replaceAll(RegExp(r'\[.*?\]'), '').replaceAll('Exception:', '').trim();
        }
      }
      state = state.copyWith(
        status: AuthStatus.error,
        error: cleanError,
      );
      throw AuthException(cleanError);
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
              _authRepository.setAllowDualDevice(profile.allowDualDevice);
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

final authDataSourceProvider = Provider<AuthenticationDataSource>((ref) {
  return AuthenticationDataSource();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    authDataSource: ref.watch(authDataSourceProvider),
  );
});

final authNotifierProvider = Provider<AuthNotifier>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return ref.watch(authNotifierProvider);
});
