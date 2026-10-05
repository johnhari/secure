import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import '../providers/auth_provider.dart';
import '../../data/datasources/authentication_datasource.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  AuthMode _authMode = AuthMode.login;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
    _loadSavedCredentials();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentError = ref.read(authProvider).error;
      if (currentError != null) {
        if (currentError == 'PENDING_APPROVAL') {
          _showPendingApprovalDialog();
        } else if (currentError.contains('another device') || currentError.startsWith('DUPLICATE_SESSION')) {
          _showSessionTerminatedDialog(currentError);
        }
      }
    });
  }

  /// Load saved credentials from SharedPreferences
  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email') ?? '';
      final savedPassword = prefs.getString('saved_password') ?? '';
      if (savedEmail.isNotEmpty && mounted) {
        setState(() {
          _emailController.text = savedEmail;
          if (savedPassword.isNotEmpty) {
            _passwordController.text = savedPassword;
          }
        });
      }
    } catch (e) {
      debugPrint('Warning: Could not load saved credentials: $e');
    }
  }

  /// Save credentials to SharedPreferences after successful login
  Future<void> _saveCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email);
      await prefs.setString('saved_password', password);
      debugPrint('Credentials saved for $email');
    } catch (e) {
      debugPrint('Warning: Could not save credentials: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode, {bool clearSnackBar = true}) {
    HapticFeedback.lightImpact();
    if (clearSnackBar) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
    }
    setState(() {
      _authMode = mode;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text.trim();

      switch (_authMode) {
        case AuthMode.login:
          try {
            debugPrint("LOGIN SUBMIT: Reading authNotifierProvider...");
            final authNotifier = ref.read(authNotifierProvider);
            debugPrint("LOGIN SUBMIT: Calling authNotifier.signIn...");
            final sessionMessage = await authNotifier.signIn(email, password);
            debugPrint("LOGIN SUBMIT: signIn returned: $sessionMessage");
            if (mounted) {
              if (sessionMessage != null && sessionMessage != 'PENDING_APPROVAL') {
                if (sessionMessage.startsWith('DUPLICATE_SESSION_OVERWRITE:') || sessionMessage.contains('logged in on')) {
                  final prevDev = sessionMessage.contains(':')
                      ? sessionMessage.split(':').last.trim()
                      : 'another device';
                  await _showSessionTakeoverNoticeDialog(prevDev);
                } else {
                  _showSnackBar(sessionMessage, isSuccess: true);
                }
              }
              if (ref.read(authProvider).isAuthenticated) {
                debugPrint("LOGIN SUBMIT: Authenticated! Saving credentials and navigating...");
                // Save credentials on successful login
                _saveCredentials(email, password);
                _navigateToChart();
              }
            }
          } catch (e, st) {
            debugPrint("LOGIN SUBMIT ERROR: $e");
            debugPrint("LOGIN SUBMIT STACKTRACE: $st");
            if (mounted) {
              final clean = _sanitizeError(e, mode: AuthMode.login);
              _showSnackBar(clean.isNotEmpty ? clean : 'Invalid credentials. Please try again.');
            }
          }
          break;

        case AuthMode.register:
          final name = _nameController.text.trim();
          final phone = _phoneController.text.trim();
          try {
            final authNotifier = ref.read(authNotifierProvider);
            final verificationSent = await authNotifier.register(
              email: email,
              password: password,
              name: name,
              phoneNumber: phone,
            );
            if (verificationSent && mounted) {
              _switchMode(AuthMode.login, clearSnackBar: false);
              _showVerificationSentDialog(email);
              _showSnackBar('Verification email sent to $email! Please verify to login.', isSuccess: true);
            }
          } catch (e) {
            debugPrint("REGISTER SUBMIT ERROR: $e");
            if (mounted) {
              final errStr = e.toString().toLowerCase();
              // Only show "already sent" dialog for the specific email-already-in-use error
              if (errStr.contains('already-in-use') || errStr.contains('email-already') || errStr.contains('email_exists')) {
                _showVerificationAlreadySentDialog(email);
                _showSnackBar('Verification link already sent to your mail ID ($email)! Check inbox & spam.');
              } else {
                final clean = _sanitizeError(e, mode: AuthMode.register);
                _showSnackBar(clean.isNotEmpty ? clean : 'Registration failed. Please try again.');
              }
            }
          }
          break;

        case AuthMode.forgotPassword:
          try {
            final authNotifier = ref.read(authNotifierProvider);
            await authNotifier.sendPasswordResetEmail(email);
            if (mounted) {
              _switchMode(AuthMode.login, clearSnackBar: false);
              _showSnackBar('Password reset email sent to $email! Check inbox & spam.', isSuccess: true);
            }
          } catch (e) {
            if (mounted) {
              _showSnackBar(_sanitizeError(e, mode: AuthMode.forgotPassword));
            }
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(_sanitizeError(e, mode: _authMode));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _sanitizeError(dynamic error, {AuthMode mode = AuthMode.login}) {
    String errorStr;
    if (error is AuthException) {
      errorStr = error.message;
    } else {
      errorStr = error?.toString() ?? '';
    }

    final lower = errorStr.toLowerCase();
    if (lower.contains('another device') || lower.contains('duplicate_session')) {
      return errorStr.replaceFirst('DUPLICATE_SESSION:', '').trim();
    }
    if (lower.contains('already-in-use') || lower.contains('already in use') || lower.contains('already registered') || lower.contains('email_exists') || lower.contains('already link') || lower.contains('link already sent')) {
      return 'Verification link already sent to your mail ID. Please check your inbox & spam folder to verify.';
    }
    if (lower.contains('invalid-email') || lower.contains('invalid_email')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('weak-password') || lower.contains('weak password') || lower.contains('password must be') || lower.contains('weak_password')) {
      return 'Password is too weak. Please use at least 6 characters.';
    }
    if (lower.contains('user-not-found') || lower.contains('no account found') || lower.contains('no user record')) {
      return 'No account found with this email.';
    }
    if (lower.contains('wrong-password') || lower.contains('incorrect password') || lower.contains('invalid password')) {
      return 'Incorrect password. Please try again.';
    }
    if (lower.contains('invalid-credential') || lower.contains('invalid credential') || lower.contains('invalid login')) {
      return 'Invalid email or password. Please verify credentials.';
    }

    final cleaned = errorStr
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll('Exception:', '')
        .replaceAll("Instance of 'AuthException'", '')
        .replaceAll("Instance of 'NetworkException'", '')
        .replaceAll("Instance of", '')
        .replaceAll('TypeError:', '')
        .trim();

    if (cleaned.isNotEmpty &&
        !cleaned.contains('TypeError') &&
        !cleaned.contains('minified:') &&
        !cleaned.contains('subtype of') &&
        !cleaned.contains('Null check operator')) {
      return cleaned;
    }

    if (mode == AuthMode.register) {
      return 'Registration failed. Please check your details and try again.';
    } else if (mode == AuthMode.forgotPassword) {
      return 'Password reset failed. Please check your email.';
    }
    return 'Invalid email or password. Please verify credentials.';
  }

  void _navigateToChart() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/chart', (route) => false);
  }

  void _showVerificationAlreadySentDialog(String email) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.primaryCyan.withValues(alpha: 0.3), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read_rounded, color: AppTheme.primaryCyan, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verification Link Sent',
                style: TextStyle(
                  color: AppTheme.primaryCyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A verification link has already been sent to your mail ID:',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                email,
                style: const TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Please check your inbox (and spam folder), then click the link inside to verify your account before logging in.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _switchMode(AuthMode.login);
            },
            child: const Text(
              'GO TO LOGIN',
              style: TextStyle(
                color: AppTheme.primaryCyan,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVerificationSentDialog(String email) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.primaryCyan.withValues(alpha: 0.3), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read_rounded, color: AppTheme.primaryCyan, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verification Sent',
                style: TextStyle(
                  color: AppTheme.primaryCyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your account has been created! A verification email has been sent to:',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                email,
                style: const TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Please check your inbox (and spam folder), then click the link inside to verify your email before logging in.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'UNDERSTOOD',
              style: TextStyle(
                color: AppTheme.primaryCyan,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPendingApprovalDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.goldColor.withValues(alpha: 0.3), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.hourglass_empty, color: AppTheme.goldColor, size: 24),
            SizedBox(width: 12),
            Text(
              'Pending Approval',
              style: TextStyle(
                color: AppTheme.goldColor,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Text(
          'Your account has been successfully created and verified.\n\nHowever, this is an exclusive terminal. Your access requires manual approval by the Administrator before you can log in.\n\nPlease contact the Admin to activate your account.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'UNDERSTOOD',
              style: TextStyle(
                color: AppTheme.primaryCyan,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Warning dialog shown on the OLD device when an active session is terminated due to login on another device
  void _showSessionTerminatedDialog(String errorMsg) {
    if (!mounted) return;
    final displayMsg = errorMsg.replaceAll('DUPLICATE_SESSION:', '').trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFF5252), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.devices_other_rounded, color: Color(0xFFFF5252), size: 26),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Session Terminated',
                style: TextStyle(
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.25)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Simultaneous multi-device access is restricted.',
                      style: TextStyle(
                        color: Color(0xFFFF5252),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              displayMsg.isNotEmpty
                  ? displayMsg
                  : 'Your account was just logged in from another device or browser session.',
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '🛡️ Device Security Policy:\nTo ensure algorithmic data protection and strict license compliance, only authorized sessions (up to 1 PC and 1 Mobile) are permitted. This previous session has been closed.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'If you did not perform this login, please change your password immediately.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'ACKNOWLEDGE & RE-LOGIN',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  /// Warning dialog shown on the NEW device when user logs in and replaces an active session on another device
  Future<void> _showSessionTakeoverNoticeDialog(String prevDevice) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFFB300), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded, color: Color(0xFFFFB300), size: 26),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Previous Session Logged Out',
                style: TextStyle(
                  color: Color(0xFFFFB300),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFFB300), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Session on $prevDevice terminated.',
                      style: const TextStyle(
                        color: Color(0xFFFFB300),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your account has successfully authorized this device. In compliance with our Device Security Policy, the active session on $prevDevice was terminated.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'PROCEED TO TERMINAL',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    final clean = _sanitizeError(message, mode: _authMode);
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          clean,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isSuccess ? const Color(0xFF00E676) : const Color(0xFFFF1744),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSubmitButton() {
    String buttonText;
    switch (_authMode) {
      case AuthMode.login:
        buttonText = 'AUTHORIZE ACCESS';
        break;
      case AuthMode.register:
        buttonText = 'CREATE ACCOUNT';
        break;
      case AuthMode.forgotPassword:
        buttonText = 'REQUEST RESET';
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isLoading
              ? [AppTheme.primaryCyan.withValues(alpha: 0.7), AppTheme.accentPurple.withValues(alpha: 0.7)]
              : [AppTheme.primaryCyan, AppTheme.accentPurple],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isLoading
                ? AppTheme.primaryCyan.withValues(alpha: 0.5)
                : AppTheme.primaryCyan.withValues(alpha: 0.3),
            blurRadius: _isLoading ? 25 : 15,
            spreadRadius: _isLoading ? 2 : 0,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _submit,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child: _isLoading
                  ? Row(
                      key: const ValueKey('loading'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _authMode == AuthMode.register
                              ? 'CREATING ACCOUNT...'
                              : (_authMode == AuthMode.login ? 'AUTHORIZING...' : 'SENDING...'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      buttonText,
                      key: ValueKey('text_$buttonText'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
@override
  Widget build(BuildContext context) {
    // Responsive Scaling Logic
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scaleFactor = (screenWidth / 390).clamp(0.8, 1.2);

    ref.listen(authProvider, (previous, next) {
      if (next.isAuthenticated) {
        _navigateToChart();
      } else if (next.error != null && next.status == AuthStatus.unauthenticated) {
        if (next.error == 'PENDING_APPROVAL') {
          _showPendingApprovalDialog();
        } else if (next.error!.contains('another device') || next.error!.startsWith('DUPLICATE_SESSION')) {
          _showSessionTerminatedDialog(next.error!);
        } else {
          _showSnackBar(next.error!);
        }
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: Stack(
        children: [
          // Background subtle glows
          Positioned(
            top: -50,
            right: -50,
            child: _buildGlowCircle(AppTheme.primaryCyan.withValues(alpha: 0.15), 250 * scaleFactor),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: _buildGlowCircle(AppTheme.accentPurple.withValues(alpha: 0.1), 300 * scaleFactor),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24 * scaleFactor),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: _buildGlassCard(scaleFactor),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildGlassCard(double scaleFactor) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: EdgeInsets.all(28 * scaleFactor),
      decoration: AppTheme.glassDecoration(
        opacity: 0.08,
        borderRadius: BorderRadius.circular(24 * scaleFactor),
      ),
      child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLogo(scaleFactor),
                SizedBox(height: 28 * scaleFactor),
                _buildTitle(scaleFactor),
                SizedBox(height: 32 * scaleFactor),
                // Name field (only for registration)
                if (_authMode == AuthMode.register) ...[
                  _buildNameField(),
                  SizedBox(height: 16 * scaleFactor),
                ],
                _buildEmailField(),
                // Phone field (only for registration)
                if (_authMode == AuthMode.register) ...[
                  SizedBox(height: 16 * scaleFactor),
                  _buildPhoneField(),
                ],
                if (_authMode != AuthMode.forgotPassword) ...[
                  SizedBox(height: 16 * scaleFactor),
                  _buildPasswordField(),
                ],
                if (_authMode == AuthMode.login) ...[
                  SizedBox(height: 14 * scaleFactor),
                  _buildSingleDevicePolicyNotice(scaleFactor),
                ],
                SizedBox(height: 20 * scaleFactor),
                _buildSubmitButton(),
                SizedBox(height: 20 * scaleFactor),
                _buildModeToggle(),
                if (_authMode == AuthMode.login) ...[
                  SizedBox(height: 12 * scaleFactor),
                  _buildForgotPasswordLink(),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildSingleDevicePolicyNotice(double scaleFactor) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * scaleFactor, vertical: 8 * scaleFactor),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10 * scaleFactor),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: const Color(0xFF00E5FF),
            size: 16 * scaleFactor,
          ),
          SizedBox(width: 8 * scaleFactor),
          Expanded(
            child: Text(
              'Device Security Policy: Authorized for 1 PC + 1 Mobile access. Duplicate logins on the same device type will terminate previous sessions.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 10.5 * scaleFactor,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(double scaleFactor) {
    return Container(
      width: 80 * scaleFactor,
      height: 80 * scaleFactor,
      padding: EdgeInsets.all(12 * scaleFactor),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryCyan.withValues(alpha: 0.2),
            blurRadius: 15 * scaleFactor,
            spreadRadius: 2 * scaleFactor,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40 * scaleFactor),
        child: Image.asset(
          'assets/images/logo_bigshot.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildTitle(double scaleFactor) {
    String title;
    String subtitle;

    switch (_authMode) {
      case AuthMode.login:
        title = 'PREMIUM ACCESS';
        subtitle = 'Login to the Institutional Dashboard';
        break;
      case AuthMode.register:
        title = 'JOIN THE ELITE';
        subtitle = 'Create your secure trading account';
        break;
      case AuthMode.forgotPassword:
        title = 'RECOVER ACCOUNT';
        subtitle = 'Secure password restoration';
        break;
    }

    return Column(
      children: [
        Text(
          title,
          style: AppTheme.headingStyle.copyWith(fontSize: 22 * scaleFactor, color: AppTheme.primaryCyan),
        ),
        SizedBox(height: 6 * scaleFactor),
        Text(
          subtitle,
          style: AppTheme.subHeadingStyle.copyWith(fontSize: 12 * scaleFactor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return _buildTextField(
      controller: _nameController,
      label: 'Full Name',
      hint: 'Enter your full name',
      icon: Icons.person_outline,
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.words,
      validator: (value) {
        if (_authMode == AuthMode.register) {
          if (value == null || value.isEmpty) return 'Name is required';
          if (value.length < 2) return 'Enter a valid name';
        }
        return null;
      },
    );
  }

  Widget _buildEmailField() {
    return _buildTextField(
      controller: _emailController,
      label: 'Email',
      hint: 'Enter your email',
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Email is required';
        if (!value.contains('@') || !value.contains('.')) {
          return 'Enter a valid email';
        }
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return _buildTextField(
      controller: _phoneController,
      label: 'Phone Number',
      hint: 'Enter your phone number',
      icon: Icons.phone_outlined,
      keyboardType: TextInputType.phone,
      validator: (value) {
        if (_authMode == AuthMode.register) {
          if (value == null || value.isEmpty) return 'Phone number is required';
          if (value.length < 10) return 'Enter a valid phone number';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return _buildTextField(
      controller: _passwordController,
      label: 'Password',
      hint: 'Enter your password',
      icon: Icons.lock_outline,
      obscureText: _obscurePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility_off : Icons.visibility,
          color: Colors.white54,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Password is required';
        if (value.length < 6) return 'Minimum 6 characters';
        return null;
      },
      onFieldSubmitted: (_) => _submit(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      style: AppTheme.bodyStyle,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTheme.bodyStyle.copyWith(color: AppTheme.subTextColor),
        hintStyle: AppTheme.bodyStyle.copyWith(color: AppTheme.dimTextColor),
        prefixIcon: Icon(icon, color: AppTheme.primaryCyan, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryCyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTheme.bearColor.withValues(alpha: 0.5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.bearColor, width: 1.5),
        ),
        errorStyle: const TextStyle(color: AppTheme.bearColor),
      ),
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
    );
  }





  Widget _buildModeToggle() {
    final isLogin = _authMode == AuthMode.login;
    final isForgotPassword = _authMode == AuthMode.forgotPassword;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isForgotPassword
              ? 'Remember your password? '
              : (isLogin ? "DON'T HAVE AN ACCOUNT? " : 'ALREADY HAVE AN ACCOUNT? '),
          style: AppTheme.bodyStyle.copyWith(color: AppTheme.subTextColor, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: () => _switchMode(
              isLogin ? AuthMode.register : AuthMode.login),
          child: Text(
            isForgotPassword ? 'LOGIN' : (isLogin ? 'SIGN UP' : 'LOGIN'),
            style: const TextStyle(
              color: AppTheme.primaryCyan,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordLink() {
    return GestureDetector(
      onTap: () => _switchMode(AuthMode.forgotPassword),
      child: Text(
        'FORGOT PASSWORD?',
        style: AppTheme.bodyStyle.copyWith(
          color: AppTheme.dimTextColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

enum AuthMode { login, register, forgotPassword }
