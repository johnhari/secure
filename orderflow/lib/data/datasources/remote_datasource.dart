import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';

class RemoteDataSource {
  final http.Client _client;
  final FirebaseFirestore _firestore;

  RemoteDataSource({http.Client? client, FirebaseFirestore? firestore}) 
      : _client = client ?? http.Client(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  FirebaseFirestore get firestore => _firestore;

  /// Save orderflow data (admin only)
  Future<Map<String, dynamic>> saveOrderflow({
    required String token,
    required String candleKey,
    required int buyerCount,
    required int sellerCount,
  }) async {
    final url = Uri.parse('${AppConstants.backendUrl}/saveOrderflow');

    final response = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'candleKey': candleKey,
        'buyerCount': buyerCount,
        'sellerCount': sellerCount,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to save orderflow: ${response.body}');
    }
  }

  /// Get orderflow data for a specific candle
  Future<Map<String, dynamic>?> getOrderflow({
    required String token,
    required String candleKey,
  }) async {
    final url = Uri.parse('${AppConstants.backendUrl}${AppConstants.adminOrderflowEndpoint}/$candleKey');

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['data'] as Map<String, dynamic>?;
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to get orderflow: ${response.body}');
    }
  }

  /// Get all orderflow data for a symbol and date
  Future<List<Map<String, dynamic>>> getOrderflowBySymbolAndDate({
    required String token,
    required String symbol,
    required DateTime date,
  }) async {
    final url = Uri.parse('${AppConstants.backendUrl}${AppConstants.adminOrderflowEndpoint}')
        .replace(queryParameters: {
      'symbol': symbol,
      'date': date.toIso8601String(),
    });

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List;
      return list.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to query orderflow: ${response.body}');
    }
  }
  /// Get users (admin only)
  Future<List<Map<String, dynamic>>> getUsers({
    required String token,
    bool? isApproved,
  }) async {
    final queryParams = <String, String>{};
    if (isApproved != null) {
      queryParams['isApproved'] = isApproved.toString();
    }

    final url = Uri.parse('${AppConstants.backendUrl}/getUsers')
        .replace(queryParameters: queryParams);

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['users'] as List;
      return list.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to get users: ${response.body}');
    }
  }

  /// Update user status (admin only)
  Future<void> updateUserStatus({
    required String token,
    required String uid,
    required bool isApproved,
  }) async {
    final url = Uri.parse('${AppConstants.backendUrl}/updateUserStatus/$uid');

    final response = await _client.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'isApproved': isApproved,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update user status: ${response.body}');
    }
  }
}
