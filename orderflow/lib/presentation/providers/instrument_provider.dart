import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';

// Selected instrument provider
final selectedInstrumentProvider = StateProvider<String>((ref) {
  return AppConstants.nifty50; // Default to NIFTY50
});
