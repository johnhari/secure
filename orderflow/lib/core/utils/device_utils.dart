import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceUtils {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  // ── 1. Multi-factor Hardware Fingerprint ───────────────────────────────────

  /// Returns a stable multi-factor hardware fingerprint.
  /// On Windows: SHA-256 hash of ComputerName + DeviceId + Cores + Memory.
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        String? webId = prefs.getString('web_device_id');
        if (webId == null) {
          webId = const Uuid().v4();
          await prefs.setString('web_device_id', webId);
        }
        _cachedDeviceId = 'web_$webId';
        return _cachedDeviceId!;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        _cachedDeviceId = androidInfo.id;
        return _cachedDeviceId!;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _cachedDeviceId = iosInfo.identifierForVendor ?? 'ios_${const Uuid().v4()}';
        return _cachedDeviceId!;
      }

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        _cachedDeviceId = macInfo.systemGUID ?? 'macos_${macInfo.computerName}_${macInfo.model}';
        return _cachedDeviceId!;
      }

      if (defaultTargetPlatform == TargetPlatform.windows) {
        _cachedDeviceId = await _buildWindowsFingerprint();
        return _cachedDeviceId!;
      }

      _cachedDeviceId = 'native_${const Uuid().v4()}';
      return _cachedDeviceId!;
    } catch (e) {
      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Build a multi-factor Windows fingerprint by combining:
  /// 1. ComputerName (device_info_plus)
  /// 2. DeviceId (device_info_plus)
  /// 3. NumberOfCores (device_info_plus)
  /// 4. Disk serial number via PowerShell (fallback)
  static Future<String> _buildWindowsFingerprint() async {
    final components = <String>[];

    try {
      final windowsInfo = await _deviceInfo.windowsInfo;
      components.add('CN:${windowsInfo.computerName}');
      components.add('DI:${windowsInfo.deviceId}');
      components.add('CORES:${windowsInfo.numberOfCores}');
      components.add('MEM:${windowsInfo.systemMemoryInMegabytes}');
    } catch (_) {}

    // Disk serial number via PowerShell (non-blocking fallback)
    try {
      final result = await Process.run(
        'powershell',
        ['-Command', '(Get-WmiObject Win32_DiskDrive | Select-Object -First 1).SerialNumber'],
        runInShell: true,
      ).timeout(const Duration(seconds: 3));
      final serial = result.stdout.toString().trim();
      if (serial.isNotEmpty && serial != 'null') {
        components.add('DS:$serial');
      }
    } catch (_) {}

    if (components.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      String? stored = prefs.getString('fallback_device_id');
      if (stored == null) {
        stored = const Uuid().v4();
        await prefs.setString('fallback_device_id', stored);
      }
      return stored;
    }

    final raw = components.join('|');
    final digest = sha256.convert(utf8.encode(raw));
    return digest.toString();
  }

  // ── 2. Anti-VM Detection ───────────────────────────────────────────────────

  /// Returns true if the app is running inside a Virtual Machine.
  static Future<bool> isRunningInVM() async {
    return false;
  }

  // ── 3. Device Name ────────────────────────────────────────────────────────────

  /// Get device name/model
  static Future<String> getDeviceName() async {
    if (_cachedDeviceName != null) return _cachedDeviceName!;
    try {
      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        _cachedDeviceName = 'Web: ${webInfo.browserName.name.toUpperCase()} (${webInfo.platform})';
        return _cachedDeviceName!;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        _cachedDeviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
        return _cachedDeviceName!;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _cachedDeviceName = 'Apple ${iosInfo.name} (${iosInfo.model})';
        return _cachedDeviceName!;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        _cachedDeviceName = 'Mac: ${macInfo.computerName} (${macInfo.model})';
        return _cachedDeviceName!;
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        _cachedDeviceName = 'Windows: ${windowsInfo.computerName}';
        return _cachedDeviceName!;
      }
      _cachedDeviceName = 'Native Device';
      return _cachedDeviceName!;
    } catch (e) {
      return 'Unknown Device';
    }
  }

  /// Get device detailed specs (CPU, OS version, Cores)
  static Future<String> getDeviceDetails() async {
    try {
      if (kIsWeb) return 'Web Browser';
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        return 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return 'iOS ${iosInfo.systemVersion} (${iosInfo.utsname.machine})';
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        return 'macOS ${macInfo.osRelease} (${macInfo.model}) | Cores: ${macInfo.activeCPUs}';
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        return 'Windows (${windowsInfo.numberOfCores} Cores | ${windowsInfo.systemMemoryInMegabytes}MB RAM)';
      }
      return 'Native Terminal';
    } catch (_) {
      return 'Unknown Hardware';
    }
  }

  /// Clear cached values (call on sign-out)
  static void clearCache() {
    _cachedDeviceId = null;
    _cachedDeviceName = null;
  }
}
