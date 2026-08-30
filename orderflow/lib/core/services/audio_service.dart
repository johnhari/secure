import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();
  static final Map<String, AssetSource> _sources = {
    'alert': AssetSource('audio/alert.mp3'),
    'trade': AssetSource('audio/trade_click.mp3'),
    'imbalance': AssetSource('audio/imbalance.mp3'),
  };

  /// Preload audio assets into the player's cache to eliminate initial lag
  static Future<void> initialize() async {
    try {
      for (var source in _sources.values) {
        // Setting the source warms up the audio engine and loads the file
        await _player.setSource(source);
      }
      debugPrint('✅ AudioService assets preloaded');
    } catch (e) {
      debugPrint('AudioService Preload Error: $e');
    }
  }
  
  static Future<void> playTradeSound({bool isInstitutional = false, bool isBig = false}) async {
    try {
      // Prioritize imbalance sound for big signals, otherwise institutional alert, then standard trade
      AssetSource source = _sources['trade']!;
      if (isBig) {
        source = _sources['imbalance']!;
      } else if (isInstitutional) {
        source = _sources['alert']!;
      }

      if (isBig || isInstitutional) {
        // High priority alert
        await _player.play(source, volume: 1.0);
        if (!kIsWeb && await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: isBig ? 800 : 500, amplitude: 255);
        }
      } else {
        // Standard trade click
        await _player.play(source, volume: 0.5);
        if (!kIsWeb && await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 50);
        }
      }
    } catch (e) {
      debugPrint('AudioService Error: $e');
    }
  }

  static Future<void> playPriceAlertSound() async {
    try {
      final source = _sources['alert']!;
      // Play 3 times with a small gap to mimic TradingView urgency
      for (int i = 0; i < 3; i++) {
        await _player.play(source, volume: 1.0);
        if (!kIsWeb && await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 300, amplitude: 255);
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (e) {
      debugPrint('AudioService Price Alert Error: $e');
    }
  }

  static Future<void> playImbalanceSound() async {
    try {
      await _player.play(_sources['imbalance']!);
    } catch (e) {
      debugPrint('AudioService Error: $e');
    }
  }
}
