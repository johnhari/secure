import 'package:equatable/equatable.dart';
 
 class GhostOrder extends Equatable {
   final String id;
   final String symbol;
   final String triggerSymbol;
   final double triggerPrice;
   final int buyerCount;
   final int sellerCount;
   final bool isBigSignal;
   final bool isMediumSignal;
   final bool isTrap;
   final bool isLiquidation;
   final bool isInstitutional;
   final double bubbleScale;
   final double pulseSpeed;
   final double bubbleOpacity;
   final DateTime createdAt;
   final bool isTriggered;
   final bool adminOnly;
 
   const GhostOrder({
     required this.id,
     required this.symbol,
     String? triggerSymbol,
     required this.triggerPrice,
     required this.buyerCount,
     required this.sellerCount,
     this.isBigSignal = false,
     this.isMediumSignal = false,
     this.isTrap = false,
     this.isLiquidation = false,
     this.isInstitutional = false,
     this.bubbleScale = 5.0,
     this.pulseSpeed = 1.0,
     this.bubbleOpacity = 0.65,
     required this.createdAt,
     this.isTriggered = false,
     this.adminOnly = false,
   }) : triggerSymbol = triggerSymbol ?? symbol;
 
   @override
   List<Object?> get props => [
         id,
         symbol,
         triggerSymbol,
         triggerPrice,
         buyerCount,
         sellerCount,
         isBigSignal,
         isMediumSignal,
         isTrap,
         isLiquidation,
         isInstitutional,
         bubbleScale,
         pulseSpeed,
         bubbleOpacity,
         createdAt,
         isTriggered,
         adminOnly,
       ];
 
   GhostOrder copyWith({
     bool? isTriggered,
     String? triggerSymbol,
     bool? adminOnly,
   }) {
     return GhostOrder(
       id: id,
       symbol: symbol,
       triggerSymbol: triggerSymbol ?? this.triggerSymbol,
       triggerPrice: triggerPrice,
       buyerCount: buyerCount,
       sellerCount: sellerCount,
       isBigSignal: isBigSignal,
       isMediumSignal: isMediumSignal,
       isTrap: isTrap,
       isLiquidation: isLiquidation,
       isInstitutional: isInstitutional,
       bubbleScale: bubbleScale,
       pulseSpeed: pulseSpeed,
       bubbleOpacity: bubbleOpacity,
       createdAt: createdAt,
       isTriggered: isTriggered ?? this.isTriggered,
       adminOnly: adminOnly ?? this.adminOnly,
     );
   }
 
   factory GhostOrder.fromJson(Map<String, dynamic> json) {
     return GhostOrder(
       id: json['id'] as String,
       symbol: json['symbol'] as String,
       triggerSymbol: json['triggerSymbol'] as String? ?? json['symbol'] as String,
       triggerPrice: (json['triggerPrice'] as num).toDouble(),
       buyerCount: json['buyerCount'] as int,
       sellerCount: json['sellerCount'] as int,
       isBigSignal: json['isBigSignal'] as bool? ?? false,
       isMediumSignal: json['isMediumSignal'] as bool? ?? false,
       isTrap: json['isTrap'] as bool? ?? false,
       isLiquidation: json['isLiquidation'] as bool? ?? false,
       isInstitutional: json['isInstitutional'] as bool? ?? false,
       bubbleScale: (json['bubbleScale'] as num?)?.toDouble() ?? 5.0,
       pulseSpeed: (json['pulseSpeed'] as num?)?.toDouble() ?? 1.0,
       bubbleOpacity: (json['bubbleOpacity'] as num?)?.toDouble() ?? 0.65,
       createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
       isTriggered: json['isTriggered'] as bool? ?? false,
       adminOnly: json['adminOnly'] as bool? ?? false,
     );
   }
 
   Map<String, dynamic> toJson() {
     return {
       'id': id,
       'symbol': symbol,
       'triggerSymbol': triggerSymbol,
       'triggerPrice': triggerPrice,
       'buyerCount': buyerCount,
       'sellerCount': sellerCount,
       'isBigSignal': isBigSignal,
       'isMediumSignal': isMediumSignal,
       'isTrap': isTrap,
       'isLiquidation': isLiquidation,
       'isInstitutional': isInstitutional,
       'bubbleScale': bubbleScale,
       'pulseSpeed': pulseSpeed,
       'bubbleOpacity': bubbleOpacity,
       'createdAt': createdAt.millisecondsSinceEpoch,
       'isTriggered': isTriggered,
       'adminOnly': adminOnly,
     };
   }
 }
