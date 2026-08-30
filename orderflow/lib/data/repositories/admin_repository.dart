import 'package:cloud_firestore/cloud_firestore.dart';
import '../datasources/remote_datasource.dart';
import '../../domain/entities/user_profile.dart';
import '../../core/constants/app_constants.dart';


class AdminRepository {
  final RemoteDataSource _remoteDataSource;

  AdminRepository({required RemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  /// Get users (admin only)
  Future<List<UserProfile>> getUsers({
    required String token,
    bool? isApproved,
  }) async {
    final list = await _remoteDataSource.getUsers(
      token: token,
      isApproved: isApproved,
    );
    return list.map((json) => UserProfile.fromJson(json)).toList();
  }

  /// Get users directly from Firestore (to bypass Cloud Functions)
  Future<List<UserProfile>> getUsersDirect({bool? isApproved}) async {
    final firestore = _remoteDataSource.firestore;
    Query query = firestore.collection('users');
    
    if (isApproved != null) {
      query = query.where('isApproved', isEqualTo: isApproved);
    }
    
    final snapshot = await query.limit(50).get();
    return snapshot.docs
        .map((doc) => UserProfile.fromJson({...doc.data() as Map<String, dynamic>, 'uid': doc.id}))
        .toList();
  }

  /// Update user status directly in Firestore
  Future<void> updateUserStatusDirect({
    required String uid,
    required bool isApproved,
    required String adminUid,
    DateTime? expiryDate,
    bool? isCanceled,
    String? subscriptionType, // 'index_only' | 'index_and_stocks'
  }) async {
    final firestore = _remoteDataSource.firestore;
    final updates = <String, dynamic>{
      'isApproved': isApproved,
      'approvedAt': isApproved ? DateTime.now().toIso8601String() : null,
      'approvedBy': isApproved ? adminUid : null,
    };

    if (expiryDate != null) {
      updates['expiryDate'] = expiryDate.toIso8601String();
    }
    if (isCanceled != null) {
      updates['isCanceled'] = isCanceled;
    }
    if (subscriptionType != null) {
      updates['subscriptionType'] = subscriptionType;
    }

    await firestore.collection('users').doc(uid).update(updates);

    // Recount stats to self-heal and update stats/user_counters document
    try {
      final snapshot = await firestore.collection('users').get();
      int total = 0;
      int approved = 0;
      int pending = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final email = data['email'] as String? ?? '';
        if (AppConstants.isMasterAdmin(email)) continue; // Skip admin

        total++;
        final isAppr = data['isApproved'] as bool? ?? false;
        final isCanc = data['isCanceled'] as bool? ?? false;

        if (isAppr && !isCanc) {
          approved++;
        } else if (!isAppr && !isCanc) {
          pending++;
        }
      }

      await firestore.collection('stats').doc('user_counters').set({
        'totalInstalls': total,
        'approvedCount': approved,
        'pendingCount': pending,
      });
    } catch (_) {}
  }

  /// Reset bound hardware ID for a user (Admin action)
  Future<void> resetHardwareId({required String uid}) async {
    final firestore = _remoteDataSource.firestore;
    await firestore.collection('users').doc(uid).update({
      'boundDeviceId': FieldValue.delete(),
      'boundMobileDeviceId': FieldValue.delete(),
      'boundWindowsDeviceId': FieldValue.delete(),
    });
  }
}

