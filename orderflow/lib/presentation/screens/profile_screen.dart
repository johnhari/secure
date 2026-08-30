import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../../domain/entities/user_profile.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    if (user != null) {
      _nameController.text = user.name ?? '';
      _phoneController.text = user.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    try {
      await ref.read(authProvider.notifier).updateProfile(
        name: _nameController.text,
        phoneNumber: _phoneController.text,
      );
      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppTheme.bullColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.unauthenticated) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      }
    });

    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        title: const Text(
          'USER PROFILE',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryCyan),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_circle_rounded, color: AppTheme.bullColor),
              onPressed: _updateProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(user),
            const SizedBox(height: 30),
            _buildInfoCard(
              title: 'Account Information',
              items: [
                _buildInfoItem('Display Name', _nameController, editable: _isEditing),
                _buildInfoItem('Phone Number', _phoneController, editable: _isEditing),
                _buildInfoItem('Email Address', TextEditingController(text: user.email), editable: false),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoCard(
              title: 'Membership Details',
              items: [
                _buildStaticItem('Role', user.isAdmin ? 'ADMINISTRATOR' : 'VIEWER', 
                  color: user.isAdmin ? AppTheme.goldColor : AppTheme.primaryCyan),
                _buildStaticItem('Status', user.isApproved ? 'APPROVED' : 'PENDING',
                  color: user.isApproved ? AppTheme.bullColor : AppTheme.bearColor),
                _buildStaticItem('Member Since', _formatDate(user.createdAt)),
                if (user.expiryDate != null)
                  _buildExpiryCountdown(user.expiryDate!),
              ],
            ),
            const SizedBox(height: 20),
            _buildSubscriptionCard(user),
            const SizedBox(height: 40),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(UserProfile user) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: Image.asset(
                'assets/images/logo_bigshot.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user.name ?? 'New User',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
          Text(
            user.isAdmin ? 'MASTER ACCESS' : 'STANDARD VIEWER',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: user.isAdmin ? AppTheme.goldColor : AppTheme.primaryCyan.withValues(alpha: 0.6),
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required List<Widget> items}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151917),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, TextEditingController controller, {required bool editable}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            enabled: editable,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              disabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryCyan)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryCyan, width: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        _buildMenuButton(
          title: 'Reset Password',
          icon: Icons.lock_reset_rounded,
          color: AppTheme.primaryCyan,
          onTap: () {
            ref.read(authProvider.notifier).sendPasswordResetEmail(ref.read(authProvider).user?.email ?? '');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Password reset email sent')),
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.bearColor.withValues(alpha: 0.1),
              foregroundColor: AppTheme.bearColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.bearColor, width: 1),
              ),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.power_settings_new_rounded),
                SizedBox(width: 12),
                Text('SECURE LOGOUT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.3), size: 14),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildExpiryCountdown(DateTime expiryDate) {
    final now = DateTime.now();
    final diff = expiryDate.difference(now);
    
    Color statusColor = AppTheme.primaryCyan;
    String label;
    
    if (now.isAfter(expiryDate) || diff.isNegative) {
      statusColor = AppTheme.bearColor;
      label = 'EXPIRED';
    } else {
      final days = diff.inDays;
      final hours = diff.inHours;
      final mins = diff.inMinutes;

      if (days >= 1) {
        label = '$days Days ${hours % 24} Hours Left';
        statusColor = days < 3 ? AppTheme.bearColor : (days < 7 ? Colors.orange : AppTheme.primaryCyan);
      } else if (hours >= 1) {
        label = '$hours Hours ${mins % 60} Mins Left';
        statusColor = AppTheme.bearColor;
      } else {
        label = '${mins.clamp(0, 59)} Mins Left';
        statusColor = AppTheme.bearColor;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Expires In',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(UserProfile user) {
    final expiryDate = user.expiryDate;
    
    final String balanceLabel;
    final Color balanceColor;
    
    if (expiryDate == null) {
      balanceLabel = 'PERMANENT ACCESS';
      balanceColor = AppTheme.bullColor;
    } else {
      final now = DateTime.now();
      if (now.isAfter(expiryDate)) {
        balanceLabel = 'Expired / No Active Balance';
        balanceColor = AppTheme.bearColor;
      } else {
        final diff = expiryDate.difference(now);
        if (diff.inDays >= 1) {
          balanceLabel = '${diff.inDays} Days Remaining';
        } else if (diff.inHours >= 1) {
          balanceLabel = '${diff.inHours} Hours Remaining';
        } else {
          balanceLabel = '${diff.inMinutes.clamp(0, 59)} Minutes Remaining';
        }
        balanceColor = AppTheme.bullColor;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151917),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUBSCRIPTION DETAILS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _buildStaticItem('Name', user.name ?? 'N/A'),
          _buildStaticItem('Phone Number', user.phoneNumber ?? 'N/A'),
          _buildStaticItem(
            'Subscription Balance', 
            balanceLabel, 
            color: balanceColor
          ),
          _buildStaticItem(
            'Expiry Date', 
            expiryDate != null ? _formatDate(expiryDate) : 'Permanent / Lifetime'
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white10),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _showPlanSelectionSheet(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryCyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment_rounded, color: Colors.black, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'PAY NEXT MONTH SUBSCRIPTION',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlanSelectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1110),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CHOOSE YOUR PLAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildPlanTile(
                  title: '1 Year Membership',
                  price: '₹25,000',
                  description: 'Indices + Stocks full access on Android & Desktop',
                  isPopular: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showPaymentOptionsSheet(25000.0, '1-Year Subscription');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanTile({
    required String title,
    required String price,
    required String description,
    bool isPopular = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF151917),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPopular ? AppTheme.primaryCyan.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
            width: isPopular ? 1.5 : 1.0,
          ),
          boxShadow: isPopular ? [
            BoxShadow(
              color: AppTheme.primaryCyan.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ] : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'POPULAR',
                            style: TextStyle(
                              color: AppTheme.primaryCyan,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              price,
              style: const TextStyle(
                color: AppTheme.primaryCyan,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentOptionsSheet(double amount, String planName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1110),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SELECT UPI PAYMENT APP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pay to: online.secure.payment@upi\nAmount: ₹${amount.toStringAsFixed(2)} ($planName)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _buildPaymentAppTile(
                  name: 'Google Pay',
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF4285F4),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUPI('gpay', amount, planName);
                  },
                ),
                const SizedBox(height: 12),
                _buildPaymentAppTile(
                  name: 'PhonePe',
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF5F259F),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUPI('phonepe', amount, planName);
                  },
                ),
                const SizedBox(height: 12),
                _buildPaymentAppTile(
                  name: 'Paytm',
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF00B9F1),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUPI('paytm', amount, planName);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentAppTile({
    required String name,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF151917),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.2),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUPI(String appName, double amount, String planName) async {
    final baseUri = 'pa=online.secure.payment@upi&pn=BIG%20SHOT%20Orderflow&cu=INR&am=${amount.toStringAsFixed(2)}&tn=${Uri.encodeComponent(planName)}';
    String upiUrl = '';
    
    switch (appName.toLowerCase()) {
      case 'gpay':
        upiUrl = 'upi://pay?$baseUri';
        break;
      case 'phonepe':
        upiUrl = 'phonepe://pay?$baseUri';
        break;
      case 'paytm':
        upiUrl = 'paytmmp://pay?$baseUri';
        break;
      default:
        upiUrl = 'upi://pay?$baseUri';
    }

    try {
      final uri = Uri.parse(upiUrl);
      // Attempt to launch directly without checking canLaunchUrl first 
      // (which is blocked by package visibility restrictions on some OS versions)
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // Fallback to standard upi:// scheme
        final genericUri = Uri.parse('upi://pay?$baseUri');
        final genericLaunched = await launchUrl(genericUri, mode: LaunchMode.externalApplication);
        if (!genericLaunched) {
          throw 'No compatible UPI apps responded';
        }
      }
    } catch (e) {
      // Fallback attempt: launch standard upi:// directly
      try {
        final genericUri = Uri.parse('upi://pay?$baseUri');
        final genericLaunched = await launchUrl(genericUri, mode: LaunchMode.externalApplication);
        if (!genericLaunched) {
          throw 'Could not launch standard UPI link';
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open payment app: $err'),
              backgroundColor: AppTheme.bearColor,
            ),
          );
        }
      }
    }
  }
}
