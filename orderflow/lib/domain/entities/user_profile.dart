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
    final emailStr = json['email']?.toString();
    final isAdminEmail = AppConstants.isMasterAdmin(emailStr);

    return UserProfile(
      uid: json['uid']?.toString() ?? '',
      name: json['name']?.toString(),
      role: isAdminEmail ? UserRole.admin : _parseRole(json['role']?.toString()),
      createdAt: _parseDateTime(json['createdAt']),
      email: emailStr,
      phoneNumber: json['phoneNumber']?.toString(),
      isApproved: isAdminEmail ? true : (json['isApproved'] == true || json['isApproved'] == 1 || json['isApproved'] == 'true'),
      expiryDate: _parseDateTime(json['expiryDate']),
      isCanceled: json['isCanceled'] == true || json['isCanceled'] == 1 || json['isCanceled'] == 'true',
      subscriptionType: _parseSubscriptionType(json['subscriptionType']?.toString()),
      boundDeviceId: json['boundDeviceId']?.toString(),
      boundMobileDeviceId: json['boundMobileDeviceId']?.toString(),
      boundWindowsDeviceId: json['boundWindowsDeviceId']?.toString(),
      registeredDeviceName: json['registeredDeviceName']?.toString(),
      registeredDeviceDetails: json['registeredDeviceDetails']?.toString(),
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

