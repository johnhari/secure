import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';


class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize({bool isIndexOnly = false}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      debugPrint('NotificationService: Skipping initialization for Windows');
      return;
    }

    // 1. Request permissions with safety check
    try {
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
        NotificationSettings settings = await _messaging.requestPermission(
          alert: true,
          sound: true,
          badge: true,
        ).timeout(const Duration(seconds: 5));
        
        if (kDebugMode) {
          print('User granted permission: ${settings.authorizationStatus}');
        }
      }
    } catch (e) {
      debugPrint('NotificationService: Permission request failed: $e');
    }

    // 2. Save token and subscribe to topics
    await saveTokenToFirestore();

    if (kIsWeb) {
      return; 
    }

    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      debugPrint('NotificationService: Skipping mobile setup for ${defaultTargetPlatform.name}');
      return;
    }

    // 3. Configure local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    // Create Android notification channel if running on Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'heavy_activity_alerts', // id
        'Heavy Activity Alerts', // title
        description: 'Notifications for heavy buying or selling activity.', // description
        importance: Importance.max,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // 4. Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;

      // Skip local notification in foreground for orderflow updates 
      // as they are handled by ChartScreen UI (SnackBars/Audio)
      if (message.data['type'] == 'orderflow_update') {
        if (kDebugMode) {
          print('[FCM] Foreground orderflow update received, skipping local notification show.');
        }
        return;
      }

      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'heavy_activity_alerts',
              'Heavy Activity Alerts',
              channelDescription: 'Notifications for heavy buying or selling activity.',
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
            macOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
      }
    });

    // 5. Save token and subscribe to topics
    await saveTokenToFirestore();
    
    if (!kIsWeb) {
      // Subscribe only to allowed instrument topics based on subscription type
      final List<String> allowedTopics = isIndexOnly
          ? ['alerts_nifty50', 'alerts_banknifty', 'alerts_finnifty', 'alerts_sensex']
          : AppConstants.instruments
              .map((i) => 'alerts_${i.toLowerCase()}')
              .toList();

      for (final topic in allowedTopics) {
        try {
          await _messaging.subscribeToTopic(topic);
        } catch (e) {
          debugPrint('Error subscribing to topic $topic: $e');
        }
      }
      
      try {
        await _messaging.subscribeToTopic('global_alerts');
      } catch (e) {
        debugPrint('Error subscribing to global_alerts: $e');
      }
    }

  }

  static Future<void> saveTokenToFirestore() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return;
    }
    try {
      String? token;
      
      // Use a strict timeout for token retrieval to prevent splash screen hangs
      if (kIsWeb) {
        token = await _messaging.getToken(
          vapidKey: 'BPHy_XW1S4FhP6F-v0N7i7jU5N3fJ5-8R7D8e7w9q0p1A2B3C4D5E6F7G8H9I0J'
        ).timeout(const Duration(seconds: 5));
      } else {
        token = await _messaging.getToken().timeout(const Duration(seconds: 5));
      }
      
      final user = FirebaseAuth.instance.currentUser;
      
      if (token != null && user != null) {
        final platformStr = kIsWeb
            ? 'web'
            : (defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : (defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : (defaultTargetPlatform == TargetPlatform.macOS ? 'macos' : 'windows')));

        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
          'platform': platformStr,
        }, SetOptions(merge: true)).catchError((e) => print("Firestore token save failed: $e"));
        
        if (kDebugMode) {
          print("FCM Token saved: $token");
        }
      }
    } catch (e) {
      print("NotificationService: FCM token error (timed out or not configured): $e");
    }
  }

  static final Set<String> _shownWindowsNotificationKeys = {};

  /// Encode string to Base64 UTF-16LE for PowerShell -EncodedCommand
  static String _base64EncodeUtf16Le(String text) {
    final List<int> bytes = [];
    for (int i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      bytes.add(codeUnit & 0xFF);
      bytes.add((codeUnit >> 8) & 0xFF);
    }
    return base64.encode(bytes);
  }

  /// Dispatch native Windows OS Toast Notification
  static Future<void> _dispatchWindowsToast(String title, String body) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      final sanitizedTitle = title.replaceAll("'", "''");
      final sanitizedBody = body.replaceAll("'", "''");

      final psScript = '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
\$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$nodes = \$xml.GetElementsByTagName('text')
\$nodes.Item(0).AppendChild(\$xml.CreateTextNode('$sanitizedTitle')) | Out-Null
\$nodes.Item(1).AppendChild(\$xml.CreateTextNode('$sanitizedBody')) | Out-Null
\$toast = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]::new(\$xml)
try {
  \$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe')
  \$notifier.Show(\$toast)
} catch {
  try {
    \$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Orderflow Analyzer')
    \$notifier.Show(\$toast)
  } catch {}
}
''';

      final encoded = _base64EncodeUtf16Le(psScript);
      await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded]);
    } catch (e) {
      debugPrint('Windows Notification Error: $e');
    }
  }

  /// Shows a desktop notification displaying Stock/Index name and Volume (Windows & macOS)
  static Future<void> showWindowsStockNotification({
    required String symbol,
    required String alertType,
    required int volumeCount,
    double? price,
    int? buyVolume,
    int? sellVolume,
    String? notificationId,
    int? candleTime,
  }) async {
    if (kIsWeb) return;

    if (notificationId != null) {
      if (_shownWindowsNotificationKeys.contains(notificationId)) return;
      _shownWindowsNotificationKeys.add(notificationId);
      if (_shownWindowsNotificationKeys.length > 500) {
        _shownWindowsNotificationKeys.clear();
      }
    }

    final volFormatted = volumeCount >= 1000
        ? '${(volumeCount / 1000).toStringAsFixed(1)}K'
        : '$volumeCount';
    
    String timeLabel = '';
    if (candleTime != null && candleTime > 0) {
      final actualMs = candleTime < 10000000000 ? candleTime * 1000 : candleTime;
      final dt = DateTime.fromMillisecondsSinceEpoch(actualMs);
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      timeLabel = ' [$hour:$minute]';
    }

    final title = '📊 $symbol$timeLabel - $alertType';
    
    String body = 'Volume: $volFormatted';
    if (buyVolume != null && sellVolume != null && (buyVolume > 0 || sellVolume > 0)) {
      final buyStr = buyVolume >= 1000 ? '${(buyVolume / 1000).toStringAsFixed(1)}K' : '$buyVolume';
      final sellStr = sellVolume >= 1000 ? '${(sellVolume / 1000).toStringAsFixed(1)}K' : '$sellVolume';
      body = 'Buy Vol: $buyStr | Sell Vol: $sellStr';
    }
    if (price != null && price > 0) {
      body += ' @ ₹${price.toStringAsFixed(2)}';
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _dispatchWindowsToast(title, body);
    } else {
      await showLocalNotification(title: title, body: body);
    }
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await _dispatchWindowsToast(title, body);
      return;
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'heavy_activity_alerts',
      'Heavy Activity Alerts',
      channelDescription: 'Notifications for heavy buying or selling activity.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails darwinPlatformSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: darwinPlatformSpecifics,
      macOS: darwinPlatformSpecifics,
    );
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }
}
