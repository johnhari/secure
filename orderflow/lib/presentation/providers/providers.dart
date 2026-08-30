import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/authentication_datasource.dart';
import '../../data/datasources/websocket_datasource.dart';
import '../../data/datasources/local_cache_datasource.dart';
import '../../data/datasources/remote_datasource.dart';
import '../../data/datasources/yahoo_datasource.dart';
import '../../data/datasources/firebase_market_datasource.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/candle_repository.dart';
import '../../data/repositories/orderflow_repository.dart';
import '../../data/repositories/admin_repository.dart';
import '../../domain/services/orderflow_service.dart';
import 'auth_provider.dart';

// Data Sources
final yahooDataSourceProvider = Provider<YahooDataSource>((ref) {
  return YahooDataSource();
});

final authDataSourceProvider = Provider<AuthenticationDataSource>((ref) {
  return AuthenticationDataSource();
});

final webSocketDataSourceProvider = Provider<WebSocketDataSource>((ref) {
  return WebSocketDataSource();
});

final localCacheDataSourceProvider = Provider<LocalCacheDataSource>((ref) {
  return LocalCacheDataSource();
});

final remoteDataSourceProvider = Provider<RemoteDataSource>((ref) {
  return RemoteDataSource();
});

final firebaseMarketDataSourceProvider = Provider<FirebaseMarketDataSource>((ref) {
  return FirebaseMarketDataSource();
});

// Repositories
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    authDataSource: ref.watch(authDataSourceProvider),
  );
});

final candleRepositoryProvider = Provider<CandleRepository>((ref) {
  return CandleRepository(
    webSocketDataSource: ref.watch(webSocketDataSourceProvider),
    yahooDataSource: ref.watch(yahooDataSourceProvider),
    firebaseMarketDataSource: ref.watch(firebaseMarketDataSourceProvider),
    localCache: ref.watch(localCacheDataSourceProvider),
  );
});

final orderflowRepositoryProvider = Provider<OrderflowRepository>((ref) {
  return OrderflowRepository(
    remoteDataSource: ref.watch(remoteDataSourceProvider),
    localCache: ref.watch(localCacheDataSourceProvider),
    candleRepository: ref.watch(candleRepositoryProvider),
  );
});

final orderflowServiceProvider = Provider<OrderflowService>((ref) {
  return OrderflowService(
    localCache: ref.watch(localCacheDataSourceProvider),
    candleRepository: ref.watch(candleRepositoryProvider),
  );
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(
    remoteDataSource: ref.watch(remoteDataSourceProvider),
  );
});

final globalSignalsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final authState = ref.watch(authProvider);
  if (!authState.isAuthenticated) {
    return Stream.value([]);
  }
  final service = ref.watch(orderflowServiceProvider);
  return service.getGlobalSignalsStream(currentUserEmail: authState.user?.email);
});
