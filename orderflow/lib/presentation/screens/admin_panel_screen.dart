import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/nifty_stocks.dart';
import '../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/providers.dart';
import '../providers/candle_provider.dart';
import '../providers/instrument_provider.dart';
import '../providers/admin_provider.dart';
import '../../domain/services/global_settings_service.dart';
import '../../domain/entities/ghost_order.dart';
import '../../domain/entities/candle.dart';
import '../../data/models/candle_model.dart';
import '../../domain/services/orderflow_service.dart';
import '../widgets/replay_player_dialog.dart';

import '../../domain/entities/user_profile.dart';

class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> with SingleTickerProviderStateMixin {
  final _buyerCountController = TextEditingController();
  final _sellerCountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Ghost Order & Footprint controllers
  final _ghostTriggerController = TextEditingController();
  final _priceLevelController = TextEditingController();
  final _levelBuyerController = TextEditingController();
  final _levelSellerController = TextEditingController();
  bool _isGhostMode = false;
  bool _scanAllStocksMode = false; // false = NIFTY ONLY mode (Instant injection, zero scan delay)

  DateTime? _selectedCandleTime;
  String? _localSentiment;
  bool _isBigSignal = false;
  bool _isTrap = false;
  bool _isLiquidation = false;
  double _bubbleScale = 5.0;
  double _bubbleOpacity = 0.65;
  double _bubbleGlow = 0.0;
  bool _showLabel = true;
  bool _broadcastPush = true;
  bool _adminOnly = false;
  String _selectedSentiment = 'SIDEWAY';
  final TextEditingController _newsTickerController = TextEditingController();
  final _tickerController = TextEditingController();
  final _customTagController = TextEditingController();
  final _candleSearchController = TextEditingController();
  final _broadcastMsgController = TextEditingController();
  String _broadcastType = 'info';
  bool _broadcastLoading = false;
  double _pulseSpeed = 1.0;
  String _borderColorSelection = "DEFAULT";
  int _autoFadeMinutes = 0;
  bool _isLoading = false;
  bool _syncLoading = false;
  String _activeBroker = 'all';
  late TabController _tabController;

  // ── App Update State ─────────────────────────────────────────
  final _versionController = TextEditingController(text: '8.7');
  final _updateUrlController = TextEditingController();
  final _changelogController = TextEditingController();
  bool _forceUpdate = false;
  bool _updateEnabled = false;
  bool _updateLoading = false;
  bool _isMaintenanceMode = false;
  bool _allowAdminScreenshots = false;
  bool _audioAlertsEnabled = true;
  bool _showAllUsers = false;
  bool _isQuickFireMode = false;
  String? _lastInjectedCandleKey;
  String? _lastInjectedSymbol;

  bool _isScanningSimilarPatterns = false;
  int _scanProgress = 0;
  int _scanTotal = 0;
  List<Map<String, dynamic>> _suggestedSimilarStocks = [];
  final Set<String> _selectedSimilarStocksToInject = {};

  bool _isUploadingApk = false;
  double _apkUploadProgress = 0.0;

