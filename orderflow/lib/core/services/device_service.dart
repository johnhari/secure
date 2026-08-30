import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    Map<String, dynamic> data = {};
    
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      data['app_version'] = packageInfo.version;
      data['build_number'] = packageInfo.buildNumber;
      data['platform'] = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : (defaultTargetPlatform == TargetPlatform.macOS
                      ? 'macos'
                      : (defaultTargetPlatform == TargetPlatform.windows ? 'windows' : 'other'))));

      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        data['browser'] = webInfo.browserName.toString();
        data['user_agent'] = webInfo.userAgent;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        data['model'] = androidInfo.model;
        data['brand'] = androidInfo.brand;
        data['os_version'] = androidInfo.version.release;
        data['sdk_int'] = androidInfo.version.sdkInt;
        data['manufacturer'] = androidInfo.manufacturer;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        data['model'] = iosInfo.utsname.machine;
        data['os_version'] = iosInfo.systemVersion;
        data['name'] = iosInfo.name;
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        data['model'] = macInfo.model;
        data['computer_name'] = macInfo.computerName;
        data['os_version'] = macInfo.osRelease;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        data['model'] = 'Windows PC';
        data['computer_name'] = windowsInfo.computerName;
        data['os_version'] = '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error gathering device info: $e');
      }
      data['error'] = e.toString();
    }

    return data;
  }
}
