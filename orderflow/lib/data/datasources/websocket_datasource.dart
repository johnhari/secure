import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/device_utils.dart';
import '../models/candle_model.dart';

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

enum DataSourceType {
  mstock,
  zerodha,
  kotak,
  simulated,
  unknown,
}

class DataSourceStatus {
  final DataSourceType type;
  final bool isConnected;
  final String message;

  const DataSourceStatus({
    required this.type,
    required this.isConnected,
    required this.message,
  });
}

class WebSocketDataSource {
  WebSocketChannel? _channel;
  StreamController<CandleModel>? _candleController;
  StreamController<WsConnectionState>? _connectionController;
  StreamController<DataSourceStatus>? _dataSourceController;
  
  WsConnectionState _connectionState = WsConnectionState.disconnected;
  DataSourceStatus _dataSourceStatus = const DataSourceStatus(
    type: DataSourceType.unknown,
    isConnected: false,
    message: 'Not connected',
  );
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  String? _token;
  List<String> _subscribedInstruments = [];

  WebSocketDataSource() {
    _candleController = StreamController<CandleModel>.broadcast();
    _connectionController = StreamController<WsConnectionState>.broadcast();
    _dataSourceController = StreamController<DataSourceStatus>.broadcast();
  }

  /// Connect to WebSocket with authentication token
  Future<void> connect(String token) async {
    _token = token;
    _reconnectAttempts = 0;
    await _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    try {
      _updateConnectionState(WsConnectionState.connecting);

      // Close existing connection
      await _closeConnection();

      // Get device ID for session enforcement
      final deviceId = await DeviceUtils.getDeviceId();

      // Connect with token and deviceId as query parameters
      final wsUrl = '${AppConstants.wsUrl}?token=$_token&deviceId=$deviceId';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Listen to messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('WebSocket closed');
          _handleDisconnect();
        },
      );

      // Start ping timer
      _startPingTimer();

    } catch (e) {
      print('WebSocket connection error: $e');
      _handleDisconnect();
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'] as String?;

      switch (type) {
        case 'connected':
          print('WebSocket connected: ${data['message']}');
          _updateConnectionState(WsConnectionState.connected);
          _reconnectAttempts = 0;
          
          // Handle data source status from connected message
          if (data['dataSource'] != null) {
            final dsData = data['dataSource'];
            _updateDataSourceStatus(DataSourceStatus(
              type: _parseDataSourceType(dsData['type']),
              isConnected: dsData['status'] == 'connected',
              message: dsData['message'] ?? '',
            ));
          }
          
          // Re-subscribe to instruments
          if (_subscribedInstruments.isNotEmpty) {
            subscribe(_subscribedInstruments);
          }
          break;

        case 'status':
          // Handle explicit status messages
          final dsType = _parseDataSourceType(data['dataSource']);
          final dsConnected = data['status'] == 'connected';
          final dsMessage = data['message'] ?? '';
          
          _updateDataSourceStatus(DataSourceStatus(
            type: dsType,
            isConnected: dsConnected,
            message: dsMessage,
          ));
          break;

        case 'candle':
          // Parse and emit candle
          final candleData = data['data'] as Map<String, dynamic>;
          final candle = CandleModel.fromJson(candleData);
          _candleController?.add(candle);
          break;

        case 'subscribed':
          print('Subscribed to: ${data['instruments']}');
          break;

        case 'pong':
          // Heartbeat response
          break;

        case 'error':
          print('Server error: ${data['message']}');
          break;

        default:
          print('Unknown message type: $type');
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  /// Subscribe to instruments
  void subscribe(List<String> instruments) {
    _subscribedInstruments = instruments;

    if (_connectionState == WsConnectionState.connected) {
      final message = jsonEncode({
        'type': 'subscribe',
        'instruments': instruments,
      });

      _channel?.sink.add(message);
    }
  }

  /// Unsubscribe from instruments
  void unsubscribe(List<String> instruments) {
    _subscribedInstruments.removeWhere((i) => instruments.contains(i));

    if (_connectionState == WsConnectionState.connected) {
      final message = jsonEncode({
        'type': 'unsubscribe',
        'instruments': instruments,
      });

      _channel?.sink.add(message);
    }
  }

  /// Handle disconnection
  void _handleDisconnect() {
    _updateConnectionState(WsConnectionState.reconnecting);
    _pingTimer?.cancel();

    if (_reconnectAttempts < AppConstants.maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = AppConstants.reconnectDelay * _reconnectAttempts;
      
      print('Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        if (_token != null) {
          _connectWebSocket();
        }
      });
    } else {
      print('Max reconnection attempts reached');
      _updateConnectionState(WsConnectionState.disconnected);
    }
  }

  /// Start ping timer (keep-alive)
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(AppConstants.pingInterval, (timer) {
      if (_connectionState == WsConnectionState.connected) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  /// Update connection state
  void _updateConnectionState(WsConnectionState state) {
    _connectionState = state;
    _connectionController?.add(state);
  }

  /// Update data source status
  void _updateDataSourceStatus(DataSourceStatus status) {
    _dataSourceStatus = status;
    _dataSourceController?.add(status);
  }

  /// Close connection
  Future<void> _closeConnection() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  /// Disconnect
  Future<void> disconnect() async {
    _token = null;
    _subscribedInstruments = [];
    _reconnectAttempts = 0;
    await _closeConnection();
    _updateConnectionState(WsConnectionState.disconnected);
  }

  /// Stream of candles
  Stream<CandleModel> get candleStream => _candleController!.stream;

  /// Stream of connection state
  Stream<WsConnectionState> get connectionStream => _connectionController!.stream;

  /// Stream of data source status
  Stream<DataSourceStatus> get dataSourceStream => _dataSourceController!.stream;

  /// Current connection state
  WsConnectionState get connectionState => _connectionState;

  /// Current data source status
  DataSourceStatus get dataSourceStatus => _dataSourceStatus;

  /// Dispose
  void dispose() {
    disconnect();
    _candleController?.close();
    _connectionController?.close();
    _dataSourceController?.close();
  }

  /// Parse data source type string to enum
  DataSourceType _parseDataSourceType(String? typeStr) {
    if (typeStr == null) return DataSourceType.unknown;
    final lower = typeStr.toLowerCase();
    if (lower.contains('mstock') || lower.contains('yahoo')) return DataSourceType.mstock;
    if (lower.contains('zerodha')) return DataSourceType.zerodha;
    if (lower.contains('kotak')) return DataSourceType.kotak;
    if (lower.contains('simulated')) return DataSourceType.simulated;
    return DataSourceType.unknown;
  }
}
