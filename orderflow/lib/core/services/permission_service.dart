import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  /// Request all necessary permissions for the app
  static Future<void> requestAllPermissions() async {
    if (kIsWeb) return;
    
    // Only request permissions on mobile platforms
    if (defaultTargetPlatform != TargetPlatform.android && 
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.notification,
        Permission.photos,
        Permission.videos,
        Permission.storage,
      ].request().timeout(const Duration(seconds: 5));

      if (kDebugMode) {
        statuses.forEach((permission, status) {
          print('Permission ${permission.toString()}: ${status.toString()}');
        });
      }
    } catch (e) {
      debugPrint('PermissionService: Request failed or timed out: $e');
    }
  }

  /// Request only media permissions
  static Future<void> requestMediaPermissions() async {
    if (kIsWeb) return;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.photos,
      Permission.videos,
      // For older Android versions
      Permission.storage,
    ].request();

    if (kDebugMode) {
      statuses.forEach((permission, status) {
        print('Permission ${permission.toString()}: ${status.toString()}');
      });
    }
  }

  /// Check if media permissions are granted
  static Future<bool> hasMediaPermissions() async {
    if (kIsWeb) return true;

    final photos = await Permission.photos.status;
    final videos = await Permission.videos.status;
    final storage = await Permission.storage.status;

    return photos.isGranted || videos.isGranted || storage.isGranted;
  }
}
