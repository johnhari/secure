import 'package:google_generative_ai/google_generative_ai.dart';
import '../../core/config/ai_config.dart';

class GeminiService {
  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-pro',
      apiKey: AiConfig.geminiApiKey,
    );
  }

  /// Generates a response based on a prompt.
  Future<String> generateText(String prompt) async {
    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? 'No response received.';
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Starts a chat session for continuous back-and-forth conversation.
  ChatSession startChat() {
    return _model.startChat();
  }
}