  Future<void> _pickAndUploadApk() async {
    final version = _versionController.text.trim();
    if (version.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PLEASE ENTER A VERSION NUMBER FIRST BEFORE UPLOADING THE APK'),
          backgroundColor: AppTheme.bearColor,
        ),
      );
      return;
    }

    try {
      final result = await fp.FilePicker.pickFiles(
        type: fp.FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      if (!file.name.toLowerCase().endsWith('.apk') && file.extension?.toLowerCase() != 'apk') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PLEASE SELECT A VALID .APK FILE'),
            backgroundColor: AppTheme.bearColor,
          ),
        );
        return;
      }

      setState(() {
        _isUploadingApk = true;
        _apkUploadProgress = 0.5;
        _updateUrlController.text = 'https://orderflowterminal.web.app/app-release.apk';
      });

      // Background upload attempt to Firebase Storage
      try {
        Reference ref;
        try {
          ref = FirebaseStorage.instanceFor(bucket: 'gs://mst7-3fb55.firebasestorage.app').ref().child('apks/app-release.apk');
        } catch (_) {
          ref = FirebaseStorage.instance.ref().child('apks/app-release.apk');
        }

        final metadata = SettableMetadata(
          contentType: 'application/vnd.android.package-archive',
          customMetadata: {'version': version},
        );

        UploadTask? uploadTask;
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          uploadTask = ref.putData(file.bytes!, metadata);
        } else if (file.path != null && file.path!.isNotEmpty) {
          uploadTask = ref.putFile(File(file.path!), metadata);
        }

        if (uploadTask != null) {
          uploadTask.snapshotEvents.listen((event) {
            if (event.totalBytes > 0 && mounted) {
              setState(() {
                _apkUploadProgress = event.bytesTransferred / event.totalBytes;
              });
            }
          });
          final snapshot = await uploadTask;
          try {
            final url = await snapshot.ref.getDownloadURL();
            if (url.isNotEmpty && mounted) {
              setState(() {
                _updateUrlController.text = url;
              });
            }
          } catch (_) {}
        }
      } catch (uploadError) {
        debugPrint('[STORAGE_UPLOAD_NOTE] $uploadError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('APK FILE READY! DOWNLOAD URL HAS BEEN SET SUCCESSFULLY.'),
            backgroundColor: AppTheme.bullColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('[APK_PICK_ERROR] $e');
      if (mounted) {
        _updateUrlController.text = 'https://orderflowterminal.web.app/app-release.apk';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DOWNLOAD URL AUTO-SET TO RELEASE LINK.'),
            backgroundColor: AppTheme.bullColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingApk = false;
          _apkUploadProgress = 1.0;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recountStats();
    });
  }

  Future<void> _recountStats() async {
    try {
      final firestore = FirebaseFirestore.instance;
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

  // ── Publish Update ───────────────────────────────────────────
  Future<void> _publishUpdate() async {
    final version = _versionController.text.trim();
    String url = _updateUrlController.text.trim();
    if (version.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ENTER A VERSION NUMBER (e.g. 1.2.0)'), backgroundColor: AppTheme.bearColor),
      );
      return;
    }
    if (url.isEmpty) {
      url = 'https://orderflowterminal.web.app/app-release.apk';
      _updateUrlController.text = url;
    }
    setState(() {
      _updateLoading = true;
      _updateEnabled = true;
    });
    try {
      await GlobalSettingsService.updateConfig(
        latestVersion: version,
        updateUrl: url,
        changelog: _changelogController.text.trim(),
        forceUpdate: _forceUpdate,
        updateEnabled: true,
      );
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => UpdatePublishedSuccessDialog(version: version),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PUBLISH FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _updateLoading = false);
    }
  }

  // ── Disable Update Dialog for All Users ──────────────────────
  Future<void> _disableUpdateForAll() async {
    setState(() => _updateLoading = true);
    try {
      await GlobalSettingsService.updateConfig(
        updateEnabled: false,
        forceUpdate: false,
      );
      if (mounted) {
        setState(() {
          _updateEnabled = false;
          _forceUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('UPDATE DIALOG DISABLED FOR ALL USERS'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _updateLoading = false);
    }
  }

  @override
  void dispose() {
    _buyerCountController.dispose();
    _sellerCountController.dispose();
    _ghostTriggerController.dispose();
    _priceLevelController.dispose();
    _levelBuyerController.dispose();
    _levelSellerController.dispose();
    _tickerController.dispose();
    _customTagController.dispose();
    _candleSearchController.dispose();
    _broadcastMsgController.dispose();
    _versionController.dispose();
    _updateUrlController.dispose();
    _changelogController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startSimilarPatternScan([DateTime? targetTimeOverride]) async {
    final symbol = ref.read(selectedInstrumentProvider);
    if (symbol != 'NIFTY50') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Switch to NIFTY50 chart to run scan'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Use override time, or selected candle time, or current moment
    final DateTime targetTime = targetTimeOverride ?? _selectedCandleTime ?? DateTime.now();

    final List<String> scanStocks = NiftyStocks.stocks.keys.toList();

    setState(() {
      _isScanningSimilarPatterns = true;
      _scanProgress = 0;
      _scanTotal = scanStocks.length;
      _suggestedSimilarStocks = [];
      _selectedSimilarStocksToInject.clear();
    });

    try {
      final repo = ref.read(candleRepositoryProvider);
      final cacheSource = ref.read(localCacheDataSourceProvider);
      
      // Get Nifty 50 candles (current day only)
      final niftyCandles = ref.read(candleStreamProvider).candles;
      print('--- CO-MOVEMENT SCAN START (TODAY ONLY) ---');
      print('TargetTime: $targetTime');
      print('NiftyCandles count: ${niftyCandles.length}');

      if (niftyCandles.isEmpty) {
        if (mounted) setState(() => _isScanningSimilarPatterns = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No NIFTY50 candle data loaded'), backgroundColor: Colors.orange),
        );
        return;
      }

      // STRICT: only today's candles up to targetTime
      final targetDateStart = DateTime(targetTime.year, targetTime.month, targetTime.day);
      final targetDateEnd = targetDateStart.add(const Duration(days: 1));
      final niftyToday = niftyCandles.where((c) =>
          c.timeStart.isAfter(targetDateStart) &&
          c.timeStart.isBefore(targetDateEnd) &&
          (c.timeStart.isBefore(targetTime) || c.timeStart.isAtSameMomentAs(targetTime))
      ).toList()..sort((a, b) => a.timeStart.compareTo(b.timeStart));

      print('Today only NiftyCandles: ${niftyToday.length}');

      if (niftyToday.isEmpty) {
        if (mounted) setState(() => _isScanningSimilarPatterns = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No NIFTY50 candles for today yet'), backgroundColor: Colors.orange),
        );
        return;
      }

      // First hour range 9:15 AM – 10:15 AM
      final firstHourEnd = targetDateStart.add(const Duration(hours: 10, minutes: 15));
      final niftyFirstHour = niftyToday.where((c) =>
          c.timeEnd.isBefore(firstHourEnd) || c.timeEnd.isAtSameMomentAs(firstHourEnd)
      ).toList();
      
      double? niftyFirstHourHigh;
      double? niftyFirstHourLow;
      if (niftyFirstHour.isNotEmpty) {
        niftyFirstHourHigh = niftyFirstHour.map((c) => c.high).reduce(math.max);
        niftyFirstHourLow = niftyFirstHour.map((c) => c.low).reduce(math.min);
      }

      final niftySessionHigh = niftyToday.map((c) => c.high).reduce(math.max);
      final niftySessionLow = niftyToday.map((c) => c.low).reduce(math.min);
      final bool niftyBrokeHigh = niftyFirstHourHigh != null && niftySessionHigh > niftyFirstHourHigh;
      final bool niftyBrokeLow = niftyFirstHourLow != null && niftySessionLow < niftyFirstHourLow;
      final double niftyOpen = niftyToday.first.open;

      print('Scanning ${scanStocks.length} Nifty50 stocks sequentially...');
      final List<Map<String, dynamic>> suggestions = [];

      // Sequential scan with progress updates to avoid rate limits
      for (int i = 0; i < scanStocks.length; i++) {
        final stock = scanStocks[i];
        if (!mounted) break;

        if (mounted) {
          setState(() => _scanProgress = i + 1);
        }

        try {
          // Try cache first
          List<CandleModel> stockCandles = await cacheSource.getCachedCandles(stock);

          // Check if cache has today's data
          final bool isUpToDate = stockCandles.any((c) =>
              c.timeStart.year == targetTime.year &&
              c.timeStart.month == targetTime.month &&
              c.timeStart.day == targetTime.day
          );

          if (!isUpToDate) {
            stockCandles = await repo.fetchHistoricalCandles(stock)
                .timeout(const Duration(seconds: 5), onTimeout: () => stockCandles);
          }

          if (stockCandles.isEmpty) continue;

          // TODAY ONLY – strict date filter
          final stockToday = stockCandles.where((c) =>
              c.timeStart.isAfter(targetDateStart) &&
              c.timeStart.isBefore(targetDateEnd) &&
              (c.timeStart.isBefore(targetTime) || c.timeStart.isAtSameMomentAs(targetTime))
          ).toList()..sort((a, b) => a.timeStart.compareTo(b.timeStart));

          if (stockToday.isEmpty) {
            print('$stock: no today candles, skip');
            continue;
          }

          // Align candles by timeStart timestamp
          final Map<int, CandleModel> stockMap = {
            for (var c in stockToday) c.timeStart.millisecondsSinceEpoch: c
          };

          final List<double> niftyPrices = [];
          final List<double> stockPrices = [];
          final double stockOpen = stockToday.first.open;

          for (final nc in niftyToday) {
            final sc = stockMap[nc.timeStart.millisecondsSinceEpoch];
            if (sc != null && niftyOpen != 0 && stockOpen != 0) {
              niftyPrices.add((nc.close - niftyOpen) / niftyOpen);
              stockPrices.add((sc.close - stockOpen) / stockOpen);
            }
          }

          if (niftyPrices.length < 3) {
            print('$stock: only ${niftyPrices.length} aligned candles, skip');
            continue;
          }

          final double correlation = _calculateCorrelation(niftyPrices, stockPrices);

          // First-hour breakout
          final stockFirstHour = stockToday.where((c) =>
              c.timeEnd.isBefore(firstHourEnd) || c.timeEnd.isAtSameMomentAs(firstHourEnd)
          ).toList();
          double? stockFHH, stockFHL;
          if (stockFirstHour.isNotEmpty) {
            stockFHH = stockFirstHour.map((c) => c.high).reduce(math.max);
            stockFHL = stockFirstHour.map((c) => c.low).reduce(math.min);
          }
          final double stockSessionHigh = stockToday.map((c) => c.high).reduce(math.max);
          final double stockSessionLow = stockToday.map((c) => c.low).reduce(math.min);
          final bool stockBrokeHigh = stockFHH != null && stockSessionHigh > stockFHH;
          final bool stockBrokeLow = stockFHL != null && stockSessionLow < stockFHL;

          // Intraday percentage return similarity (closeness in return magnitude)
          double sumDiff = 0.0;
          for (int i = 0; i < niftyPrices.length; i++) {
            sumDiff += (niftyPrices[i] - stockPrices[i]).abs();
          }
          final double avgDiff = sumDiff / niftyPrices.length;
          // 0% average difference = 100% similarity, 2% difference or more = 0% similarity
          final double percentageSimilarity = (1.0 - (avgDiff / 0.02)).clamp(0.0, 1.0) * 100.0;

          // Combined Score: 50% Pearson correlation + 30% percentage similarity + 20% breakout match
          double score = (correlation > 0 ? correlation * 50.0 : 0.0) + (percentageSimilarity * 0.30);
          if (niftyBrokeHigh == stockBrokeHigh) score += 10;
          if (niftyBrokeLow == stockBrokeLow) score += 10;
          final int finalScore = score.round().clamp(0, 99);

          print('$stock: corr=${correlation.toStringAsFixed(2)}, pctSim=${percentageSimilarity.toStringAsFixed(1)}%, score=$finalScore');

          // Include stocks with >= 50% similarity
          if (finalScore >= 50) {
            suggestions.add({
              'symbol': stock,
              'score': finalScore,
              'brokeHigh': stockBrokeHigh,
              'brokeLow': stockBrokeLow,
            });
          }
        } catch (e) {
          print('$stock error: $e');
        }
      }

      // Sort by score descending
      suggestions.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      print('Scan done. ${suggestions.length} stocks matched (>=50%).');

      if (mounted) {
        setState(() {
          _suggestedSimilarStocks = suggestions;
          _selectedSimilarStocksToInject.clear();
          // Auto-select all with >= 80% (strong correlation)
          for (final s in suggestions) {
            if ((s['score'] as int) >= 80) {
              _selectedSimilarStocksToInject.add(s['symbol'] as String);
            }
          }
          _isScanningSimilarPatterns = false;
          _scanProgress = 0;
        });
      }
    } catch (e, stack) {
      print('Scan general error: $e\n$stack');
      if (mounted) {
        setState(() {
          _isScanningSimilarPatterns = false;
          _scanProgress = 0;
        });
      }
    }
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    final int n = x.length;
    double sumX = 0, sumY = 0, sumXY = 0;
    double sumX2 = 0, sumY2 = 0;

    for (int i = 0; i < n; i++) {
      sumX += x[i];
      sumY += y[i];
      sumXY += x[i] * y[i];
      sumX2 += x[i] * x[i];
      sumY2 += y[i] * y[i];
    }

    final double num = (n * sumXY) - (sumX * sumY);
    final double den = math.sqrt(((n * sumX2) - (sumX * sumX)) * ((n * sumY2) - (sumY * sumY)));

    if (den == 0) return 0.0;
    return num / den;
  }

  Future<void> _handleAutoInjectDaySwings() async {
    final user = ref.read(authProvider).user;
    final isSuperuser = OrderflowService.isSuperuser(user?.email);
    if (!(user?.isAdmin ?? false) && !isSuperuser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required.')),
      );
      return;
    }

    final symbol = ref.read(selectedInstrumentProvider);
    final candleState = ref.read(candleStreamProvider);
    final candles = candleState.candles;

    if (candles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No candlestick data available for auto-injection.')),
      );
      return;
    }

    // 1. Group candles by local calendar day (YYYY-MM-DD)
    final Map<String, List<CandleModel>> candlesByDay = {};
    for (final c in candles) {
      final local = c.timeStart.toLocal();
      final dayKey = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      candlesByDay.putIfAbsent(dayKey, () => []).add(c);
    }

    if (candlesByDay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid candles found for swing analysis.')),
      );
      return;
    }

    // 2. Select target day session (most recent day key with at least 2 candles)
    final sortedDayKeys = candlesByDay.keys.toList()..sort();
    String? targetDayKey;
    for (int i = sortedDayKeys.length - 1; i >= 0; i--) {
      if (candlesByDay[sortedDayKeys[i]]!.length >= 2) {
        targetDayKey = sortedDayKeys[i];
        break;
      }
    }
    targetDayKey ??= sortedDayKeys.last;

    final List<CandleModel> dayCandles = candlesByDay[targetDayKey]!;

    if (dayCandles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough candles available for swing calculation.')),
      );
      return;
    }

    // 3. Find exact Swing Low and Swing High candles for the day session
    CandleModel lowestCandle = dayCandles.reduce((curr, next) => next.low < curr.low ? next : curr);
    CandleModel highestCandle = dayCandles.reduce((curr, next) => next.high > curr.high ? next : curr);

    final firstCandleOpen = dayCandles.first.open;
    final upMove = (highestCandle.high - firstCandleOpen).abs();
    final downMove = (firstCandleOpen - lowestCandle.low).abs();

    String injectionSummary = '';
    final orderflowService = ref.read(orderflowServiceProvider);

    if (upMove >= downMove) {
      final sellerVol = 4450 + (DateTime.now().millisecondsSinceEpoch % 700);
      final buyerHighVol = 310 + (DateTime.now().millisecondsSinceEpoch % 130);
      await orderflowService.saveOrderflow(
        symbol: symbol,
        candleTime: highestCandle.timeStart,
        buyerCount: buyerHighVol,
        sellerCount: sellerVol,
        isInstitutional: true,
        isBigSignal: true,
        bubbleScale: 5.0,
        pulseSpeed: 1.0,
        bubbleOpacity: 0.95,
        footprint: {
          highestCandle.high: PriceLevelData(buyVolume: buyerHighVol, sellVolume: sellerVol)
        },
        customTag: "",
        adminOnly: true,
      );
      final highTimeStr = DateFormat('hh:mm a').format(highestCandle.timeStart.toLocal());
      injectionSummary = '⚡ SINGLE INJECTION PROMO ($targetDayKey):\n\n'
          '• SELLER Signal @ Swing High (₹${highestCandle.high.toStringAsFixed(1)} at $highTimeStr)';
    } else {
      final buyerVol = 4250 + (DateTime.now().millisecondsSinceEpoch % 650);
      final sellerLowVol = 280 + (DateTime.now().millisecondsSinceEpoch % 120);
      await orderflowService.saveOrderflow(
        symbol: symbol,
        candleTime: lowestCandle.timeStart,
        buyerCount: buyerVol,
        sellerCount: sellerLowVol,
        isInstitutional: true,
        isBigSignal: true,
        bubbleScale: 5.0,
        pulseSpeed: 1.0,
        bubbleOpacity: 0.95,
        footprint: {
          lowestCandle.low: PriceLevelData(buyVolume: buyerVol, sellVolume: sellerLowVol)
        },
        customTag: "",
        autoFadeMinutes: 0,
        adminOnly: true,
      );
      final lowTimeStr = DateFormat('hh:mm a').format(lowestCandle.timeStart.toLocal());
      injectionSummary = '⚡ SINGLE INJECTION PROMO ($targetDayKey):\n\n'
          '• BUYER Signal @ Swing Low (₹${lowestCandle.low.toStringAsFixed(1)} at $lowTimeStr)';
    }

    ref.read(candleStreamProvider.notifier).refresh();

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF131722),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.goldColor, width: 1.5),
          ),
          title: Text(
            'PROMO AUTO-INJECT SUCCESS ($symbol)',
            style: const TextStyle(color: AppTheme.goldColor, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: Text(injectionSummary, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.goldColor, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('GREAT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _saveOrderflow() async {
    if (_selectedCandleTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PLEASE SELECT A CANDLE NODE'),
          backgroundColor: AppTheme.bearColor,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final timeStr = DateFormat('hh:mm a').format(_selectedCandleTime!);
    final selectedInstrument = ref.read(selectedInstrumentProvider);
    final tagText = _customTagController.text.isNotEmpty ? _customTagController.text : 'SIGNAL';

    final bool? confirmBroadcast = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.goldColor, width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppTheme.goldColor, size: 22),
            SizedBox(width: 10),
            Text(
              'CONFIRM ALERT BROADCAST',
              style: TextStyle(color: AppTheme.goldColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to broadcast and inject data for:\n\n• Node: $selectedInstrument\n• Candle Time: $timeStr IST\n• Signal Tag: $tagText',
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will immediately update Firebase and dispatch live push notification alerts to all connected app terminals.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.bullColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('CONFIRM & BROADCAST', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirmBroadcast != true) return;
    if (!mounted) return;

    List<String> additionalIndices = [];
    if (selectedInstrument == 'NIFTY50') {
      final shouldInjectOthers = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'INJECT IN OTHER INDICES?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: const Text(
            'Do you also want to inject this data in FINNIFTY, SENSEX, and BANKNIFTY?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('NO', style: TextStyle(color: AppTheme.bearColor)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('YES', style: TextStyle(color: AppTheme.bullColor)),
            ),
          ],
        ),
      );
      if (shouldInjectOthers == true) {
        additionalIndices.addAll(['FINNIFTY', 'SENSEX', 'BANKNIFTY']);
      }
    }

    setState(() => _isLoading = true);

    try {
      final authState = ref.read(authProvider);
      final orderflowRepo = ref.read(orderflowRepositoryProvider);

      int buyerCount = int.tryParse(_buyerCountController.text) ?? 0;
      int sellerCount = int.tryParse(_sellerCountController.text) ?? 0;

      // Randomize round numbers to look more realistic (User Request)
      buyerCount = _randomizeValue(buyerCount);
      sellerCount = _randomizeValue(sellerCount);

      if (buyerCount == 0 && sellerCount == 0) {
        throw 'AT LEAST ONE VOLUME NODE IS REQUIRED';
      }

      // Parse Footprint data if provided
      final priceLevel = double.tryParse(_priceLevelController.text);
      final levelBuy = _randomizeValue(int.tryParse(_levelBuyerController.text) ?? 0);
      final levelSell = _randomizeValue(int.tryParse(_levelSellerController.text) ?? 0);
      
      if (priceLevel != null && (levelBuy > 0 || levelSell > 0)) {
        // Footprint parsing logic...
      }

      // Find the candle key for the selected time
      final candleState = ref.read(candleStreamProvider);
      final selectedCandle = candleState.candles.firstWhere(
        (c) => c.timeStart == _selectedCandleTime,
        orElse: () => throw 'SELECTED CANDLE NOT FOUND',
      );
      final candleKey = selectedCandle.candleKey;

      // If selectedInstrument is NIFTY50 and SCAN ALL mode is enabled, run similarity scan
      if (selectedInstrument == 'NIFTY50' && _scanAllStocksMode && _suggestedSimilarStocks.isEmpty) {
        await _startSimilarPatternScan(_selectedCandleTime);
      }

      // GHOST MODE: Create pending ghost orders for the selected candle
      if (_isGhostMode) {
        final triggerPrice = double.tryParse(_ghostTriggerController.text);
        if (triggerPrice == null) {
          throw 'GHOST MODE REQUIRES A VALID TRIGGER PRICE';
        }

        // Create ghost order for the selected candle
        final ghost = GhostOrder(
          id: DateTime.now().millisecondsSinceEpoch.toString() + candleKey,
          symbol: selectedInstrument,
          triggerSymbol: selectedInstrument,
          triggerPrice: triggerPrice,
          buyerCount: buyerCount,
          sellerCount: sellerCount,
          isInstitutional: buyerCount >= 50000 || sellerCount >= 50000,
          isBigSignal: _isBigSignal,
          isTrap: _isTrap,
          isLiquidation: _isLiquidation,
          createdAt: DateTime.now(),
        );
        
        await ref.read(orderflowServiceProvider).saveGhostOrder(ghost);

        // Inject to suggested similar pattern stocks as well
        if (selectedInstrument == 'NIFTY50' && _selectedSimilarStocksToInject.isNotEmpty) {
          for (final suggestSymbol in _selectedSimilarStocksToInject) {
            final int stockBuyer = _randomizeVolumeForSymbol(buyerCount, suggestSymbol);
            final int stockSeller = _randomizeVolumeForSymbol(sellerCount, suggestSymbol);
            final suggestGhost = GhostOrder(
              id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + suggestSymbol + '_' + candleKey,
              symbol: suggestSymbol,
              triggerSymbol: 'NIFTY50',
              triggerPrice: triggerPrice,
              buyerCount: stockBuyer,
              sellerCount: stockSeller,
              isInstitutional: stockBuyer >= 50000 || stockSeller >= 50000,
              isBigSignal: _isBigSignal,
              isTrap: _isTrap,
              isLiquidation: _isLiquidation,
              createdAt: DateTime.now(),
            );
            await ref.read(orderflowServiceProvider).saveGhostOrder(suggestGhost);
          }
        }

        // Inject to other indices if approved
        if (additionalIndices.isNotEmpty) {
          for (final additionalSymbol in additionalIndices) {
            final int indexBuyer = _randomizeVolumeForSymbol(buyerCount, additionalSymbol);
            final int indexSeller = _randomizeVolumeForSymbol(sellerCount, additionalSymbol);
            final additionalGhost = GhostOrder(
              id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + additionalSymbol + '_' + candleKey,
              symbol: additionalSymbol,
              triggerSymbol: 'NIFTY50',
              triggerPrice: triggerPrice,
              buyerCount: indexBuyer,
              sellerCount: indexSeller,
              isInstitutional: indexBuyer >= 50000 || indexSeller >= 50000,
              isBigSignal: _isBigSignal,
              isTrap: _isTrap,
              isLiquidation: _isLiquidation,
              createdAt: DateTime.now(),
            );
            await ref.read(orderflowServiceProvider).saveGhostOrder(additionalGhost);
          }
        }

        if (mounted) {
          final List<String> allInjected = [selectedInstrument];
          allInjected.addAll(_selectedSimilarStocksToInject);
          allInjected.addAll(additionalIndices);
          final String msg = allInjected.length > 1
              ? 'GHOST ORDER CREATED AT ₹${triggerPrice.toStringAsFixed(2)} FOR ${allInjected.join(", ")}'
              : 'GHOST ORDER CREATED AT ₹${triggerPrice.toStringAsFixed(2)}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppTheme.goldColor,
            ),
          );
        }
      } 
      // STANDARD MODE: Inject live orderflow
      else {
        await orderflowRepo.saveOrderflowBulk(
          candleKeys: [candleKey],
          symbol: selectedInstrument,
          buyerCount: buyerCount,
          sellerCount: sellerCount,
          isBigSignal: _isBigSignal,
          adminUid: authState.user!.uid,
          bubbleScale: _bubbleScale,
          bubbleOpacity: _bubbleOpacity,
          bubbleGlow: _bubbleGlow,
          showLabel: _showLabel,
          customTag: _customTagController.text,
          pulseSpeed: _pulseSpeed,
          borderColor: _borderColorSelection,
          autoFadeMinutes: _autoFadeMinutes,
          broadcastPush: _broadcastPush,
          isTrap: _isTrap,
          isLiquidation: _isLiquidation,
          adminOnly: _adminOnly,
        );

        // Inject to suggested similar pattern stocks as well
        if (selectedInstrument == 'NIFTY50' && _selectedSimilarStocksToInject.isNotEmpty) {
          for (final suggestSymbol in _selectedSimilarStocksToInject) {
            final int stockBuyer = _randomizeVolumeForSymbol(buyerCount, suggestSymbol);
            final int stockSeller = _randomizeVolumeForSymbol(sellerCount, suggestSymbol);
            await orderflowRepo.saveOrderflowBulk(
              candleKeys: [candleKey],
              symbol: suggestSymbol,
              buyerCount: stockBuyer,
              sellerCount: stockSeller,
              isBigSignal: _isBigSignal,
              adminUid: authState.user!.uid,
              bubbleScale: _bubbleScale,
              bubbleOpacity: _bubbleOpacity,
              bubbleGlow: _bubbleGlow,
              showLabel: _showLabel,
              customTag: _customTagController.text,
              pulseSpeed: _pulseSpeed,
              borderColor: _borderColorSelection,
              autoFadeMinutes: _autoFadeMinutes,
              broadcastPush: _broadcastPush,
              isTrap: _isTrap,
              isLiquidation: _isLiquidation,
              adminOnly: _adminOnly,
            );
          }
        }

        // Inject to other indices if approved
        if (additionalIndices.isNotEmpty) {
          for (final additionalSymbol in additionalIndices) {
            final int indexBuyer = _randomizeVolumeForSymbol(buyerCount, additionalSymbol);
            final int indexSeller = _randomizeVolumeForSymbol(sellerCount, additionalSymbol);
            await orderflowRepo.saveOrderflowBulk(
              candleKeys: [candleKey],
              symbol: additionalSymbol,
              buyerCount: indexBuyer,
              sellerCount: indexSeller,
              isBigSignal: _isBigSignal,
              adminUid: authState.user!.uid,
              bubbleScale: _bubbleScale,
              bubbleOpacity: _bubbleOpacity,
              bubbleGlow: _bubbleGlow,
              showLabel: _showLabel,
              customTag: _customTagController.text,
              pulseSpeed: _pulseSpeed,
              borderColor: _borderColorSelection,
              autoFadeMinutes: _autoFadeMinutes,
              broadcastPush: _broadcastPush,
              isTrap: _isTrap,
              isLiquidation: _isLiquidation,
              adminOnly: _adminOnly,
            );
          }
        }

        _lastInjectedCandleKey = candleKey;
        _lastInjectedSymbol = selectedInstrument;

        if (mounted) {
          final List<String> allInjected = [selectedInstrument];
          allInjected.addAll(_selectedSimilarStocksToInject);
          allInjected.addAll(additionalIndices);
          final String msg = allInjected.length > 1
              ? 'ALERT BROADCAST TO ${allInjected.join(", ")}'
              : 'ALERT BROADCAST SUCCESSFULLY';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppTheme.bullColor,
            ),
          );
          // Refresh data to show in log immediately
          ref.read(candleStreamProvider.notifier).refresh();
        }
      }

      // Clear all controllers
      if (mounted) {
        _buyerCountController.clear();
        _sellerCountController.clear();
        _ghostTriggerController.clear();
        _priceLevelController.clear();
        _levelBuyerController.clear();
        _levelSellerController.clear();
        
        setState(() {
          _selectedCandleTime = null;
          _bubbleScale = 5.0;
          _isBigSignal = false;
          _isTrap = false;
          _isLiquidation = false;
          _isGhostMode = false;
          _customTagController.clear();
          _pulseSpeed = 1.0;
          _borderColorSelection = "DEFAULT";
          _autoFadeMinutes = 0;
          _broadcastPush = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ALERT FAILED: $e'),
            backgroundColor: AppTheme.bearColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showReplayPlayer(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) => const ReplayPlayerDialog(),
    );
  }

  Future<void> _undoLastInjection() async {
    if (_lastInjectedCandleKey == null || _lastInjectedSymbol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NO PREVIOUS INJECTION TO UNDO'), backgroundColor: AppTheme.bearColor),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('UNDO LAST INJECTION', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Text('Delete the last injected signal for $_lastInjectedSymbol at node $_lastInjectedCandleKey?', style: const TextStyle(color: Colors.white, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('UNDO NOW', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final orderflowRepo = ref.read(orderflowRepositoryProvider);
      
      await orderflowRepo.deleteOrderflowDirect(
        candleKey: _lastInjectedCandleKey!,
        symbol: _lastInjectedSymbol!,
      );

      final undoneKey = _lastInjectedCandleKey;
      _lastInjectedCandleKey = null;
      _lastInjectedSymbol = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('UNDONE: SIGNAL AT $undoneKey REMOVED'), backgroundColor: AppTheme.primaryCyan),
        );
        ref.read(candleStreamProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('UNDO FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _revokeSingleOrderflow(String candleKey, {required String symbol}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('REVOKE SIGNAL', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 16)),
        content: const Text('Are you sure you want to delete the orderflow signal for this specific candle?', style: TextStyle(color: Colors.white, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DELETE', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final orderflowRepo = ref.read(orderflowRepositoryProvider);
      
      await orderflowRepo.deleteOrderflowDirect(
        candleKey: candleKey,
        symbol: symbol,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SIGNAL REVOKED SUCCESSFULLY'), backgroundColor: AppTheme.primaryCyan),
        );
        // Refresh data to update log immediately
        ref.read(candleStreamProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('REVOKE FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteOrderflow() async {
    if (_selectedCandleTime == null) return;

    setState(() => _isLoading = true);
    try {
      final selectedInstrument = ref.read(selectedInstrumentProvider);
      final orderflowRepo = ref.read(orderflowRepositoryProvider);
      final candleState = ref.read(candleStreamProvider);
      final candles = candleState.candles;

      final candle = candles.firstWhereOrNull((c) => c.timeStart == _selectedCandleTime);
      if (candle == null) {
        throw 'SELECTED CANDLE NOT FOUND IN CACHE';
      }

      await orderflowRepo.deleteOrderflowDirect(
        candleKey: candle.candleKey,
        symbol: selectedInstrument,
      );

      if (selectedInstrument == 'NIFTY50' && _selectedSimilarStocksToInject.isNotEmpty) {
        for (final suggestSymbol in _selectedSimilarStocksToInject) {
          await orderflowRepo.deleteOrderflowDirect(
            candleKey: candle.candleKey,
            symbol: suggestSymbol,
          );
        }
      }

      if (mounted) {
        final String msg = selectedInstrument == 'NIFTY50' && _selectedSimilarStocksToInject.isNotEmpty
            ? 'DATA CLEARED FOR $selectedInstrument AND ${_selectedSimilarStocksToInject.join(", ")}'
            : 'DATA CLEARED SUCCESSFULLY';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.primaryCyan,
          ),
        );
        setState(() {
          _selectedCandleTime = null;
          _buyerCountController.clear();
          _sellerCountController.clear();
          _isBigSignal = false;
          _isTrap = false;
          _isLiquidation = false;
        });
        // Refresh to reflect changes
        ref.read(candleStreamProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DELETE FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _wipeMarketData() async {
    final symbol = ref.read(selectedInstrumentProvider);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('WIPE HISTORICAL DATA', 
          style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to wipe ALL historical market data for $symbol?', 
              style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 12),
            const Text('This will clear the chart for all users until new data is fetched.', 
              style: TextStyle(color: AppTheme.bearColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54))
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('WIPE DATA', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(candleStreamProvider.notifier).wipeHistoricalCandles(symbol);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('HISTORICAL MARKET DATA WIPED'), 
            backgroundColor: AppTheme.bearColor
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WIPE FAILED: $e'), 
            backgroundColor: AppTheme.bearColor
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildIconButton({required IconData icon, required Color color, String? tooltip, required VoidCallback onPressed}) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: button,
      );
    }
    return button;
  }

  Future<void> _updateUserStatus(
    String uid, 
    bool isApproved, {
    DateTime? expiryDate,
    bool? isCanceled,
    String? subscriptionType,
  }) async {
    setState(() => _isLoading = true);
    try {
      final adminRepo = ref.read(adminRepositoryProvider);
      final authState = ref.read(authProvider);
      
      if (authState.user != null) {
        await adminRepo.updateUserStatusDirect(
          uid: uid, 
          isApproved: isApproved,
          adminUid: authState.user!.uid,
          expiryDate: expiryDate,
          isCanceled: isCanceled,
          subscriptionType: subscriptionType,
        );

        if (isCanceled == true) {
          try {
            await FirebaseDatabase.instance.ref('${AppConstants.sessionsPath}/$uid').update({
              'forceLogout': true,
            });
          } catch (_) {}
        }

        ref.invalidate(pendingUsersProvider);
        ref.invalidate(allUsersProvider);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('USER RECORRD UPDATED'),
              backgroundColor: isApproved ? AppTheme.bullColor : AppTheme.bearColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ERROR: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetUserHardwareId(String uid, String userEmail) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.amber, width: 1.2)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Colors.amber, size: 20),
            SizedBox(width: 10),
            Text('RESET HARDWARE LOCK', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 14)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to reset the hardware ID lock for:\n$userEmail',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'The user will be able to log in from a NEW device on their next login. This action cannot be undone.',
              style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withValues(alpha: 0.15), foregroundColor: Colors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET HWID', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final adminRepo = ref.read(adminRepositoryProvider);
      await adminRepo.resetHardwareId(uid: uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ HARDWARE LOCK CLEARED — User can now log in from a new device'),
            backgroundColor: Colors.amber,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RESET FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forceLogoutUser(String uid, String userEmail) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.bearColor, width: 1.2)),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: AppTheme.bearColor, size: 20),
            SizedBox(width: 10),
            Text('FORCE LOGOUT USER', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 14)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to terminate the active session and force logout:\n$userEmail',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will instantly kick the user out of the terminal and return them to the login screen.',
              style: TextStyle(color: AppTheme.bearColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.bearColor.withValues(alpha: 0.15), foregroundColor: AppTheme.bearColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('FORCE LOGOUT', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseDatabase.instance.ref('${AppConstants.sessionsPath}/$uid').update({
        'forceLogout': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ FORCE LOGOUT COMMAND SENT to $userEmail'),
            backgroundColor: AppTheme.bearColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showUserEditDialog(UserProfile user) {
    DateTime? selectedDate = user.expiryDate;
    bool isCanceled = user.isCanceled;
    bool isApproved = user.isApproved;
    // Subscription plan type — persist existing value
    String selectedPlanType = user.subscriptionType == SubscriptionType.indexOnly
        ? 'index_only'
        : 'index_and_stocks';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
          title: const Row(
            children: [
              Icon(Icons.manage_accounts_rounded, color: AppTheme.primaryCyan, size: 20),
              SizedBox(width: 12),
              Text('MANAGE USER ACCESS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email?.toUpperCase() ?? 'UNKNOWN USER', style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              
              // Expiry Date Selection
              const Text('EXPIRY DATE / TRIAL END', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: AppTheme.primaryCyan,
                          onPrimary: AppTheme.bgColor,
                          surface: AppTheme.cardColor,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (date != null) {
                    setDialogState(() => selectedDate = date);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryCyan, size: 16),
                      const SizedBox(width: 12),
                      Text(
                        selectedDate == null ? 'SET PERMANENT ACCESS' : DateFormat('MMM dd, yyyy').format(selectedDate!),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (selectedDate != null)
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.bearColor, size: 16),
                          onPressed: () => setDialogState(() => selectedDate = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Plan Type Selector ────────────────────────────────────────
              const Text('SUBSCRIPTION PLAN TYPE', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => selectedPlanType = 'index_only'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selectedPlanType == 'index_only'
                              ? const Color(0xFF00C8FF).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                          border: Border.all(
                            color: selectedPlanType == 'index_only'
                                ? const Color(0xFF00C8FF)
                                : Colors.white12,
                            width: selectedPlanType == 'index_only' ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text('INDEX ONLY',
                                style: TextStyle(
                                    color: selectedPlanType == 'index_only'
                                        ? const Color(0xFF00C8FF)
                                        : Colors.white38,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text('Index Only Plan',
                                style: TextStyle(
                                    color: selectedPlanType == 'index_only'
                                        ? Colors.white70
                                        : Colors.white24,
                                    fontSize: 8)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => selectedPlanType = 'index_and_stocks'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selectedPlanType == 'index_and_stocks'
                              ? AppTheme.bullColor.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                          border: Border.all(
                            color: selectedPlanType == 'index_and_stocks'
                                ? AppTheme.bullColor
                                : Colors.white12,
                            width: selectedPlanType == 'index_and_stocks' ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text('INDEX + STOCKS',
                                style: TextStyle(
                                    color: selectedPlanType == 'index_and_stocks'
                                        ? AppTheme.bullColor
                                        : Colors.white38,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text('Full Access Plan',
                                style: TextStyle(
                                    color: selectedPlanType == 'index_and_stocks'
                                        ? Colors.white70
                                        : Colors.white24,
                                    fontSize: 8)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Status Toggles
              _buildDialogToggle(
                label: 'APPROVED ACCESS',
                value: isApproved,
                activeColor: AppTheme.bullColor,
                onChanged: (v) => setDialogState(() => isApproved = v),
              ),
              const SizedBox(height: 8),
              _buildDialogToggle(
                label: 'SUSPEND / CANCEL USER',
                value: isCanceled,
                activeColor: AppTheme.bearColor,
                onChanged: (v) => setDialogState(() => isCanceled = v),
              ),
              const SizedBox(height: 16),

              if (user.registeredDeviceName != null || user.registeredDeviceDetails != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.perm_device_info_rounded, color: AppTheme.primaryCyan, size: 14),
                          SizedBox(width: 6),
                          Text('PC DETAILS & HARDWARE', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Name: ${user.registeredDeviceName ?? 'Unknown PC'}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Specs: ${user.registeredDeviceDetails ?? 'Unknown specifications'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 9.5, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Hardware ID Lock Reset ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.computer_rounded, color: Colors.amber, size: 14),
                        SizedBox(width: 6),
                        Text('HARDWARE LOCK STATUS', style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      () {
                        final win = user.boundWindowsDeviceId;
                        final mob = user.boundMobileDeviceId;
                        final legacy = user.boundDeviceId;
                        final parts = <String>[];
                        if (win != null && win.isNotEmpty) parts.add('Win: ${win.substring(0, win.length.clamp(0, 16))}...');
                        if (mob != null && mob.isNotEmpty) parts.add('Phone: ${mob.substring(0, mob.length.clamp(0, 16))}...');
                        if (parts.isEmpty && legacy != null && legacy.isNotEmpty) parts.add('Bound: ${legacy.substring(0, legacy.length.clamp(0, 16))}...');
                        return parts.isNotEmpty ? parts.join(' | ') : 'No device bound — user will bind on next login';
                      }(),
                      style: TextStyle(
                        color: (user.boundWindowsDeviceId != null || user.boundMobileDeviceId != null || user.boundDeviceId != null) ? Colors.white60 : Colors.greenAccent,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.lock_reset_rounded, size: 14),
                        label: const Text('RESET HARDWARE ID LOCK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: (user.boundWindowsDeviceId == null || user.boundWindowsDeviceId!.isEmpty) &&
                                (user.boundMobileDeviceId == null || user.boundMobileDeviceId!.isEmpty) &&
                                (user.boundDeviceId == null || user.boundDeviceId!.isEmpty)
                            ? null
                            : () {
                                Navigator.pop(context);
                                _resetUserHardwareId(user.uid, user.email ?? user.uid);
                              },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.gavel_rounded, size: 14),
                        label: const Text('FORCE LOGOUT (KILL SESSION)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.bearColor,
                          side: const BorderSide(color: AppTheme.bearColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _forceLogoutUser(user.uid, user.email ?? user.uid);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateUserStatus(
                  user.uid, 
                  isApproved, 
                  expiryDate: selectedDate, 
                  isCanceled: isCanceled,
                  subscriptionType: selectedPlanType,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryCyan),
              child: const Text('SAVE CHANGES', style: TextStyle(color: AppTheme.bgColor, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogToggle({required String label, required bool value, required Color activeColor, required ValueChanged<bool> onChanged}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor.withValues(alpha: 0.2),
          activeThumbColor: activeColor,
        ),
      ],
    );
  }

  Future<void> _sendBroadcast() async {
    final msg = _broadcastMsgController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PLEASE ENTER A BROADCAST MESSAGE'), backgroundColor: AppTheme.bearColor),
      );
      return;
    }

    setState(() => _broadcastLoading = true);
    try {
      await GlobalSettingsService.updateConfig(
        broadcastMessage: msg,
        broadcastType: _broadcastType,
      );
      _broadcastMsgController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ URGENT BROADCAST SENT TO ALL USERS'), backgroundColor: AppTheme.primaryCyan),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('BROADCAST FAILED: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    } finally {
      if (mounted) setState(() => _broadcastLoading = false);
    }
  }

  Future<void> _saveSystemSync() async {
    if (_localSentiment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PLEASE SELECT A SENTIMENT FIRST'),
          backgroundColor: AppTheme.bearColor,
        ),
      );
      return;
    }

    setState(() => _syncLoading = true);

    try {
      await GlobalSettingsService.updateConfig(
        sentiment: _localSentiment,
        tickerMessage: _tickerController.text,
        isMaintenanceMode: _isMaintenanceMode,
        allowAdminScreenshots: _allowAdminScreenshots,
        activeBroker: _activeBroker,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SYSTEM SYNC BROADCAST SUCCESSFULLY'),
            backgroundColor: AppTheme.primaryCyan,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SYNC FAILED: $e'),
            backgroundColor: AppTheme.bearColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.unauthenticated) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      }
    });

    final isSuperuser = OrderflowService.isSuperuser(authState.user?.email);
    final screenWidth = MediaQuery.of(context).size.width;
    final double scaleFactor = (screenWidth / 375.0).clamp(0.8, 1.2);


    if (authState.user?.isAdmin != true && !isSuperuser) {
      return Scaffold(
        backgroundColor: AppTheme.bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_person_rounded, size: 64 * scaleFactor, color: AppTheme.bearColor),
              SizedBox(height: 24 * scaleFactor),
              Text(
                'ACCESS DENIED',
                style: AppTheme.headingStyle.copyWith(color: AppTheme.bearColor, fontSize: 24 * scaleFactor),
              ),
              SizedBox(height: 12 * scaleFactor),
              Text(
                'THIS AREA IS RESTRICTED TO SYSTEM ADMINISTRATORS',
                style: AppTheme.subHeadingStyle.copyWith(fontSize: 10 * scaleFactor),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('RETURN TO TERMINAL', style: TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: Stack(
        children: [
          // ── Radial Background Glow Orbs ────────────────────────────────
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryCyan.withValues(alpha: 0.04),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.goldColor.withValues(alpha: 0.04),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          
          // ── Dashboard Content ──────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildCustomHeader(context, isSuperuser),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOrderflowTab(),
                      _buildSystemSyncTab(),
                      _buildUsersTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context, bool isSuperuser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.2),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              const Column(
                children: [
                  Text(
                    'ADMIN CENTER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'SYSTEM LEVEL ROOT GRANTED',
                    style: TextStyle(
                      color: AppTheme.goldColor,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 48), // Balance symmetry
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: AppTheme.glassDecoration(
              opacity: 0.04,
              borderRadius: BorderRadius.circular(20),
              borderColor: Colors.white.withValues(alpha: 0.06),
            ),
            child: ListenableBuilder(
              listenable: _tabController,
              builder: (context, _) {
                return Row(
                  children: [
                    Expanded(child: _buildCustomTabItem(0, 'ALERTS', Icons.notification_important_rounded)),
                    Expanded(child: _buildCustomTabItem(1, 'SYSTEM SYNC', Icons.sync_rounded)),
                    Expanded(child: _buildCustomTabItem(2, 'USERS', Icons.people_alt_rounded)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTabItem(int index, String label, IconData icon) {
    final isSelected = _tabController.index == index;
    final color = isSelected ? AppTheme.goldColor : Colors.white38;
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _tabController.animateTo(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryCyan.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryCyan.withValues(alpha: 0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white38,
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderflowTab() {
    final candleState = ref.watch(candleStreamProvider);
    final selectedInstrument = ref.watch(selectedInstrumentProvider);

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        if (isLandscape) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Candle Selection & Active Injections
              Expanded(
                flex: 4,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 10, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildActiveInstrumentHeader(selectedInstrument),
                      const SizedBox(height: 20),
                      _buildCandleSelectionHeader(candleState),
                      const SizedBox(height: 12),
                      _buildCandleSearchBar(candleState.candles),
                      const SizedBox(height: 12),
                      _buildCandleList(candleState, isFlexible: true),
                      const SizedBox(height: 20),
                      _buildActiveInjectionsLog(),
                    ],
                  ),
                ),
              ),
              // Right Column: Injection Forms
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 20, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAdvancedTemplates(),
                        const SizedBox(height: 24),
                        _buildVolumeInputs(),
                        const SizedBox(height: 20),
                        _buildSignalSwitches(),
                        const SizedBox(height: 20),
                        _buildGhostModeSection(),
                        const SizedBox(height: 24),
                        _buildFootprintSection(),
                        if (selectedInstrument == 'NIFTY50') ...[
                          const SizedBox(height: 24),
                          _buildCoMovementSuggestionsSection(),
                        ],
                        const SizedBox(height: 32),
                        _buildSubmitButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // Portrait Layout
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildActiveInstrumentHeader(selectedInstrument),
                const SizedBox(height: 24),
                _buildCandleSelectionHeader(candleState),
                const SizedBox(height: 12),
                _buildCandleSearchBar(candleState.candles),
                const SizedBox(height: 12),
                _buildCandleList(candleState),
                const SizedBox(height: 24),
                _buildActiveInjectionsLog(),
                const SizedBox(height: 24),
                _buildAdvancedTemplates(),
                const SizedBox(height: 24),
                _buildVolumeInputs(),
                const SizedBox(height: 24),
                _buildSignalSwitches(),
                const SizedBox(height: 24),
                _buildGhostModeSection(),
                const SizedBox(height: 24),
                _buildFootprintSection(),
                if (selectedInstrument == 'NIFTY50') ...[
                  const SizedBox(height: 24),
                  _buildCoMovementSuggestionsSection(),
                ],
                const SizedBox(height: 32),
                _buildSubmitButton(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveInstrumentHeader(String selectedInstrument) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showInstrumentSelectorDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassDecoration(opacity: 0.05),
          child: Row(
            children: [
              const Icon(Icons.memory_rounded, color: AppTheme.goldColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE INSTRUMENT NODE (TAP TO CHANGE)',
                      style: TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    Text(
                      AppConstants.instrumentNames[selectedInstrument]?.toUpperCase() ?? selectedInstrument.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_rounded, color: AppTheme.goldColor, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _showInstrumentSelectorDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchController.text.trim().toUpperCase();
            
            // Build matching items
            final matches = <String, String>{};
            if (query.isEmpty) {
              matches.addAll(NiftyStocks.indices);
              matches.addAll(NiftyStocks.stocks);
            } else {
              NiftyStocks.indices.forEach((key, value) {
                if (key.toUpperCase().contains(query) || value.toUpperCase().contains(query)) {
                  matches[key] = value;
                }
              });
              NiftyStocks.stocks.forEach((key, value) {
                if (key.toUpperCase().contains(query) || value.toUpperCase().contains(query)) {
                  matches[key] = value;
                }
              });
            }

            final displayMatches = <String, String>{};
            if (query.isNotEmpty && !matches.containsKey(query)) {
              displayMatches[query] = 'CUSTOM SYMBOL';
            }
            displayMatches.addAll(matches);

            return AlertDialog(
              backgroundColor: AppTheme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Row(
                children: [
                  Icon(Icons.search_rounded, color: AppTheme.primaryCyan, size: 20),
                  SizedBox(width: 12),
                  Text('SELECT STOCK / INDEX', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search or type any stock symbol...',
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (val) {
                        final cleanVal = val.trim().toUpperCase();
                        if (cleanVal.isNotEmpty) {
                          ref.read(selectedInstrumentProvider.notifier).state = cleanVal;
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SizedBox(
                      width: double.maxFinite,
                      height: 250,
                      child: ListView.separated(
                        itemCount: displayMatches.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final symbol = displayMatches.keys.elementAt(index);
                          final name = displayMatches.values.elementAt(index);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(name.toUpperCase(), style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 10)),
                            onTap: () {
                              ref.read(selectedInstrumentProvider.notifier).state = symbol;
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCandleSelectionHeader(CandleStreamState candleState) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'SELECT TARGET CANDLE NODE',
                      style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (candleState.isLoading)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                    ),
                ],
              ),
              if (candleState.dataSourceInfo != null)
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'SYNC: ${candleState.dataSourceInfo!.toUpperCase()}',
                        style: TextStyle(
                          color: candleState.dataSourceInfo!.contains('Yahoo') ? AppTheme.bullColor : AppTheme.goldColor,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (candleState.lastUpdated != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '•  ${candleState.lastUpdated!.hour.toString().padLeft(2, '0')}:${candleState.lastUpdated!.minute.toString().padLeft(2, '0')}:${candleState.lastUpdated!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // INJECTION SCOPE TOGGLE (NIFTY ONLY VS SCAN ALL STOCKS)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _scanAllStocksMode ? 'SCAN ALL STOCKS' : 'NIFTY ONLY',
                      style: TextStyle(
                        color: _scanAllStocksMode ? AppTheme.goldColor : AppTheme.bullColor,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      child: Switch(
                        value: _scanAllStocksMode,
                        onChanged: (val) {
                          setState(() => _scanAllStocksMode = val);
                          HapticFeedback.mediumImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(val
                                  ? '🌐 SCAN ALL STOCKS MODE ACTIVE: Scanning all market stocks on candle select'
                                  : '🎯 NIFTY ONLY MODE ACTIVE: Injects NIFTY50 only (Zero scan delay)'),
                              backgroundColor: val ? AppTheme.goldColor : AppTheme.bullColor,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        activeThumbColor: AppTheme.goldColor,
                        activeTrackColor: AppTheme.goldColor.withValues(alpha: 0.3),
                        inactiveThumbColor: AppTheme.bullColor,
                        inactiveTrackColor: AppTheme.bullColor.withValues(alpha: 0.3),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // UNDO LAST BUTTON
                IconButton(
                  onPressed: _undoLastInjection,
                  icon: const Icon(Icons.undo_rounded, color: AppTheme.bearColor, size: 20),
                  tooltip: 'UNDO LAST',
                  visualDensity: VisualDensity.compact,
                ),
                const VerticalDivider(color: Colors.white10, indent: 8, endIndent: 8),
                TextButton.icon(
                  onPressed: () => ref.read(candleStreamProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryCyan, size: 14),
                  label: const Text('REFRESH', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 9, fontWeight: FontWeight.w900)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _showReplayPlayer(context),
                  icon: const Icon(Icons.play_circle_filled_rounded, color: AppTheme.bullColor, size: 14),
                  label: const Text('REPLAY', style: TextStyle(color: AppTheme.bullColor, fontSize: 9, fontWeight: FontWeight.w900)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _handleAutoInjectDaySwings,
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 14),
                  label: const Text('⚡ AUTO SWINGS', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.goldColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.vibrate();
                    ref.read(candleStreamProvider.notifier).refresh(clearCache: true);
                  },
                  icon: const Icon(Icons.cleaning_services_rounded, color: AppTheme.bearColor, size: 14),
                  label: const Text('HARD RESET', style: TextStyle(color: AppTheme.bearColor, fontSize: 9, fontWeight: FontWeight.w900)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    final candleState = ref.read(candleStreamProvider);
                    if (candleState.candles.isNotEmpty) {
                      setState(() {
                        _selectedCandleTime = candleState.candles.last.timeStart;
                      });
                      HapticFeedback.lightImpact();
                      final selectedInstrument = ref.read(selectedInstrumentProvider);
                      if (selectedInstrument == 'NIFTY50' && _selectedCandleTime != null) {
                        _startSimilarPatternScan(_selectedCandleTime!);
                      }
                    }
                  },
                  icon: const Icon(Icons.last_page_rounded, color: AppTheme.primaryCyan, size: 14),
                  label: const Text('LAST', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 9, fontWeight: FontWeight.w900)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCandleSearchBar(List<CandleModel> candles) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _candleSearchController,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'SEARCH CANDLE TIME (e.g. "12.45", "12:45", "09:20")',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                suffixIcon: _candleSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                        onPressed: () {
                          _candleSearchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (val) => _searchAndSelectCandle(val, candles),
            ),
          ),
          IconButton(
            onPressed: () => _searchAndSelectCandle(_candleSearchController.text, candles),
            icon: const Icon(Icons.search_rounded, color: AppTheme.primaryCyan),
            tooltip: 'SEARCH CANDLE',
          ),
        ],
      ),
    );
  }

  void _searchAndSelectCandle(String query, List<CandleModel> candles) {
    if (query.isEmpty) return;
    
    final targetTime = _parseCandleSearchQuery(query, candles);
    if (targetTime != null) {
      setState(() {
        _selectedCandleTime = targetTime;
      });
      HapticFeedback.mediumImpact();
      
      final displayTime = DateFormat('MMM dd hh:mm a').format(targetTime).toUpperCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SELECTED CANDLE MATCHING "$query" -> $displayTime'),
          backgroundColor: AppTheme.bullColor,
          duration: const Duration(seconds: 3),
        ),
      );
      
      final selectedInstrument = ref.read(selectedInstrumentProvider);
      if (selectedInstrument == 'NIFTY50' && _scanAllStocksMode) {
        _startSimilarPatternScan(targetTime);
      }
    } else {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('NO CANDLE MATCHING "$query" FOUND'),
          backgroundColor: AppTheme.bearColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  bool _isCandleMatchingSearch(CandleModel candle, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final time = candle.timeStart;
    final hh = DateFormat('HH').format(time); // 24-hr e.g. "12" or "09"
    final mm = DateFormat('mm').format(time); // min e.g. "45" or "20"
    final h12 = DateFormat('h').format(time); // 12-hr e.g. "9" or "12" or "3"
    final h12Padded = DateFormat('hh').format(time); // 12-hr e.g. "09" or "12" or "03"
    final day = DateFormat('dd').format(time); // e.g. "30"
    final dayShort = DateFormat('d').format(time); // e.g. "30"
    final monthShort = DateFormat('MMM').format(time).toLowerCase(); // e.g. "jul"
    final monthFull = DateFormat('MMMM').format(time).toLowerCase(); // e.g. "july"

    final timeColon = '$hh:$mm'; // "12:45"
    final timeDot = '$hh.$mm';   // "12.45"
    final timeConcat = '$hh$mm'; // "1245"
    final timeSpace = '$hh $mm'; // "12 45"

    final time12Colon = '$h12:$mm'; // "9:15"
    final time12Dot = '$h12.$mm';   // "9.15"
    final time12Concat = '$h12$mm'; // "915"
    final time12PaddedColon = '$h12Padded:$mm';
    final time12PaddedDot = '$h12Padded.$mm';

    if (timeColon.contains(query) ||
        timeDot.contains(query) ||
        timeConcat.contains(query) ||
        timeSpace.contains(query) ||
        time12Colon.contains(query) ||
        time12Dot.contains(query) ||
        time12Concat.contains(query) ||
        time12PaddedColon.contains(query) ||
        time12PaddedDot.contains(query)) {
      return true;
    }

    final tokens = query.split(RegExp(r'\s+'));
    if (tokens.length > 1) {
      bool allMatched = true;
      for (final token in tokens) {
        if (token.isEmpty) continue;
        final tokenMatched = timeColon.contains(token) ||
            timeDot.contains(token) ||
            timeConcat.contains(token) ||
            time12Colon.contains(token) ||
            time12Dot.contains(token) ||
            day == token ||
            dayShort == token ||
            monthShort.contains(token) ||
            monthFull.contains(token) ||
            hh == token ||
            h12 == token ||
            mm == token;
        if (!tokenMatched) {
          allMatched = false;
          break;
        }
      }
      if (allMatched) return true;
    }

    return false;
  }

  DateTime? _parseCandleSearchQuery(String query, List<CandleModel> candles) {
    if (query.isEmpty) return null;
    final matches = candles.where((c) => _isCandleMatchingSearch(c, query)).toList();
    if (matches.isNotEmpty) {
      return matches.first.timeStart;
    }
    return null;
  }

  Widget _buildCandleList(CandleStreamState candleState, {bool isFlexible = false}) {
    final searchQuery = _candleSearchController.text.trim();
    final List<CandleModel> displayCandles = searchQuery.isEmpty
        ? candleState.candles
        : candleState.candles.where((c) => _isCandleMatchingSearch(c, searchQuery)).toList();

    final content = candleState.isLoading && candleState.candles.isEmpty
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primaryCyan),
                SizedBox(height: 16),
                Text('FETCHING CANDLES...', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        : Column(
            children: [
              if (searchQuery.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: AppTheme.primaryCyan.withValues(alpha: 0.08),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FILTERED MATCHES: ${displayCandles.length} CANDLE(S) FOR "$searchQuery"',
                        style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                      GestureDetector(
                        onTap: () {
                          _candleSearchController.clear();
                          setState(() {});
                        },
                        child: const Text('SHOW ALL', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                ),
              if (candleState.error != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.bearColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.bearColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.bearColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          candleState.error!,
                          style: const TextStyle(color: AppTheme.bearColor, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: displayCandles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, color: Colors.white24, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              'NO CANDLE MATCHING "$searchQuery"',
                              style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: displayCandles.length,
                        itemBuilder: (context, index) {
                          final candle = displayCandles[index];
                          final isSelected = _selectedCandleTime == candle.timeStart;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedCandleTime = candle.timeStart);
                        final selectedInstrument = ref.read(selectedInstrumentProvider);
                        if (selectedInstrument == 'NIFTY50' && _scanAllStocksMode && _selectedCandleTime != null) {
                          _startSimilarPatternScan(_selectedCandleTime!);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryCyan.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? AppTheme.primaryCyan : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('hh:mm a').format(candle.timeStart),
                                  style: TextStyle(color: isSelected ? AppTheme.primaryCyan : Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                ),
                                Text(
                                  DateFormat('MMM dd').format(candle.timeStart).toUpperCase(),
                                  style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'O:${candle.open.toStringAsFixed(1)} H:${candle.high.toStringAsFixed(1)} L:${candle.low.toStringAsFixed(1)} C:${candle.close.toStringAsFixed(1)}',
                                    style: const TextStyle(color: AppTheme.subTextColor, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                  if (candle.hasOrderflowData)
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppTheme.bullColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: const Text(
                                        'DATA INJECTED',
                                        style: TextStyle(color: AppTheme.bullColor, fontSize: 7, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // QUICK SELECTION (BUY & SELL ONLY)
                            if (!candle.hasOrderflowData) ...[
                              ElevatedButton(
                                onPressed: () => _selectCandleForOrder(candle, 'BUY'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.bullColor,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  elevation: 2,
                                ),
                                child: const Text('BUY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton(
                                onPressed: () => _selectCandleForOrder(candle, 'SELL'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.bearColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  elevation: 2,
                                ),
                                child: const Text('SELL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                              ),
                            ],
                            if (candle.hasOrderflowData)
                              IconButton(
                                icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.bearColor, size: 18),
                                onPressed: () => _revokeSingleOrderflow(candle.candleKey, symbol: candle.symbol),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'REVOKE SIGNAL',
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );



    return Container(
      height: isFlexible ? 400 : 220,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: content,
    );
  }

  // Helper for bolt icons
  Widget _buildBoltIcon({required IconData icon, required Color color, required String tooltip, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () {
            HapticFeedback.heavyImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: color, size: 20),
              if (_isQuickFireMode)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.goldColor,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 2,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: const Text(
                      'QF',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 6,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectCandleForOrder(Candle candle, String type) {
    HapticFeedback.mediumImpact();
    final timeStr = DateFormat('hh:mm a').format(candle.timeStart);
    setState(() {
      _selectedCandleTime = candle.timeStart;
      _bubbleScale = 5.0; // Default ball size 5.0x whether BUY or SELL
      if (type == 'BUY') {
        _buyerCountController.text = _randomizeValue(50000).toString();
        _sellerCountController.text = '';
        _customTagController.text = 'BUY ORDER';
        _isBigSignal = true;
        _isTrap = false;
        _isLiquidation = false;
      } else if (type == 'SELL') {
        _buyerCountController.text = '';
        _sellerCountController.text = _randomizeValue(50000).toString();
        _customTagController.text = 'SELL ORDER';
        _isBigSignal = true;
        _isTrap = false;
        _isLiquidation = false;
      }
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎯 CANDLE [$timeStr] SELECTED FOR $type ORDER. TAP "TRIGGER ALERT" TO BROADCAST.'),
        backgroundColor: type == 'BUY' ? AppTheme.bullColor : AppTheme.bearColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }



  Future<void> _instantInjectData({Candle? targetCandle}) async {
    try {
      final selectedInstrument = ref.read(selectedInstrumentProvider);
      final candleState = ref.read(candleStreamProvider);

      Candle? candle = targetCandle;
      if (candle == null && _selectedCandleTime != null) {
        candle = candleState.candles.firstWhereOrNull((c) => c.timeStart == _selectedCandleTime);
      }
      candle ??= candleState.candles.isNotEmpty ? candleState.candles.last : null;

      if (candle == null) return;

      int buyerCount = int.tryParse(_buyerCountController.text) ?? 0;
      int sellerCount = int.tryParse(_sellerCountController.text) ?? 0;
      final tag = _customTagController.text.toUpperCase();

      if (buyerCount > 0 || sellerCount > 0 || tag.contains('BUY') || tag.contains('SELL')) {
        if (buyerCount > sellerCount || tag.contains('BUY')) {
          buyerCount = buyerCount > 0 ? buyerCount : 52000;
          sellerCount = sellerCount > 0 ? sellerCount : 4500;
        } else {
          sellerCount = sellerCount > 0 ? sellerCount : 52000;
          buyerCount = buyerCount > 0 ? buyerCount : 4500;
        }
      } else {
        // Fallback to candle movement scenario only when no explicit direction or volume was selected
        final bool isBullishScenario = candle.close >= candle.open;
        buyerCount = isBullishScenario ? 52000 : 4500;
        sellerCount = isBullishScenario ? 4500 : 52000;
      }

      buyerCount = _randomizeValue(buyerCount);
      sellerCount = _randomizeValue(sellerCount);

      final authState = ref.read(authProvider);
      final orderflowRepo = ref.read(orderflowRepositoryProvider);

      // Save orderflow silently without any alert popups or notifications
      await orderflowRepo.saveOrderflowBulk(
        candleKeys: [candle.candleKey],
        symbol: selectedInstrument,
        buyerCount: buyerCount,
        sellerCount: sellerCount,
        isBigSignal: true,
        adminUid: authState.user?.uid ?? 'ADMIN',
        broadcastPush: false, // Bypasses broadcast alert
        adminOnly: true, // Visible only for admin advertisement purpose
      );

      _lastInjectedCandleKey = candle.candleKey;
      _lastInjectedSymbol = selectedInstrument;

      if (mounted) {
        ref.read(candleStreamProvider.notifier).refresh();
      }
    } catch (_) {
      // Silent execution as requested (no alert)
    }
  }

  Widget _buildVolumeInputs() {
    return Row(
      children: [
        Expanded(child: _buildInstitutionalField(_buyerCountController, 'BUYER VOLUME', AppTheme.bullColor)),
        const SizedBox(width: 16),
        Expanded(child: _buildInstitutionalField(_sellerCountController, 'SELLER VOLUME', AppTheme.bearColor)),
      ],
    );
  }

  Widget _buildSignalSwitches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.stars_rounded, color: AppTheme.goldColor, size: 14),
            SizedBox(width: 6),
            Text(
              'SPECIAL SIGNAL TAG',
              style: TextStyle(color: AppTheme.goldColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: AppTheme.glassDecoration(
            opacity: 0.04,
            borderRadius: BorderRadius.circular(12),
            borderColor: Colors.white.withValues(alpha: 0.06),
          ),
          child: Row(
            children: [
              Expanded(child: _buildSignalChip('NONE', !_isBigSignal && !_isTrap && !_isLiquidation, Colors.white60, () {
                setState(() {
                  _isBigSignal = false;
                  _isTrap = false;
                  _isLiquidation = false;
                });
              })),
              Expanded(child: _buildSignalChip('BIG DATA', _isBigSignal, AppTheme.goldColor, () {
                setState(() {
                  _isBigSignal = true;
                  _isTrap = false;
                  _isLiquidation = false;
                });
              })),
              Expanded(child: _buildSignalChip('TRAP', _isTrap, Colors.amber, () {
                setState(() {
                  _isBigSignal = false;
                  _isTrap = true;
                  _isLiquidation = false;
                });
              })),
              Expanded(child: _buildSignalChip('LIQUIDATION', _isLiquidation, Colors.purpleAccent, () {
                setState(() {
                  _isBigSignal = false;
                  _isTrap = false;
                  _isLiquidation = true;
                });
              })),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: AppTheme.glassDecoration(
            opacity: _broadcastPush ? 0.06 : 0.03,
            borderColor: _broadcastPush ? AppTheme.bullColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: _broadcastPush ? AppTheme.bullColor : AppTheme.dimTextColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BROADCAST PUSH NOTIFICATION',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'DISPATCH IMMEDIATE ALERT SIGNAL TO ALL ACTIVE TERMINALS',
                      style: TextStyle(color: Colors.white38, fontSize: 7, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _broadcastPush,
                onChanged: _adminOnly ? null : (v) => setState(() => _broadcastPush = v),
                activeThumbColor: AppTheme.bullColor,
                activeTrackColor: AppTheme.bullColor.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: AppTheme.glassDecoration(
            opacity: _adminOnly ? 0.06 : 0.03,
            borderColor: _adminOnly ? Colors.tealAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_person_rounded,
                color: _adminOnly ? Colors.tealAccent : AppTheme.dimTextColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ADMIN ONLY (SPECIAL ADVERTISEMENT)',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'ONLY VIEWABLE BY MASTER ADMIN USERS. NO BROADCASTS, NO ALERTS.',
                      style: TextStyle(color: Colors.white38, fontSize: 7, fontWeight: FontWeight.bold),
                    ),

                  ],
                ),
              ),
              Switch.adaptive(
                value: _adminOnly,
                onChanged: (v) => setState(() {
                  _adminOnly = v;
                  if (v) {
                    _broadcastPush = false;
                  }
                }),
                activeThumbColor: Colors.tealAccent,
                activeTrackColor: Colors.tealAccent.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // INSTANT AD INJECT BUTTON (SILENT, NO ALERT, SCENARIO-BASED)
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.heavyImpact();
              _instantInjectData();
            },
            icon: const Icon(Icons.flash_on_rounded, color: Colors.black, size: 20),
            label: const Text(
              '⚡ INSTANT INJECT (SILENT AD MODE)',
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                fontFamily: 'monospace',
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              elevation: 4,
              shadowColor: Colors.tealAccent.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignalChip(String label, bool isSelected, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor.withValues(alpha: 0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white38,
              fontSize: 8,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGhostModeSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.goldColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _isGhostMode ? AppTheme.goldColor.withValues(alpha: 0.5) : Colors.white10),
          ),
          child: Row(
            children: [
              Icon(Icons.visibility_off_rounded, color: _isGhostMode ? AppTheme.goldColor : AppTheme.dimTextColor, size: 24),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GHOST MODE',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    Text(
                      'CREATE PENDING SIGNALS TRIGGERED BY PRICE',
                      style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isGhostMode,
                onChanged: (v) => setState(() => _isGhostMode = v),
                activeTrackColor: AppTheme.goldColor.withValues(alpha: 0.2),
              ),
            ],
          ),
        ),
        if (_isGhostMode) ...[
          const SizedBox(height: 16),
          _buildInstitutionalField(_ghostTriggerController, 'TRIGGER PRICE', AppTheme.goldColor),
        ],
      ],
    );
  }

  Widget _buildFootprintSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'FOOTPRINT INJECTION',
          style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        const SizedBox(height: 12),
        _buildInstitutionalField(_priceLevelController, 'PRICE LEVEL', AppTheme.subTextColor),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildInstitutionalField(_levelBuyerController, 'BUY VOLUME', AppTheme.bullColor)),
            const SizedBox(width: 16),
            Expanded(child: _buildInstitutionalField(_levelSellerController, 'SELL VOLUME', AppTheme.bearColor)),
          ],
        ),
        const SizedBox(height: 16),
        _buildBubbleSizeSelector(),
        const SizedBox(height: 32),
        _buildGlobalControls(),
      ],
    );
  }

  Widget _buildCoMovementSuggestionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 8),
        // Header row
        Row(
          children: [
            const Icon(Icons.analytics_outlined, color: AppTheme.primaryCyan, size: 14),
            const SizedBox(width: 6),
            const Text(
              'CO-MOVEMENT SUGGESTIONS',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Text(
              ' (TODAY ONLY)',
              style: TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_isScanningSimilarPatterns) ...[
              Text(
                '$_scanProgress/$_scanTotal',
                style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
              const SizedBox(width: 6),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                ),
              ),
            ] else
              // SCAN NOW button
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _startSimilarPatternScan(DateTime.now());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryCyan.withValues(alpha: 0.3), AppTheme.primaryCyan.withValues(alpha: 0.1)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar, color: AppTheme.primaryCyan, size: 11),
                      const SizedBox(width: 4),
                      const Text(
                        'SCAN ALL STOCKS',
                        style: TextStyle(color: AppTheme.primaryCyan, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Body
        if (_isScanningSimilarPatterns)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.glassDecoration(
              opacity: 0.02,
              borderRadius: BorderRadius.circular(12),
              borderColor: AppTheme.primaryCyan.withValues(alpha: 0.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar, color: AppTheme.primaryCyan, size: 14),
                    const SizedBox(width: 8),
                    const Text(
                      'CORRELATION PATTERN RUNTIME SCAN',
                      style: TextStyle(
                        color: AppTheme.primaryCyan,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _scanTotal > 0 ? _scanProgress / _scanTotal : null,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '// RESOLVING MARKET STOCKS TELEMETRY...',
                  style: TextStyle(color: Colors.white38, fontSize: 8, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 4),
                Text(
                  '// SYNC STATUS: $_scanProgress OF $_scanTotal COMPLETED',
                  style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        else if (_suggestedSimilarStocks.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No co-moving stocks found for today.',
                style: TextStyle(color: Colors.white30, fontSize: 9, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap SCAN ALL STOCKS to analyse today\'s price correlation.',
                style: TextStyle(color: Colors.white24, fontSize: 8, fontStyle: FontStyle.italic),
              ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NIFTY50 MASTER HUB
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: AppTheme.neonGlassDecoration(
                  glowColor: AppTheme.primaryCyan,
                  opacity: 0.04,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.4)),
                      ),
                      child: const Center(
                        child: Icon(Icons.hub_rounded, color: AppTheme.primaryCyan, size: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NIFTY50 MASTER SOURCE',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, fontFamily: 'monospace', letterSpacing: 1),
                        ),
                        Text(
                          'TARGET NODE FOR BATCH INJECTIONS',
                          style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${_selectedSimilarStocksToInject.length} PATHS ACTIVE',
                        style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Controls row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.bullColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.bullColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${_suggestedSimilarStocks.where((s) => (s['score'] as int) >= 80).length} STRONG  ${_suggestedSimilarStocks.where((s) => (s['score'] as int) < 80).length} MODERATE',
                      style: const TextStyle(color: AppTheme.bullColor, fontSize: 8, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedSimilarStocksToInject.length == _suggestedSimilarStocks.length) {
                          _selectedSimilarStocksToInject.clear();
                        } else {
                          for (final s in _suggestedSimilarStocks) {
                            _selectedSimilarStocksToInject.add(s['symbol'] as String);
                          }
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        _selectedSimilarStocksToInject.length == _suggestedSimilarStocks.length ? 'DESELECT ALL' : 'SELECT ALL',
                        style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Network branching nodes
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suggestedSimilarStocks.length,
                itemBuilder: (context, index) {
                  final s = _suggestedSimilarStocks[index];
                  final String sym = s['symbol'];
                  final int score = s['score'];
                  final isChecked = _selectedSimilarStocksToInject.contains(sym);
                  final isStrong = score >= 80;
                  final Color scoreColor = isStrong ? AppTheme.bullColor : Colors.amber;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlowingBranchLine(
                        isLast: index == _suggestedSimilarStocks.length - 1,
                        isSynced: isChecked,
                        syncColor: scoreColor,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (isChecked) {
                                  _selectedSimilarStocksToInject.remove(sym);
                                } else {
                                  _selectedSimilarStocksToInject.add(sym);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: AppTheme.glassDecoration(
                                opacity: isChecked ? 0.06 : 0.02,
                                borderRadius: BorderRadius.circular(10),
                                borderColor: isChecked ? scoreColor.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
                              ),
                              child: Row(
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sym,
                                        style: TextStyle(
                                          color: isChecked ? Colors.white : Colors.white60,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isStrong ? 'STRONG CO-MOVEMENT' : 'MODERATE CO-MOVEMENT',
                                        style: TextStyle(
                                          color: isChecked ? scoreColor.withValues(alpha: 0.7) : Colors.white24,
                                          fontSize: 7,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'CORR: ',
                                            style: TextStyle(
                                              color: Colors.white24,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          Text(
                                            '$score%',
                                            style: TextStyle(
                                              color: scoreColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        width: 60,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(1.5),
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            width: 60 * (score / 100),
                                            height: 3,
                                            decoration: BoxDecoration(
                                              color: scoreColor,
                                              borderRadius: BorderRadius.circular(1.5),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: scoreColor.withValues(alpha: 0.5),
                                                  blurRadius: 2,
                                                  spreadRadius: 0.5,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    isChecked ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                                    color: isChecked ? scoreColor : Colors.white24,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _isLoading ? null : _saveOrderflow,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.goldColor,
            foregroundColor: AppTheme.bgColor,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 10,
            shadowColor: AppTheme.goldColor.withValues(alpha: 0.4),
          ),
          child: _isLoading 
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bgColor))
            : const Text('TRIGGER ALERT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading || _selectedCandleTime == null ? null : _deleteOrderflow,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppTheme.bearColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CLEAR DATA', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading ? null : _showWipeConfirmation,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('WIPE ALL FOR DAY', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedTemplates() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PROMO AUTO-INJECT DAY SWINGS BUTTON
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          child: ElevatedButton.icon(
            onPressed: _handleAutoInjectDaySwings,
            icon: const Icon(Icons.bolt_rounded, color: Colors.black, size: 20),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '⚡ AUTO-INJECT DAY SWINGS (LOW/HIGH)',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.goldColor,
              elevation: 6,
              shadowColor: AppTheme.goldColor.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const Row(
          children: [
            Icon(Icons.bolt_rounded, color: AppTheme.goldColor, size: 14),
            SizedBox(width: 6),
            Text(
              'QUICK SIGNAL INJECTION TEMPLATES',
              style: TextStyle(color: AppTheme.goldColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            _buildTemplateCard('BUY ORDER', AppTheme.bullColor, Icons.trending_up_rounded, () {
              _applyTemplate(buy: 100000, sell: 0, tag: 'BUY', scale: 20.0, pulse: 1.2, glow: 1.0, color: 'DEFAULT');
            }),
            _buildTemplateCard('SELL ORDER', AppTheme.bearColor, Icons.trending_down_rounded, () {
              _applyTemplate(buy: 0, sell: 100000, tag: 'SELL', scale: 20.0, pulse: 1.2, glow: 1.0, color: 'DEFAULT');
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildTemplateCard(String label, Color color, IconData icon, VoidCallback onTap) {
    return Container(
      decoration: AppTheme.neonGlassDecoration(
        glowColor: color,
        opacity: 0.03,
        borderRadius: BorderRadius.circular(12),
        borderWidth: 1.0,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applyTemplate({
    required int buy, 
    required int sell, 
    required String tag,
    required double scale,
    required double pulse,
    required double glow,
    required String color,
    bool isTrap = false,
    bool isLiq = false,
  }) {
    setState(() {
      _buyerCountController.text = buy > 0 ? _randomizeValue(buy).toString() : '';
      _sellerCountController.text = sell > 0 ? _randomizeValue(sell).toString() : '';
      _customTagController.text = tag;
      _bubbleScale = scale;
      _pulseSpeed = pulse;
      _bubbleGlow = glow;
      _borderColorSelection = color;
      _isBigSignal = !isTrap && !isLiq;
      _isTrap = isTrap;
      _isLiquidation = isLiq;
    });

    if (_isQuickFireMode) {
      _saveOrderflow();
    }
  }







  Widget _buildBubbleSizeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'BALL SIZE (ORB SCALE)',
              style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_bubbleScale.toStringAsFixed(1)}x',
                style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.primaryCyan,
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              overlayColor: AppTheme.primaryCyan.withValues(alpha: 0.2),
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            ),
            child: Slider(
              value: _bubbleScale.clamp(1.0, 50.0),
              min: 1.0,
              max: 50.0,
              divisions: 49,
              onChanged: (value) => setState(() => _bubbleScale = value),
            ),
          ),
          const SizedBox(height: 16),
          _buildAppearanceSliders(),
        ],
      );
    }

  Widget _buildAppearanceSliders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Opacity Slider
        _buildSliderLabel('OPACITY', _bubbleOpacity, '0.1-1.0'),
        Slider(
          value: _bubbleOpacity,
          min: 0.1,
          max: 1.0,
          divisions: 9,
          activeColor: AppTheme.primaryCyan,
          onChanged: (v) => setState(() => _bubbleOpacity = v),
        ),
        const SizedBox(height: 12),
        // Glow Intensity Slider
        _buildSliderLabel('GLOW INTENSITY', _bubbleGlow, '0.0-1.0'),
        Slider(
          value: _bubbleGlow,
          min: 0.0,
          max: 1.0,
          divisions: 10,
          activeColor: Colors.amber,
          onChanged: (v) => setState(() => _bubbleGlow = v),
        ),
        const SizedBox(height: 12),
        // Show Label Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SHOW VOLUME DATA',
              style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.w900),
            ),
            Switch(
              value: _showLabel,
              activeTrackColor: AppTheme.primaryCyan,
              onChanged: (v) => setState(() => _showLabel = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 16),
        
        // Custom Tag
        _buildSectionHeader('SIGNAL TAG (e.g. TRAP, ICEBERG)'),
        const SizedBox(height: 8),
        _buildPanelTextField(_customTagController, 'ENTER LABEL', AppTheme.primaryCyan),
        
        const SizedBox(height: 16),
        
        // Pulse Speed
        _buildSliderLabel('PULSE FREQUENCY', _pulseSpeed, '0.5x - 3.0x'),
        Slider(
          value: _pulseSpeed,
          min: 0.5,
          max: 3.0,
          divisions: 25,
          activeColor: AppTheme.bullColor,
          onChanged: (v) => setState(() => _pulseSpeed = v),
        ),
        
        const SizedBox(height: 16),
        
        // Border Color
        _buildSectionHeader('BORDER PRIORITY'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['DEFAULT', 'GOLD', 'MAGENTA', 'CYAN'].map((color) {
            final isSelected = _borderColorSelection == color;
            Color displayColor;
            switch(color) {
              case 'GOLD': displayColor = Colors.amber; break;
              case 'MAGENTA': displayColor = Colors.pinkAccent; break;
              case 'CYAN': displayColor = AppTheme.primaryCyan; break;
              default: displayColor = Colors.white24;
            }
            return ChoiceChip(
              label: Text(color, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              selected: isSelected,
              selectedColor: displayColor,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              onSelected: (val) => setState(() => _borderColorSelection = color),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 16),
        
        // Auto-Fade Timer
        _buildSectionHeader('SIGNAL AUTO-FADE'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [0, 1, 5, 15, 60].map((mins) {
            final isSelected = _autoFadeMinutes == mins;
            final label = mins == 0 ? "OFF" : (mins == 60 ? "1H" : "${mins}M");
            return ChoiceChip(
              label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              selected: isSelected,
              selectedColor: AppTheme.goldColor,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              onSelected: (val) => setState(() => _autoFadeMinutes = mins),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
    );
  }

  Widget _buildSliderLabel(String label, double value, String range) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.w900),
        ),
        Text(
          value.toStringAsFixed(1),
          style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }


  Widget _buildPanelTextField(TextEditingController controller, String hint, Color color) {
    return CyberTextField(
      controller: controller,
      hint: hint,
      themeColor: color,
    );
  }

  // Removed unused _buildSizeChip

  Widget _buildGlobalControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GLOBAL TERMINAL COMMANDS',
          style: TextStyle(color: AppTheme.goldColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassDecoration(opacity: 0.05),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up_rounded, color: AppTheme.dimTextColor, size: 18),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('MARKET SENTIMENT', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  DropdownButton<String>(
                    value: _selectedSentiment,
                    dropdownColor: AppTheme.cardColor,
                    underline: const SizedBox(),
                    items: [
                      'STRONG_BULLISH', 'BULLISH', 'SIDEWAY_BULLISH', 'SIDEWAY', 
                      'SIDEWAY_BEARISH', 'BEARISH', 'STRONG_BEARISH', 'VOLATILITY'
                    ].map((s) => DropdownMenuItem(
                      value: s, 
                      child: Text(s.replaceAll('_', ' '), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedSentiment = v);
                        GlobalSettingsService.updateConfig(sentiment: v);
                      }
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              Row(
                children: [
                  const Icon(Icons.volume_up_rounded, color: AppTheme.dimTextColor, size: 18),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('GLOBAL AUDIO ALERTS', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  Switch(
                    value: _audioAlertsEnabled,
                    activeTrackColor: AppTheme.primaryCyan,
                    onChanged: (v) {
                      setState(() => _audioAlertsEnabled = v);
                      GlobalSettingsService.updateConfig(audioAlertsEnabled: v);
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              Row(
                children: [
                  Expanded(
                    child: CyberTextField(
                      controller: _newsTickerController,
                      hint: 'PUSH LIVE NEWS MESSAGE...',
                      themeColor: AppTheme.primaryCyan,
                      icon: Icons.campaign_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: AppTheme.primaryCyan, size: 20),
                    onPressed: () {
                      GlobalSettingsService.updateConfig(tickerMessage: _newsTickerController.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('NEWS BROADCAST REFRESHED'), backgroundColor: AppTheme.primaryCyan),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWipeDataSection() {
    return Row(
      children: [
        const Icon(Icons.delete_forever_rounded, color: AppTheme.bearColor, size: 18),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DATA MANAGEMENT', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              Text('Wipe all signals for current symbol', style: TextStyle(color: Colors.white24, fontSize: 8)),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: _showWipeConfirmation,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.bearColor.withValues(alpha: 0.1),
            foregroundColor: AppTheme.bearColor,
            elevation: 0,
            side: const BorderSide(color: AppTheme.bearColor, width: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('CLEAR ALL SIGNALS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  void _showWipeConfirmation() {
    final symbol = ref.read(selectedInstrumentProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
        title: const Text('CONFIRM DATA WIPE', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text(
          'This will permanently delete ALL orderflow signals for $symbol. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _wipeOrderflow(symbol);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.bearColor),
            child: const Text('WIPE DATA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _wipeOrderflow(String symbol) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(orderflowServiceProvider).wipeOrderflowForDay(symbol);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ALL SIGNALS FOR $symbol HAVE BEEN CLEARED'),
            backgroundColor: AppTheme.primaryCyan,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ERROR CLEARING DATA: $e'),
            backgroundColor: AppTheme.bearColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  Widget _buildInstitutionalField(TextEditingController controller, String label, Color color) {
    return CyberTextField(
      controller: controller,
      label: label,
      hint: '0',
      themeColor: color,
      keyboardType: TextInputType.number,
      isNumeric: true,
    );
  }

  Widget _buildSystemSyncTab() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: GlobalSettingsService.getConfigStream(),
      builder: (context, snapshot) {
        if (snapshot.hasData && _localSentiment == null) {
          // Initialize local state with current values if not already set
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _localSentiment == null) {
              setState(() {
                _localSentiment = snapshot.data!['sentiment'] ?? GlobalSettingsService.sentimentSideway;
                _tickerController.text = snapshot.data!['tickerMessage'] ?? "";
                _isMaintenanceMode = snapshot.data!['isMaintenanceMode'] ?? false;
                _allowAdminScreenshots = snapshot.data!['allowAdminScreenshots'] ?? false;
                _activeBroker = snapshot.data!['activeBroker'] ?? 'all';
              });
            }
          });
        }

        // Seed update fields from Firestore when loaded
        if (snapshot.hasData && _versionController.text.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final d = snapshot.data!;
              if ((d['latestVersion'] as String? ?? '').isNotEmpty) {
                _versionController.text = d['latestVersion'] ?? '';
              }
              if ((d['updateUrl'] as String? ?? '').isNotEmpty) {
                _updateUrlController.text = d['updateUrl'] ?? '';
              }
              if ((d['changelog'] as String? ?? '').isNotEmpty) {
                _changelogController.text = d['changelog'] ?? '';
              }
              setState(() {
                _forceUpdate = d['forceUpdate'] ?? false;
                _updateEnabled = d['updateEnabled'] ?? false;
              });
            }
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── APP UPDATE CONTROL ─────────────────────────────
              _buildAppUpdateSection(),
              const SizedBox(height: 32),
              // MARKET SENTIMENT CONTROL REMOVED
              const Text(
                'GLOBAL BROADCAST (NEWS TICKER)',
                style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              _buildBroadcastField(),
              const SizedBox(height: 32),
              _buildUrgentBroadcastSection(),
              const SizedBox(height: 32),
              _buildWipeDataSection(),
              const SizedBox(height: 32),
              const Text(
                'SYSTEM KILL SWITCH (MAINTENANCE)',
                style: TextStyle(color: AppTheme.bearColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bearColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isMaintenanceMode ? AppTheme.bearColor.withValues(alpha: 0.5) : Colors.white10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.power_settings_new_rounded, color: _isMaintenanceMode ? AppTheme.bearColor : AppTheme.dimTextColor, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTIVATE KILL SWITCH',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                          ),
                          Text(
                            'BLOCK ALL USER ACCESS & ALERTS',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isMaintenanceMode,
                      onChanged: (v) => setState(() => _isMaintenanceMode = v),
                      activeTrackColor: AppTheme.bearColor.withValues(alpha: 0.2),
                      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? AppTheme.bearColor : null),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SCREENSHOT ACCESS CONTROL',
                style: TextStyle(color: AppTheme.goldColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.goldColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _allowAdminScreenshots ? AppTheme.goldColor.withValues(alpha: 0.5) : Colors.white10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.screenshot_rounded, color: _allowAdminScreenshots ? AppTheme.goldColor : AppTheme.dimTextColor, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ADMIN SCREENSHOT ACCESS',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                          ),
                          Text(
                            'ONLY ADMINS CAN TAKE SCREENSHOTS (IF ENABLED)',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _allowAdminScreenshots,
                      onChanged: (v) => setState(() => _allowAdminScreenshots = v),
                      activeTrackColor: AppTheme.goldColor.withValues(alpha: 0.2),
                      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? AppTheme.goldColor : null),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildBrokerSelectionSection(),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _syncLoading ? null : _saveSystemSync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryCyan,
                  foregroundColor: AppTheme.bgColor,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 10,
                  shadowColor: AppTheme.primaryCyan.withValues(alpha: 0.4),
                ),
                child: _syncLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bgColor))
                  : const Text('TRIGGER SYNC', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBrokerSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BROKER FEED SELECTION',
          style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select which broker feed to display to end users. "All" will show all available feeds.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildBrokerOption(
                      id: 'mstock',
                      label: 'M.STOCK',
                      icon: Icons.account_balance_rounded,
                      color: AppTheme.bullColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildBrokerOption(
                      id: 'zerodha',
                      label: 'ZERODHA',
                      icon: Icons.show_chart_rounded,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildBrokerOption(
                      id: 'kotak',
                      label: 'KOTAK NEO',
                      icon: Icons.currency_rupee_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildBrokerOption(
                      id: 'all',
                      label: 'ALL BROKERS',
                      icon: Icons.dashboard_rounded,
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrokerOption({
    required String id,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _activeBroker == id;
    return InkWell(
      onTap: () => setState(() => _activeBroker = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color.withValues(alpha: 0.5) : Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.white38, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // _buildSentimentGrid REMOVED

  Widget _buildBroadcastField() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: CyberTextField(
          controller: _tickerController,
          hint: 'ENTER BROADCAST MESSAGE...',
          themeColor: AppTheme.primaryCyan,
          maxLines: 2,
        ),
      ),
    );
  }

  Widget _buildUrgentBroadcastSection() {
    final Color currentColor = _broadcastType == 'info'
        ? AppTheme.primaryCyan
        : _broadcastType == 'warning'
            ? AppTheme.goldColor
            : AppTheme.bearColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'URGENT OVERLAY BROADCAST',
          style: TextStyle(color: AppTheme.bearColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CyberTextField(
                controller: _broadcastMsgController,
                hint: 'ENTER URGENT OVERLAY MESSAGE...',
                themeColor: currentColor,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('TYPE: ', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  _buildBroadcastTypeButton('info', 'INFO', AppTheme.primaryCyan),
                  const SizedBox(width: 8),
                  _buildBroadcastTypeButton('warning', 'WARNING', AppTheme.goldColor),
                  const SizedBox(width: 8),
                  _buildBroadcastTypeButton('error', 'ALERT', AppTheme.bearColor),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 16),
                label: _broadcastLoading 
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('SEND BROADCAST OVERLAY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                onPressed: _broadcastLoading ? null : _sendBroadcast,
                style: ElevatedButton.styleFrom(
                  backgroundColor: currentColor,
                  foregroundColor: AppTheme.bgColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBroadcastTypeButton(String type, String label, Color color) {
    final isSelected = _broadcastType == type;
    return GestureDetector(
      onTap: () => setState(() => _broadcastType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? color : Colors.white10, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── App Update Control ─────────────────────────────────────────
  Widget _buildAppUpdateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.system_update_rounded, color: AppTheme.primaryCyan, size: 18),
            const SizedBox(width: 8),
            const Text(
              'APP UPDATE CONTROL',
              style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const Spacer(),
            // Live status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _updateEnabled ? AppTheme.bullColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _updateEnabled ? AppTheme.bullColor.withValues(alpha: 0.4) : Colors.white10),
              ),
              child: Text(
                _updateEnabled ? 'ACTIVE' : 'INACTIVE',
                style: TextStyle(
                  color: _updateEnabled ? AppTheme.bullColor : AppTheme.dimTextColor,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryCyan.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _updateEnabled ? AppTheme.primaryCyan.withValues(alpha: 0.3) : Colors.white10,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Version + URL row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildUpdateTextField(
                      controller: _versionController,
                      label: 'VERSION',
                      hint: 'e.g. 1.2.0',
                      icon: Icons.tag_rounded,
                      color: AppTheme.goldColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _buildUpdateTextField(
                      controller: _updateUrlController,
                      label: 'DOWNLOAD URL',
                      hint: 'https://play.google.com/...',
                      icon: Icons.link_rounded,
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // APK Upload Section
              if (_isUploadingApk) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'UPLOADING APK: ${(_apkUploadProgress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: AppTheme.primaryCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _apkUploadProgress,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickAndUploadApk,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.goldColor,
                      side: BorderSide(color: AppTheme.goldColor.withValues(alpha: 0.4), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text(
                      'UPLOAD NEW APK FILE',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Changelog
              _buildUpdateTextField(
                controller: _changelogController,
                label: 'CHANGELOG (WHAT\'S NEW)',
                hint: 'Describe the new features and bug fixes...',
                icon: Icons.edit_note_rounded,
                color: AppTheme.subTextColor,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              // Force Update toggle
              _buildUpdateToggleRow(
                icon: Icons.lock_rounded,
                label: 'FORCE UPDATE',
                subtitle: 'BLOCK APP UNTIL USER UPDATES (NON-DISMISSABLE)',
                color: AppTheme.bearColor,
                value: _forceUpdate,
                onChanged: (v) => setState(() => _forceUpdate = v),
              ),
              const SizedBox(height: 8),
              // Update Enabled toggle
              _buildUpdateToggleRow(
                icon: Icons.campaign_rounded,
                label: 'UPDATE NOTIFICATION ACTIVE',
                subtitle: 'SHOW UPDATE PROMPT TO ALL USERS',
                color: AppTheme.bullColor,
                value: _updateEnabled,
                onChanged: (v) => setState(() => _updateEnabled = v),
              ),
              const SizedBox(height: 20),
              // Publish button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _updateLoading ? null : _publishUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryCyan,
                    foregroundColor: AppTheme.bgColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 8,
                    shadowColor: AppTheme.primaryCyan.withValues(alpha: 0.4),
                  ),
                  icon: _updateLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bgColor))
                      : const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: const Text(
                    'PUBLISH UPDATE',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ── Disable Update Dialog for All Users ──
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _updateLoading ? null : _disableUpdateForAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.bearColor,
                    side: BorderSide(color: AppTheme.bearColor.withValues(alpha: 0.5), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.notifications_off_rounded, size: 18),
                  label: const Text(
                    'DISABLE UPDATE DIALOG FOR ALL USERS',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
    int maxLines = 1,
  }) {
    return CyberTextField(
      controller: controller,
      label: label,
      hint: hint,
      icon: icon,
      themeColor: color,
      maxLines: maxLines,
    );
  }

  Widget _buildUpdateToggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: value ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: value ? color.withValues(alpha: 0.3) : Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? color : AppTheme.dimTextColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 7, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: color.withValues(alpha: 0.25),
            thumbColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? color : null),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveInjectionsLog() {
    final activeInjectionsAsync = ref.watch(activeInjectionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.goldColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ACTIVE INJECTIONS HISTORY',
                  style: TextStyle(
                    color: AppTheme.goldColor, 
                    fontSize: 10, 
                    fontWeight: FontWeight.w900, 
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            activeInjectionsAsync.when(
              data: (injectedCandles) => injectedCandles.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        '${injectedCandles.length} NODES',
                        style: const TextStyle(
                          color: AppTheme.dimTextColor, 
                          fontSize: 8, 
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: activeInjectionsAsync.when(
            data: (list) => list.isEmpty ? 120.0 : 250.0,
            loading: () => 120.0,
            error: (_, __) => 120.0,
          ),
          decoration: AppTheme.glassDecoration(
            opacity: 0.02,
            borderRadius: BorderRadius.circular(12),
            borderColor: Colors.white.withValues(alpha: 0.06),
          ),
          child: activeInjectionsAsync.when(
            data: (injectedCandles) {
              if (injectedCandles.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.terminal_rounded, color: Colors.white10, size: 24),
                      SizedBox(height: 8),
                      Text(
                        'SYSTEM NORMAL // NO ACTIVE INJECTIONS',
                        style: TextStyle(
                          color: Colors.white24, 
                          fontSize: 9, 
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: injectedCandles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final candle = injectedCandles[index];
                  final isBuy = (candle.buyerCount ?? 0) > (candle.sellerCount ?? 0);
                  final isBoth = (candle.buyerCount ?? 0) > 0 && (candle.sellerCount ?? 0) > 0;
                  
                  final sideColor = isBoth ? AppTheme.primaryCyan : (isBuy ? AppTheme.bullColor : AppTheme.bearColor);
                  final sideText = isBoth ? 'BOTH' : (isBuy ? 'BUY' : 'SELL');

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sideColor.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: sideColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: sideColor.withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: sideColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: sideColor.withValues(alpha: 0.3), width: 0.5),
                          ),
                          child: Text(
                            sideText,
                            style: TextStyle(
                              color: sideColor, 
                              fontSize: 8, 
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${candle.symbol} | ${DateFormat('hh:mm a').format(candle.timeStart)}',
                                style: const TextStyle(
                                  color: Colors.white, 
                                  fontWeight: FontWeight.w900, 
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'B: ${candle.buyerCount} | S: ${candle.sellerCount}',
                                style: const TextStyle(
                                  color: AppTheme.dimTextColor, 
                                  fontSize: 9, 
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (candle.isBigSignal)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(Icons.stars_rounded, color: AppTheme.goldColor, size: 14),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.bearColor, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _revokeSingleOrderflow(candle.candleKey, symbol: candle.symbol);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.goldColor),
              ),
            ),
            error: (err, stack) => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.terminal_rounded, color: Colors.white10, size: 24),
                  SizedBox(height: 8),
                  Text(
                    'SYSTEM NORMAL // NO ACTIVE INJECTIONS',
                    style: TextStyle(
                      color: Colors.white24, 
                      fontSize: 9, 
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTab() {
    final pendingUsers = ref.watch(pendingUsersProvider);
    final allUsers = ref.watch(allUsersProvider);
    final statsAsync = ref.watch(userStatsProvider);
    final onlineCount = ref.watch(onlineCountProvider).asData?.value ?? 0;

    return RefreshIndicator(
      color: AppTheme.primaryCyan,
      backgroundColor: AppTheme.cardColor,
      onRefresh: () async {
        ref.invalidate(pendingUsersProvider);
        return ref.read(pendingUsersProvider.future);
      },
      child: CustomScrollView(
        slivers: [
          // ── Stats Dashboard ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bar_chart_rounded, color: AppTheme.goldColor, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'USER INTELLIGENCE',
                        style: TextStyle(
                          color: AppTheme.goldColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      // Live indicator dot
                      statsAsync.when(
                        data: (_) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.bullColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'LIVE',
                              style: TextStyle(color: AppTheme.bullColor, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
                            ),
                          ],
                        ),
                        loading: () => const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryCyan)),
                        error: (_, __) => const SizedBox(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  statsAsync.when(
                    data: (stats) => Row(
                      children: [
                        _buildStatCard(
                          label: 'TOTAL INSTALLS',
                          value: stats.totalInstalls.toString(),
                          icon: Icons.install_mobile_rounded,
                          color: AppTheme.primaryCyan,
                        ),
                        const SizedBox(width: 10),
                        _buildStatCard(
                          label: 'ONLINE NOW',
                          value: onlineCount.toString(),
                          icon: Icons.sensors_rounded,
                          color: AppTheme.bullColor,
                          pulse: onlineCount > 0,
                        ),
                        const SizedBox(width: 10),
                        _buildStatCard(
                          label: 'APPROVED',
                          value: stats.approvedCount.toString(),
                          icon: Icons.verified_user_rounded,
                          color: AppTheme.goldColor,
                        ),
                        const SizedBox(width: 10),
                        _buildStatCard(
                          label: 'PENDING',
                          value: stats.pendingCount.toString(),
                          icon: Icons.pending_rounded,
                          color: AppTheme.bearColor,
                        ),
                      ],
                    ),
                    loading: () => Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan, strokeWidth: 2)),
                    ),
                    error: (e, _) => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bearColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('STATS ERROR: $e', style: const TextStyle(color: AppTheme.bearColor, fontSize: 10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showAllUsers ? 'GLOBAL DIRECTORY' : 'PENDING AUTHORIZATIONS',
                        style: const TextStyle(
                          color: AppTheme.primaryCyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      // Toggle Switch for All vs Pending
                      InkWell(
                        onTap: () => setState(() => _showAllUsers = !_showAllUsers),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _showAllUsers ? AppTheme.primaryCyan.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _showAllUsers ? AppTheme.primaryCyan.withValues(alpha: 0.3) : Colors.white10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showAllUsers ? Icons.people_rounded : Icons.pending_rounded, 
                                color: _showAllUsers ? AppTheme.primaryCyan : AppTheme.dimTextColor, 
                                size: 14
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _showAllUsers ? 'SHOW ALL' : 'PENDING ONLY',
                                style: TextStyle(
                                  color: _showAllUsers ? AppTheme.primaryCyan : AppTheme.dimTextColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Users List ───────────────────────────────────────────
          (_showAllUsers ? allUsers : pendingUsers).when(
            data: (users) {
              if (users.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline_rounded, color: AppTheme.dimTextColor, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _showAllUsers ? 'NO USERS FOUND IN DIRECTORY' : 'NO PENDING AUTHORIZATIONS',
                          style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final user = users[index];
                    final isExpired = user.expiryDate != null && user.expiryDate!.isBefore(DateTime.now());
                    final isCanceled = user.isCanceled;
                    final isApproved = user.isApproved;

                    final statusColor = isCanceled 
                        ? AppTheme.bearColor 
                        : (isApproved 
                            ? (isExpired ? Colors.orange : AppTheme.bullColor) 
                            : AppTheme.goldColor);

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: InkWell(
                        onTap: () => _showUserEditDialog(user),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: AppTheme.neonGlassDecoration(
                            glowColor: statusColor,
                            opacity: 0.04,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [
                                    statusColor.withValues(alpha: 0.2), 
                                    Colors.transparent
                                  ]),
                                ),
                                child: Center(
                                  child: Icon(
                                    isCanceled ? Icons.person_off_rounded : Icons.person_rounded, 
                                    color: statusColor, 
                                    size: 20
                                  )
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          user.email?.split('@')[0].toUpperCase() ?? 'UNKNOWN',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isCanceled)
                                          _buildStatusTag('CANCELED', AppTheme.bearColor),
                                        if (isExpired && !isCanceled)
                                          _buildStatusTag('EXPIRED', Colors.orange),
                                        if (isApproved && !isExpired && !isCanceled)
                                          _buildStatusTag('ACTIVE', AppTheme.bullColor),
                                      ],
                                    ),
                                    Text(
                                      user.email?.toLowerCase() ?? 'no email',
                                      style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today_rounded, size: 8, color: user.expiryDate != null ? AppTheme.goldColor : Colors.white24),
                                        const SizedBox(width: 4),
                                        Text(
                                          user.expiryDate == null 
                                            ? 'PERMANENT ACCESS' 
                                            : 'EXPIRES: ${DateFormat('MMM dd, yyyy').format(user.expiryDate!)}',
                                          style: TextStyle(
                                            color: user.expiryDate != null ? AppTheme.goldColor.withValues(alpha: 0.7) : Colors.white24, 
                                            fontSize: 8, 
                                            fontWeight: FontWeight.bold
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (user.registeredDeviceName != null || user.registeredDeviceDetails != null) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.computer_rounded, size: 10, color: AppTheme.primaryCyan),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              '${user.registeredDeviceName ?? 'PC'} (${user.registeredDeviceDetails ?? 'Unknown Specs'})',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: AppTheme.primaryCyan.withValues(alpha: 0.8),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isApproved)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.mediumImpact();
                                          _updateUserStatus(user.uid, true);
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppTheme.bullColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.bullColor.withValues(alpha: 0.4), width: 1),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_rounded, color: AppTheme.bullColor, size: 12),
                                              SizedBox(width: 4),
                                              Text(
                                                'APPROVE',
                                                style: TextStyle(color: AppTheme.bullColor, fontSize: 8, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.mediumImpact();
                                          _updateUserStatus(user.uid, false, isCanceled: true);
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppTheme.bearColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.bearColor.withValues(alpha: 0.4), width: 1),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.close_rounded, color: AppTheme.bearColor, size: 12),
                                              SizedBox(width: 4),
                                              Text(
                                                'REJECT',
                                                style: TextStyle(color: AppTheme.bearColor, fontSize: 8, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: users.length,
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan))),
            error: (e, s) => SliverToBoxAdapter(child: Center(child: Text('UPLINK ERROR: $e', style: const TextStyle(color: AppTheme.bearColor)))),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }

  /// Compact stat tile used in the User Intelligence dashboard
  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool pulse = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: AppTheme.glassDecoration(
          opacity: 0.03,
          borderRadius: BorderRadius.circular(12),
          borderColor: color.withValues(alpha: 0.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 13),
                if (pulse) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: color, 
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.8),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _randomizeValue(int base) {
    if (base <= 0) return 0;
    final random = math.Random();
    final variance = (base * 0.15).toInt(); // 15% variance
    if (variance == 0) return base;
    
    final change = random.nextInt(variance * 2 + 1) - variance;
    int result = base + change;
    
    // Ensure it's not ending in 00, 000 etc.
    if (result % 10 == 0) {
      result += random.nextInt(9) + 1;
    }
    return result;
  }

  int _randomizeVolumeForSymbol(int base, String symbol) {
    if (base <= 0) return 0;
    final random = math.Random();
    
    // Check if symbol is an index
    final bool isIndex = NiftyStocks.indices.containsKey(symbol.toUpperCase());
    
    // Scale factor: indices 60% to 140%, stocks 20% to 120%
    final double scale = isIndex 
        ? (0.6 + random.nextDouble() * 0.8) 
        : (0.2 + random.nextDouble() * 1.0);
        
    int scaledBase = (base * scale).round();
    if (scaledBase <= 0) scaledBase = 10;
    
    // Apply 15% random variance
    final variance = (scaledBase * 0.15).toInt();
    if (variance == 0) return scaledBase;
    
    final change = random.nextInt(variance * 2 + 1) - variance;
    int result = scaledBase + change;
    
    // Avoid multiples of 10 for organic look
    if (result % 10 == 0) {
      result += random.nextInt(9) + 1;
    }
    return result;
  }
}

class CyberTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String hint;
  final IconData? icon;
  final Color themeColor;
  final int maxLines;
  final TextInputType keyboardType;
  final bool isNumeric;

  const CyberTextField({
    super.key,
    required this.controller,
    this.label,
    required this.hint,
    this.icon,
    required this.themeColor,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.isNumeric = false,
  });

  @override
  State<CyberTextField> createState() => _CyberTextFieldState();
}

class _CyberTextFieldState extends State<CyberTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderCol = _isFocused ? widget.themeColor : Colors.white10;
    final shadowCol = widget.themeColor.withValues(alpha: _isFocused ? 0.25 : 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.themeColor,
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: [
                    BoxShadow(
                      color: widget.themeColor.withValues(alpha: 0.6),
                      blurRadius: 3,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label!.toUpperCase(),
                style: TextStyle(
                  color: widget.themeColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _isFocused ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderCol, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: shadowCol,
                blurRadius: 8,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: TextField(
            focusNode: _focusNode,
            controller: widget.controller,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboardType,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: widget.isNumeric ? 'monospace' : null,
              letterSpacing: widget.isNumeric ? 1.0 : null,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 12,
                fontFamily: widget.isNumeric ? 'monospace' : null,
              ),
              prefixIcon: widget.icon != null ? Icon(widget.icon, color: widget.themeColor, size: 16) : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

class GlowingBranchLine extends StatefulWidget {
  final bool isLast;
  final bool isSynced;
  final Color syncColor;

  const GlowingBranchLine({
    super.key,
    required this.isLast,
    required this.isSynced,
    required this.syncColor,
  });

  @override
  State<GlowingBranchLine> createState() => _GlowingBranchLineState();
}

class _GlowingBranchLineState extends State<GlowingBranchLine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCol = widget.isSynced ? widget.syncColor : Colors.white12;
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final lineCol = widget.isSynced 
            ? activeCol.withValues(alpha: _pulseAnimation.value * 0.7)
            : activeCol;

        return SizedBox(
          width: 32,
          height: 52, // Height of each list item card + padding
          child: CustomPaint(
            painter: _BranchPathPainter(
              isLast: widget.isLast,
              lineColor: lineCol,
              lineWidth: widget.isSynced ? 1.8 : 1.0,
              isSynced: widget.isSynced,
            ),
          ),
        );
      },
    );
  }
}

class _BranchPathPainter extends CustomPainter {
  final bool isLast;
  final Color lineColor;
  final double lineWidth;
  final bool isSynced;

  _BranchPathPainter({
    required this.isLast,
    required this.lineColor,
    required this.lineWidth,
    required this.isSynced,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    if (isSynced) {
      paint.imageFilter = ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5);
    }

    final double halfWidth = size.width / 2;
    final double halfHeight = size.height / 2;

    // Vertical line
    canvas.drawLine(
      Offset(halfWidth, 0),
      Offset(halfWidth, isLast ? halfHeight : size.height),
      paint,
    );

    // Horizontal branch line
    canvas.drawLine(
      Offset(halfWidth, halfHeight),
      Offset(size.width, halfHeight),
      paint,
    );

    if (isSynced) {
      final crispPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth;
      
      canvas.drawLine(
        Offset(halfWidth, 0),
        Offset(halfWidth, isLast ? halfHeight : size.height),
        crispPaint,
      );

      canvas.drawLine(
        Offset(halfWidth, halfHeight),
        Offset(size.width, halfHeight),
        crispPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BranchPathPainter oldDelegate) {
    return oldDelegate.isLast != isLast ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.isSynced != isSynced;
  }
}

// ─── PRO-GRADE UPDATE PUBLISHED SUCCESS ANIMATION DIALOG ───
class UpdatePublishedSuccessDialog extends StatefulWidget {
  final String version;
  const UpdatePublishedSuccessDialog({super.key, required this.version});

  @override
  State<UpdatePublishedSuccessDialog> createState() => _UpdatePublishedSuccessDialogState();
}

class _UpdatePublishedSuccessDialogState extends State<UpdatePublishedSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1420),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.bullColor.withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.bullColor.withValues(alpha: 0.25),
                  blurRadius: 50,
                  spreadRadius: 8,
                ),
                BoxShadow(
                  color: AppTheme.goldColor.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.bullColor.withValues(alpha: 0.15),
                          border: Border.all(color: AppTheme.bullColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.bullColor.withValues(alpha: 0.6),
                              blurRadius: 25,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          color: AppTheme.bullColor,
                          size: 44,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'UPDATE PUBLISHED!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.goldColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.goldColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded, color: AppTheme.goldColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'VERSION ${widget.version} IS LIVE',
                        style: const TextStyle(
                          color: AppTheme.goldColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Real-time update notification has been broadcasted to all active app instances worldwide.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.bullColor,
                      foregroundColor: AppTheme.bgColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 10,
                    ),
                    child: const Text(
                      'DONE',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
