import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing global app settings (sentiment, news ticker)
class GlobalSettingsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'global_config';
  static const String _configDoc = 'active_configuration';

  /// Sentiment Types
  static const String sentimentStrongBullish = 'STRONG_BULLISH';
  static const String sentimentBullish = 'BULLISH';
  static const String sentimentSidewayBullish = 'SIDEWAY_BULLISH';
  static const String sentimentSideway = 'SIDEWAY';
  static const String sentimentSidewayBearish = 'SIDEWAY_BEARISH';
  static const String sentimentBearish = 'BEARISH';
  static const String sentimentStrongBearish = 'STRONG_BEARISH';
  static const String sentimentVolatility = 'VOLATILITY';

  /// Save global configuration
  static Future<void> updateConfig({
    String? sentiment,
    String? tickerMessage,
    bool? isMaintenanceMode,
    bool? allowAdminScreenshots,
    bool? audioAlertsEnabled,
    String? latestVersion, /// The latest available app version.
    String? updateUrl, /// URL to download the latest app version.
    String? changelog, /// Description of changes in the latest version.
    bool? forceUpdate, /// Whether to force users to update the app.
    bool? updateEnabled, /// Whether the update mechanism is active.
    String? activeBroker, /// Active broker (mstock, zerodha, all, etc)
    String? broadcastMessage, /// Custom message broadcast to all users
    String? broadcastType, /// 'info' | 'warning' | 'error'
  }) async {
    final Map<String, dynamic> data = {
      'updatedAt': FieldValue.serverTimestamp(),
    };
    
    if (sentiment != null) data['sentiment'] = sentiment;
    if (tickerMessage != null) data['tickerMessage'] = tickerMessage;
    if (isMaintenanceMode != null) data['isMaintenanceMode'] = isMaintenanceMode;
    if (allowAdminScreenshots != null) data['allowAdminScreenshots'] = allowAdminScreenshots;
    if (audioAlertsEnabled != null) data['audioAlertsEnabled'] = audioAlertsEnabled;
    if (latestVersion != null) data['latestVersion'] = latestVersion;
    if (updateUrl != null) data['updateUrl'] = updateUrl;
    if (changelog != null) data['changelog'] = changelog;
    if (forceUpdate != null) data['forceUpdate'] = forceUpdate;
    if (updateEnabled != null) data['updateEnabled'] = updateEnabled;
    if (activeBroker != null) data['activeBroker'] = activeBroker;
    
    if (broadcastMessage != null) {
      data['broadcastMessage'] = broadcastMessage;
      data['broadcastType'] = broadcastType ?? 'info';
      data['broadcastTimestamp'] = DateTime.now().millisecondsSinceEpoch;
    }

    await _firestore.collection(_collection).doc(_configDoc).set(data, SetOptions(merge: true));
  }

  /// Stream global configuration
  static Stream<Map<String, dynamic>> getConfigStream() {
    return _firestore
        .collection(_collection)
        .doc(_configDoc)
        .snapshots()
        .map((snapshot) => snapshot.data() ?? {});
  }
}
