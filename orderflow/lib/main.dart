import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';
import 'core/services/notification_service.dart';
import 'core/services/permission_service.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/profile_screen.dart';
import 'package:screen_secure/screen_secure.dart';
import 'core/services/audio_service.dart';
import 'firebase_options.dart';
import 'presentation/screens/chart_screen.dart';
import 'presentation/widgets/futuristic_radar_loader.dart';
import 'data/datasources/local_cache_datasource.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Basic error logging
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint("❌ FlutterError: ${details.exception}");
  };

  runApp(
    const ProviderScope(
      child: OrderflowApp(),
    ),
  );
}

class OrderflowApp extends StatelessWidget {
  const OrderflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BIG SHOT Orderflow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const InitializationWrapper(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/chart': (context) => const ChartScreen(),
        '/profile': (context) => const ProfileScreen(),
      },
    );
  }
}

class InitializationWrapper extends StatefulWidget {
  const InitializationWrapper({super.key});

  @override
  State<InitializationWrapper> createState() => _InitializationWrapperState();
}

class _InitializationWrapperState extends State<InitializationWrapper> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    debugPrint("🚀 Starting BIG SHOT Initialization...");
    
    // 1. Firebase (with timeout)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 12));
      debugPrint("✅ Firebase Ready");
    } catch (e) {
      debugPrint("⚠️ Firebase Init Error: $e");
    }

    // 2. Core Services
    try {
      await Hive.initFlutter().timeout(const Duration(seconds: 5));
      debugPrint("✅ Hive Ready");
    } catch (e) {
      debugPrint("⚠️ Hive Init Error: $e");
    }

    try {
      // Initialize core services with individual error handling to prevent startup hangs
      await Future.wait([
        NotificationService.initialize()
            .timeout(const Duration(seconds: 10))
            .catchError((e) => debugPrint('❌ NotificationService Init Failed: $e')),
        AudioService.initialize()
            .timeout(const Duration(seconds: 5))
            .catchError((e) => debugPrint('❌ AudioService Init Failed: $e')),
        PermissionService.requestAllPermissions()
            .timeout(const Duration(seconds: 8))
            .catchError((e) => debugPrint('❌ PermissionService Init Failed: $e')),
        LocalCacheDataSource().initialize()
            .timeout(const Duration(seconds: 5))
            .catchError((e) => debugPrint('❌ LocalCache Init Failed: $e')),
      ]);

      if (kDebugMode) {
        debugPrint('✅ Services Ready');
      }
    } catch (e) {
      // Fallback for any catastrophic global failure
      debugPrint('⚠️ Critical Initialization Error (Bypassing): $e');
    }

    // 3. Security (Mobile only)
    final bool isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile && !kDebugMode) {
      try {
        // Disable screenshots/screen recording blocking by default
        await ScreenSecure.init(screenshotBlock: false, screenRecordBlock: false)
            .timeout(const Duration(seconds: 3));
      } on MissingPluginException catch (e) {
        debugPrint("⚠️ Security Plugin Error (Missing Implementation): $e");
      } catch (e) {
        debugPrint("⚠️ Security Plugin Error: $e");
      }
    }


    debugPrint("🏁 Initialization Complete");
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return _ErrorDisplay(error: snapshot.error.toString());
          }
          return const SplashScreen(); // SplashScreen handles routing to login/chart
        }
        // Show a futuristic cyber radar loading screen while bootstrapping services
        return const Scaffold(
          backgroundColor: Color(0xFF060B12),
          body: Center(
            child: FuturisticRadarLoader(
              size: 140,
              statusText: 'BOOTSTRAPPING QUANTUM TERMINAL...',
            ),
          ),
        );
      },
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  final String error;
  const _ErrorDisplay({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B12),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
              const SizedBox(height: 24),
              const Text(
                'SYSTEM INITIALIZATION FAILED',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // In a real app, we might use a reload trigger here
                  debugPrint("Retry clicked");
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
