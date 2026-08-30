import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RiskDisclosureScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const RiskDisclosureScreen({super.key, required this.onAccepted});

  @override
  State<RiskDisclosureScreen> createState() => _RiskDisclosureScreenState();
}

class _RiskDisclosureScreenState extends State<RiskDisclosureScreen> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Request focus on the next frame to ensure the widget tree is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive Scaling Logic
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scaleFactor = (screenWidth / 390).clamp(1.0, 1.5);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): widget.onAccepted,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): widget.onAccepted,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && 
             (event.logicalKey == LogicalKeyboardKey.enter || 
              event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
            widget.onAccepted();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0C0B),
          body: Stack(
            children: [
              // 1. Subtle Background Logo Watermark
              Positioned.fill(
                child: Opacity(
                  opacity: 0.03,
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo_bigshot.jpg',
                      width: 300 * scaleFactor,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              
              // 2. Main Content
              SafeArea(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.5,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF0A0C0B),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.0 * scaleFactor, 
                      vertical: 20.0 * scaleFactor
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: 40 * scaleFactor),
                        // Icon
                        Container(
                          padding: EdgeInsets.all(20 * scaleFactor),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyan.withValues(alpha: 0.2),
                                blurRadius: 20 * scaleFactor,
                                spreadRadius: 5 * scaleFactor,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Icon(Icons.assignment_outlined, size: 90 * scaleFactor, color: Colors.white70),
                              Container(
                                padding: EdgeInsets.all(4 * scaleFactor),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0A0C0B),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.warning, size: 34 * scaleFactor, color: Colors.cyanAccent),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24 * scaleFactor),
                        Text(
                          'Risk Disclosure on Derivatives',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22 * scaleFactor,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 32 * scaleFactor),
                        // Bullet points
                        Expanded(
                          child: ListView(
                            physics: const BouncingScrollPhysics(),
                            children: [
                              _buildBulletPoint('9 out of 10 individual traders in equity Futures and Options Segment, incurred net losses', scaleFactor),
                              _buildBulletPoint('On an average, loss makers registered net trading loss close to 50,000', scaleFactor),
                              _buildBulletPoint('Over and above the net trading losses incurred, loss makers expended an additional 28% of net trading losses as transaction costs', scaleFactor),
                              _buildBulletPoint('Those making net trading profits, incurred between 15% to 50% of such profits as transaction cost', scaleFactor),
                            ],
                          ),
                        ),
                        // Source
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: EdgeInsets.all(12 * scaleFactor),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(
                              'Source:\nSEBI study dated January 25, 2023 on "Analysis of Profit and Loss of Individual Traders dealing in equity Futures and Options (F&O) Segment", wherein Aggregate Level findings are based on annual Profit/Loss incurred by individual traders in equity F&O during FY 2021-22.',
                              style: TextStyle(
                                fontSize: 11 * scaleFactor,
                                color: Colors.white.withValues(alpha: 0.5),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 24 * scaleFactor),
                        // Continue button
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.cyan.withValues(alpha: 0.3),
                                  blurRadius: 15 * scaleFactor,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: widget.onAccepted,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyanAccent.shade700,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 20 * scaleFactor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'I understand, continue',
                                style: TextStyle(
                                  fontSize: 18 * scaleFactor,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 10 * scaleFactor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text, double scaleFactor) {
    return Padding(
      padding: EdgeInsets.only(bottom: 24.0 * scaleFactor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 6 * scaleFactor),
            width: 12 * scaleFactor,
            height: 12 * scaleFactor,
            decoration: BoxDecoration(
              color: Colors.cyanAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.5),
                  blurRadius: 6 * scaleFactor,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          SizedBox(width: 16 * scaleFactor),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16 * scaleFactor,
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
