import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

final heatmapStreamProvider = StreamProvider<Map<String, Map<String, dynamic>>>((ref) {
  final repo = ref.watch(candleRepositoryProvider);
  return repo.getHeatmapStream();
});
