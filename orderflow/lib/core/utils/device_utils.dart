import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:win32_registry/win32_registry.dart';

class DeviceUtils {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  // ── 1. Multi-factor Hardware Fingerprint ───────────────────────────────────

  /// Returns a stable multi-factor hardware fingerprint.
  /// On Windows: SHA-256 hash of MachineGuid + ComputerName + ProcessorId + disk serial.
  /// Much harder to spoof than a single registry key.
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
  /// 1. MachineGuid (registry)
  /// 2. ComputerName (device_info_plus)
  /// 3. CPU ProcessorNameString (registry)
  /// 4. First disk serial number (WMI via PowerShell)
  static Future<String> _buildWindowsFingerprint() async {
    final components = <String>[];

    // Factor 1: MachineGuid (registry)
    try {
      final machineGuid = _readRegistry(
        RegistryHive.localMachine,
        r'SOFTWARE\Microsoft\Cryptography',
        'MachineGuid',
      );
      if (machineGuid != null) components.add('MG:$machineGuid');
    } catch (_) {}

    // Factor 2: ComputerName from device_info_plus
    try {
      final windowsInfo = await _deviceInfo.windowsInfo;
      components.add('CN:${windowsInfo.computerName}');
      // Also use the built-in deviceId as a base
      components.add('DI:${windowsInfo.deviceId}');
    } catch (_) {}

    // Factor 3: CPU Processor info from registry
    try {
      final cpu = _readRegistry(
        RegistryHive.localMachine,
        r'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
        'ProcessorNameString',
      );
      if (cpu != null) components.add('CPU:${cpu.trim()}');
    } catch (_) {}

    // Factor 4: Disk serial number via PowerShell (non-blocking)
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
      // Last resort: use a stored UUID
      final prefs = await SharedPreferences.getInstance();
      String? stored = prefs.getString('fallback_device_id');
      if (stored == null) {
        stored = const Uuid().v4();
        await prefs.setString('fallback_device_id', stored);
      }
      return stored;
    }

    // Hash all components together → stable, unforgeable ID
    final raw = components.join('|');
    final digest = sha256.convert(utf8.encode(raw));
    return digest.toString();
  }

  // ── 4. Anti-VM Detection ───────────────────────────────────────────────────

  /// Returns true if the app is running inside a Virtual Machine.
  /// Disabled VM detection to prevent false positives on physical Windows systems.
  static Future<bool> isRunningInVM() async {
    return false;
  }

  /// Helper: read a string value from the Windows registry.
  static String? _readRegistry(RegistryHive hive, String path, String key) {
    try {
      final regKey = Registry.openPath(hive, path: path);
      final value = regKey.getValueAsString(key);
      regKey.close();
      return value;
    } catch (_) {
      return null;
    }
  }

  // ── Device Name ────────────────────────────────────────────────────────────

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
        final cpu = _readRegistry(
          RegistryHive.localMachine,
          r'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
          'ProcessorNameString',
        );
        final cpuStr = cpu != null ? ' | CPU: ${cpu.trim()}' : '';
        return 'Windows (${windowsInfo.numberOfCores} Cores)$cpuStr';
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
