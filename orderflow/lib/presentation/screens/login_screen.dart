import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import 'chart_screen.dart';

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

  void _switchMode(AuthMode mode) {
    HapticFeedback.lightImpact();
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
            final sessionMessage = await ref.read(authProvider.notifier).signIn(email, password);
            if (mounted) {
              if (sessionMessage != null && sessionMessage != 'PENDING_APPROVAL') {
                _showSnackBar(sessionMessage, isSuccess: true);
              }
              if (ref.read(authProvider).isAuthenticated) {
                _navigateToChart();
              }
            }
          } catch (e) {
            debugPrint("LOGIN SUBMIT ERROR: $e");
            if (mounted) {
              final clean = e.toString().replaceAll(RegExp(r'\[.*?\]'), '').replaceAll('minified:', '').trim();
              _showSnackBar(clean.isNotEmpty ? clean : 'Invalid credentials. Please try again.');
            }
          }
          break;

        case AuthMode.register:
          final name = _nameController.text.trim();
          final phone = _phoneController.text.trim();
          try {
            final verificationSent = await ref.read(authProvider.notifier).register(
              email: email,
              password: password,
              name: name,
              phoneNumber: phone,
            );
            if (verificationSent) {
              _showSnackBar('Verification email sent to $email! Please verify to login.', isSuccess: true);
              _switchMode(AuthMode.login);
            }
          } catch (e) {
            debugPrint("REGISTER SUBMIT ERROR: $e");
            if (mounted) {
              final clean = _sanitizeError(e.toString());
              _showSnackBar(clean.isNotEmpty ? clean : 'Registration failed. Please try again.');
            }
          }
          break;

        case AuthMode.forgotPassword:
          try {
            await ref.read(authProvider.notifier).sendPasswordResetEmail(email);
            _showSnackBar('Password reset email sent to $email! Check inbox & spam.', isSuccess: true);
            _switchMode(AuthMode.login);
          } catch (e) {
            _showSnackBar(_sanitizeError(e.toString()));
          }
          break;
      }
    } catch (e) {
      _showSnackBar(_sanitizeError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _sanitizeError(String error) {
    if (error.contains('TypeError') || error.contains('minified:') || error.contains('subtype of')) {
      return 'Authentication service error. Please try again.';
    }
    return error.replaceAll(RegExp(r'\[.*?\]'), '').replaceAll('minified:', '').trim();
  }

  void _navigateToChart() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/chart', (route) => false);
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

  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
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

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryCyan, AppTheme.accentPurple],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryCyan.withValues(alpha: 0.3),
            blurRadius: 15,
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
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    buttonText,
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
    );
  }@override
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
                SizedBox(height: 24 * scaleFactor),
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
              isLogin || isForgotPassword ? AuthMode.register : AuthMode.login),
          child: Text(
            isForgotPassword ? 'SIGN UP' : (isLogin ? 'SIGN UP' : 'LOGIN'),
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
