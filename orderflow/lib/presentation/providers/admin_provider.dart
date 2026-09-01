import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../core/utils/map_utils.dart';
import 'providers.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/candle.dart';

/// Aggregated user stats for admin panel
class UserStats {
  final int totalInstalls;
  final int approvedCount;
  final int pendingCount;
  final int onlineCount; // RTDB presence keys

  const UserStats({
    required this.totalInstalls,
    required this.approvedCount,
    required this.pendingCount,
    required this.onlineCount,
  });
}

// ── #10: Lightweight stats from dedicated counter document ───────────────────
// Reads `stats/user_counters` (maintained by Cloud Functions) for totalInstalls,
// approvedCount, pendingCount — no full-collection scan needed.
// Reads `presence/` RTDB node (#2) for real-time online count.
final userStatsProvider = StreamProvider<UserStats>((ref) async* {
  // Stream Firestore counter doc
  final counterStream = FirebaseFirestore.instance
      .collection('stats')
      .doc('user_counters')
      .snapshots();

  // Stream RTDB presence node — each key is a uid of an online user
  final presenceStream =
      FirebaseDatabase.instance.ref('presence').onValue;

  // Combine both streams manually: emit whenever either changes
  int totalInstalls = 0;
  int approvedCount = 0;
  int pendingCount = 0;
  int onlineCount = 0;

  // Seed online count once immediately from RTDB
  try {
    final snap =
        await FirebaseDatabase.instance.ref('presence').get();
    if (snap.exists) {
      onlineCount = MapUtils.countEntries(snap.value);
    }
  } catch (_) {}

  // Seed counter doc once immediately from Firestore
  try {
    final doc = await FirebaseFirestore.instance
        .collection('stats')
        .doc('user_counters')
        .get();
    if (doc.exists && doc.data() != null) {
      final data = MapUtils.extractMap(doc.data()) ?? {};
      totalInstalls = (data['totalInstalls'] as num?)?.toInt() ?? 0;
      approvedCount = (data['approvedCount'] as num?)?.toInt() ?? 0;
      pendingCount = (data['pendingCount'] as num?)?.toInt() ?? 0;
    }
  } catch (_) {}

  yield UserStats(
    totalInstalls: totalInstalls,
    approvedCount: approvedCount,
    pendingCount: pendingCount,
    onlineCount: onlineCount,
  );

  // Listen to Firestore counter doc changes
  await for (final snap in counterStream) {
    if (snap.exists && snap.data() != null) {
      final data = MapUtils.extractMap(snap.data()) ?? {};
      totalInstalls = (data['totalInstalls'] as num?)?.toInt() ?? 0;
      approvedCount = (data['approvedCount'] as num?)?.toInt() ?? 0;
      pendingCount = (data['pendingCount'] as num?)?.toInt() ?? 0;
    }
    yield UserStats(
      totalInstalls: totalInstalls,
      approvedCount: approvedCount,
      pendingCount: pendingCount,
      onlineCount: onlineCount,
    );
  }
});

// Separate lightweight provider just for RTDB online count — updates in real time
final onlineCountProvider = StreamProvider<int>((ref) {
  return FirebaseDatabase.instance
      .ref('presence')
      .onValue
      .map((event) {
    if (event.snapshot.value == null) return 0;
    return MapUtils.countEntries(event.snapshot.value);
  });
});

final pendingUsersProvider = FutureProvider<List<UserProfile>>((ref) async {
  final adminRepo = ref.watch(adminRepositoryProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  final token = await authRepo.getIdToken();
  if (token == null) throw Exception('Not authenticated');

  final users = await adminRepo.getUsersDirect(isApproved: false);
  final pendingList = users.where((u) => !u.isCanceled).toList();
  return _deduplicateUsers(pendingList);
});

final allUsersProvider = FutureProvider<List<UserProfile>>((ref) async {
  final adminRepo = ref.watch(adminRepositoryProvider);
  final users = await adminRepo.getUsersDirect();
  return _deduplicateUsers(users);
});

/// Helper to deduplicate users by email address
List<UserProfile> _deduplicateUsers(List<UserProfile> users) {
  final Map<String, UserProfile> uniqueUsers = {};
  
  for (final user in users) {
    final email = user.email?.trim().toLowerCase();
    
    // If no email, we can't safely deduplicate by it, so use UID
    if (email == null || email.isEmpty) {
      uniqueUsers[user.uid] = user;
      continue;
    }

    if (!uniqueUsers.containsKey(email)) {
      uniqueUsers[email] = user;
    } else {
      final existing = uniqueUsers[email]!;
      
      // Decision logic for duplicates:
      // 1. Prefer approved over non-approved
      if (user.isApproved && !existing.isApproved) {
        uniqueUsers[email] = user;
      } 
      // 2. If both same approval state, prefer one with a name
      else if (user.isApproved == existing.isApproved) {
        if (user.name != null && existing.name == null) {
          uniqueUsers[email] = user;
        }
        // 3. Finally, prefer the most recently created
        else if (user.name == existing.name || (user.name != null && existing.name != null)) {
          if (user.createdAt != null && existing.createdAt != null && 
              user.createdAt!.isAfter(existing.createdAt!)) {
            uniqueUsers[email] = user;
          }
        }
      }
    }
  }
  
  // Sort back by creation date (descending) if available, otherwise preserve order
  final result = uniqueUsers.values.toList();
  result.sort((a, b) {
    if (a.createdAt != null && b.createdAt != null) {
      return b.createdAt!.compareTo(a.createdAt!);
    }
    return 0;
  });
  
  return result;
}

final activeInjectionsProvider = StreamProvider<List<Candle>>((ref) {
  final firestore = FirebaseFirestore.instance;
  return firestore
      .collection('orderflow')
      .snapshots()
      .handleError((error) {
        debugPrint('[ACTIVE_INJECTIONS_STREAM_ERROR] $error');
        return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      })
      .map((snapshot) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final list = snapshot.docs.map((doc) {
          final data = doc.data();
          final String symbol = data['symbol'] as String? ?? '';
          final String candleKey = data['candleKey'] as String? ?? '';
          final int candleTime = data['candleTime'] as int? ?? 0;
          final int? expiryTime = data['expiryTime'] as int?;
          
          if (expiryTime != null && expiryTime < nowMs) {
            return null;
          }

          final timeStart = DateTime.fromMillisecondsSinceEpoch(candleTime);
          
          return Candle(
            symbol: symbol,
            candleKey: candleKey,
            timeStart: timeStart,
            timeEnd: timeStart.add(const Duration(minutes: 5)),
            open: 0.0,
            high: 0.0,
            low: 0.0,
            close: 0.0,
            buyerCount: data['buyerCount'] as int?,
            sellerCount: data['sellerCount'] as int?,
            isBigSignal: data['isBigSignal'] as bool? ?? false,
            isMediumSignal: data['isMediumSignal'] as bool? ?? false,
            isTrap: data['isTrap'] as bool? ?? false,
            isLiquidation: data['isLiquidation'] as bool? ?? false,
            isInjected: true,
            injectedBy: data['updatedBy'] as String? ?? 'ADMIN',
          );
        })
        .whereType<Candle>()
        .toList();
        
        list.sort((a, b) => b.timeStart.compareTo(a.timeStart));
        return list;
      });
});
