import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/gemini_service.dart';

/// Provider for GeminiService using standard Riverpod syntax to avoid build_runner dependencies.
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});
