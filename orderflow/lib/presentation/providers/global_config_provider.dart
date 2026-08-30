import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/services/global_settings_service.dart';
import 'auth_provider.dart';

final globalConfigProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final authState = ref.watch(authProvider);
  if (!authState.isAuthenticated) {
    return Stream.value({});
  }
  return GlobalSettingsService.getConfigStream();
});
