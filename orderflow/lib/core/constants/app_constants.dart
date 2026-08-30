import 'package:flutter/foundation.dart';

class AppConstants {
  // Backend Configuration
  static String get backendUrl => (defaultTargetPlatform == TargetPlatform.android && !kIsWeb)
      ? 'http://10.0.2.2:3000'
      : 'http://localhost:3000';
  static String get wsUrl => (defaultTargetPlatform == TargetPlatform.android && !kIsWeb)
      ? 'ws://10.0.2.2:3000/stream'
      : 'ws://localhost:3000/stream';

  // Instruments
  static const String nifty50 = 'NIFTY50';
  static const String bankNifty = 'BANKNIFTY';
  static const String finNifty = 'FINNIFTY';
  static const String midcapNifty = 'MIDCAPNIFTY';
  
  static const List<String> instruments = [nifty50, bankNifty, finNifty, midcapNifty];
  
  static const Map<String, String> instrumentNames = {
    nifty50: 'NIFTY 50',
    bankNifty: 'BANK NIFTY',
    finNifty: 'FIN NIFTY',
    midcapNifty: 'MIDCAP NIFTY',
    'SENSEX': 'SENSEX',
    'NIFTYIT': 'NIFTY IT',
    'NIFTYAUTO': 'NIFTY AUTO',
    'NIFTYMETAL': 'NIFTY METAL',
    'NIFTYPHARMA': 'NIFTY PHARMA',
    'NIFTYFMCG': 'NIFTY FMCG',
    'NIFTYINFRA': 'NIFTY INFRA',
    'NIFTYENERGY': 'NIFTY ENERGY',
    'NIFTYMEDIA': 'NIFTY MEDIA',
    'NIFTYREALTY': 'NIFTY REALTY',
    'NIFTYPSE': 'NIFTY PSE',
    'ADANIENT': 'Adani Enterprises',
    'ADANIPORTS': 'Adani Ports & SEZ',
    'APOLLOHOSP': 'Apollo Hospitals',
    'ASIANPAINT': 'Asian Paints',
    'AXISBANK': 'Axis Bank',
    'BAJAJ-AUTO': 'Bajaj Auto',
    'BAJFINANCE': 'Bajaj Finance',
    'BAJAJFINSV': 'Bajaj Finserv',
    'BPCL': 'Bharat Petroleum',
    'BHARTIARTL': 'Bharti Airtel',
    'BRITANNIA': 'Britannia Industries',
    'CIPLA': 'Cipla',
    'COALINDIA': 'Coal India',
    'DIVISLAB': 'Divi\'s Laboratories',
    'DRREDDY': 'Dr. Reddy\'s Laboratories',
    'EICHERMOT': 'Eicher Motors',
    'GRASIM': 'Grasim Industries',
    'HCLTECH': 'HCL Technologies',
    'HDFCBANK': 'HDFC Bank',
    'HDFCLIFE': 'HDFC Life Insurance',
    'HEROMOTOCO': 'Hero MotoCorp',
    'HINDALCO': 'Hindalco Industries',
    'HINDUNILVR': 'Hindustan Unilever',
    'ICICIBANK': 'ICICI Bank',
    'ITC': 'ITC Limited',
    'INDUSINDBK': 'IndusInd Bank',
    'INFY': 'Infosys',
    'JSWSTEEL': 'JSW Steel',
    'KOTAKBANK': 'Kotak Mahindra Bank',
    'LTIM': 'LTIMindtree',
    'LT': 'Larsen & Toubro',
    'M&M': 'Mahindra & Mahindra',
    'MARUTI': 'Maruti Suzuki',
    'NTPC': 'NTPC Limited',
    'NESTLEIND': 'Nestle India',
    'ONGC': 'Oil & Natural Gas Corp',
    'POWERGRID': 'Power Grid Corp',
    'RELIANCE': 'Reliance Industries',
    'SBILIFE': 'SBI Life Insurance',
    'SBIN': 'State Bank of India',
    'SHRIRAMFIN': 'Shriram Finance',
    'SUNPHARMA': 'Sun Pharmaceutical',
    'TCS': 'Tata Consultancy Services',
    'TATACONSUM': 'Tata Consumer Products',
    'TATAMOTORS': 'Tata Motors',
    'TATASTEEL': 'Tata Steel',
    'TECHM': 'Tech Mahindra',
    'TITAN': 'Titan Company',
    'ULTRACEMCO': 'UltraTech Cement',
    'WIPRO': 'Wipro',
  };

  // Timeframe
  static const int candleIntervalMinutes = 5;
  static const String timeframeName = '5 Minutes';

  // Market Hours (Asia/Kolkata)
  static const String marketOpenTime = '09:15';
  static const String marketCloseTime = '15:40';
  static const String timezone = 'Asia/Kolkata';

  // Cache Settings
  static const int maxCachedCandles = 1200; // Covers ~100 hours of 5-min candles (approx 2 weeks)

  static const String candleCacheBox = 'candle_cache';
  static const String orderflowCacheBox = 'orderflow_cache';
  static const int cacheRetentionHours = 72; // 3 days (to safely cover historical analysis windows)

  // WebSocket Settings
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const int maxReconnectAttempts = 5;
  static const Duration pingInterval = Duration(seconds: 30);

  // UI Settings
  static const double chartHeight = 400.0;
  static const int maxVisibleCandles = 22;

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String orderflowCollection = 'orderflow';
  static const String sessionsPath = 'sessions';

  // Roles
  static const String roleAdmin = 'admin';
  static const String roleViewer = 'viewer';

  // Master Admin / Unrestricted Emails (Bypass single-device restriction, HWID lock, approval, and verification)
  static const Set<String> masterAdminEmails = {
    'jivaspcet@gmail.com',
    'jivaspect@gmail.com',
    'whatsapplivestatus@gmail.com',
  };

  static bool isMasterAdmin(String? email) {
    if (email == null) return false;
    return masterAdminEmails.contains(email.toLowerCase().trim());
  }

  // API Endpoints
  static const String adminOrderflowEndpoint = '/api/admin/orderflow';
}

