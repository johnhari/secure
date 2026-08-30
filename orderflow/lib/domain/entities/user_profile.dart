import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

enum UserRole { admin, viewer }


/// Controls which instruments/alerts a subscriber can access.
enum SubscriptionType {
  indexOnly,       // NIFTY50, BANKNIFTY, FINNIFTY, SENSEX only
  indexAndStocks,  // Full access — indices + all Nifty 50 stocks
}

class UserProfile extends Equatable {
  final String uid;
  final String? name;
  final UserRole role;
  final DateTime? createdAt;
  final String? email;
  final String? phoneNumber;
  final bool isApproved;
  final DateTime? expiryDate;
  final bool isCanceled;
  final SubscriptionType subscriptionType;
  final String? boundDeviceId;
  final String? boundMobileDeviceId;
  final String? boundWindowsDeviceId;
  final String? registeredDeviceName;
  final String? registeredDeviceDetails;

  const UserProfile({
    required this.uid,
    required this.role,
    this.name,
    this.createdAt,
    this.email,
    this.phoneNumber,
    this.isApproved = false,
    this.expiryDate,
    this.isCanceled = false,
    this.subscriptionType = SubscriptionType.indexAndStocks,
    this.boundDeviceId,
    this.boundMobileDeviceId,
    this.boundWindowsDeviceId,
    this.registeredDeviceName,
    this.registeredDeviceDetails,
  });

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    try {
      if (value.runtimeType.toString() == 'Timestamp') {
        return (value as dynamic).toDate();
      }
    } catch (_) {}
    return null;
  }

  static SubscriptionType _parseSubscriptionType(String? value) {
    if (value == 'index_only') return SubscriptionType.indexOnly;
    return SubscriptionType.indexAndStocks;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final emailStr = json['email'] as String?;
    final isAdminEmail = AppConstants.isMasterAdmin(emailStr);

    return UserProfile(
      uid: json['uid'] as String,
      name: json['name'] as String?,
      role: isAdminEmail ? UserRole.admin : _parseRole(json['role'] as String?),
      createdAt: _parseDateTime(json['createdAt']),
      email: emailStr,
      phoneNumber: json['phoneNumber'] as String?,
      isApproved: isAdminEmail ? true : ((json['isApproved'] as bool?) ?? false),
      expiryDate: _parseDateTime(json['expiryDate']),
      isCanceled: (json['isCanceled'] as bool?) ?? false,
      subscriptionType: _parseSubscriptionType(json['subscriptionType'] as String?),
      boundDeviceId: json['boundDeviceId'] as String?,
      boundMobileDeviceId: json['boundMobileDeviceId'] as String?,
      boundWindowsDeviceId: json['boundWindowsDeviceId'] as String?,
      registeredDeviceName: json['registeredDeviceName'] as String?,
      registeredDeviceDetails: json['registeredDeviceDetails'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'role': role.name,
      'createdAt': createdAt?.toIso8601String(),
      'email': email,
      'phoneNumber': phoneNumber,
      'isApproved': isApproved,
      'expiryDate': expiryDate?.toIso8601String(),
      'isCanceled': isCanceled,
      'subscriptionType': subscriptionType == SubscriptionType.indexOnly
          ? 'index_only'
          : 'index_and_stocks',
      'boundDeviceId': boundDeviceId,
      'boundMobileDeviceId': boundMobileDeviceId,
      'boundWindowsDeviceId': boundWindowsDeviceId,
      'registeredDeviceName': registeredDeviceName,
      'registeredDeviceDetails': registeredDeviceDetails,
    };
  }

  static UserRole _parseRole(String? role) {
    return role == 'admin' ? UserRole.admin : UserRole.viewer;
  }

  bool get isAdmin => role == UserRole.admin || AppConstants.isMasterAdmin(email);

  /// Convenience getter: true when user can ONLY view index instruments.
  bool get isIndexOnly => subscriptionType == SubscriptionType.indexOnly;

  @override
  List<Object?> get props => [
        uid,
        name,
        role,
        createdAt,
        email,
        phoneNumber,
        isApproved,
        expiryDate,
        isCanceled,
        subscriptionType,
        boundDeviceId,
        boundMobileDeviceId,
        boundWindowsDeviceId,
        registeredDeviceName,
        registeredDeviceDetails,
      ];
}

