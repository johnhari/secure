import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/mstock_constants.dart';
import '../models/tick_data_model.dart';

enum MStockConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticating,
  authenticated,
  subscribed,
  reconnecting,
  error,
}

class MStockWebSocketService {
  WebSocketChannel? _channel;
  final StreamController<TickData> _tickController = StreamController<TickData>.broadcast();
  final StreamController<MStockConnectionStatus> _statusController = StreamController<MStockConnectionStatus>.broadcast();
  
  MStockConnectionStatus _status = MStockConnectionStatus.disconnected;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  
  Stream<TickData> get tickStream => _tickController.stream;
  Stream<MStockConnectionStatus> get connectionStream => _statusController.stream;
  MStockConnectionStatus get status => _status;

  Future<void> connect() async {
    if (_status == MStockConnectionStatus.connected || _status == MStockConnectionStatus.connecting) return;
    
    try {
      _updateStatus(MStockConnectionStatus.connecting);
      _channel = WebSocketChannel.connect(Uri.parse(MStockConstants.wsUrl));
      
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      _updateStatus(MStockConnectionStatus.connected);
      await authenticate();
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> authenticate() async {
    if (_status != MStockConnectionStatus.connected) return;
    
    _updateStatus(MStockConnectionStatus.authenticating);
    final authMessage = {
      "action": "authenticate",
      "apiKey": MStockConstants.apiKey
    };
    
    _channel?.sink.add(jsonEncode(authMessage));
  }

  Future<void> subscribeToInstruments(List<Map<String, String>> instruments) async {
    if (_status != MStockConnectionStatus.authenticated && _status != MStockConnectionStatus.subscribed) return;
    
    final subscribeMessage = {
      "action": "subscribe",
      "mode": "full",
      "instruments": instruments
    };
    
    _channel?.sink.add(jsonEncode(subscribeMessage));
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'];

      switch (type) {
        case 'auth':
          if (data['status'] == 'success') {
            _updateStatus(MStockConnectionStatus.authenticated);
            _startHeartbeat();
            // Automatically subscribe to Nifty and BankNifty
            subscribeToInstruments([
              {
                "exchange": MStockConstants.exchange,
                "token": MStockConstants.nifty50Token,
                "symbol": "NIFTY 50"
              },
              {
                "exchange": MStockConstants.exchange,
                "token": MStockConstants.bankNiftyToken,
                "symbol": "NIFTY BANK"
              }
            ]);
          } else {
            _updateStatus(MStockConnectionStatus.error);
          }
          break;
          
        case 'subscribe':
          if (data['status'] == 'success') {
            _updateStatus(MStockConnectionStatus.subscribed);
          }
          break;
          
        case 'tick':
          final tick = TickData.fromJson(data);
          _tickController.add(tick);
          break;
          
        case 'pong':
          // Heartbeat response
          break;
          
        case 'error':
          print('MStock API Error: ${data['message']}');
          break;
      }
    } catch (e) {
      print('Error parsing MStock message: $e');
    }
  }

  void _updateStatus(MStockConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_status == MStockConnectionStatus.subscribed || _status == MStockConnectionStatus.authenticated) {
        _channel?.sink.add(jsonEncode({
          "action": "ping",
          "timestamp": DateTime.now().millisecondsSinceEpoch
        }));
      }
    });
  }

  void _handleError(dynamic error) {
    _updateStatus(MStockConnectionStatus.error);
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _updateStatus(MStockConnectionStatus.disconnected);
    
    if (_reconnectAttempts < 5) {
      _reconnectAttempts++;
      _updateStatus(MStockConnectionStatus.reconnecting);
      Future.delayed(Duration(seconds: _reconnectAttempts * 2), connect);
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _tickController.close();
    _statusController.close();
  }
}
