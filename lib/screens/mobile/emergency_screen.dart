import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/location_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class _NearbyProvider {
  final String id;
  final String name;
  final double distanceKm;
  final double? lat;
  final double? lng;
  final double ratingAvg;

  const _NearbyProvider({
    required this.id,
    required this.name,
    required this.distanceKm,
    this.lat,
    this.lng,
    this.ratingAvg = 0.0,
  });
}

class EmergencyScreen extends StatefulWidget {
  final CustomerProfile profile;
  const EmergencyScreen({super.key, required this.profile});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _db = Supabase.instance.client;
  final _locationService = LocationService();
  final _notifs = NotificationsService.instance;
  final _mapController = MapController();
  final _carCtrl = TextEditingController();

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _loadingRate = true;
  bool _loadingProviders = true;
  bool _submitting = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';
  double _distanceKm = 6.0;
  double _kmRate = 1.5;
  double _nearbyRadiusKm = 15.0;

  List<_NearbyProvider> _nearbyProviders = [];
  List<_NearbyProvider> _allAvailableProviders = [];
  Timer? _providersRefreshTimer;

  // حالة انتظار قبول الطلب (5 دقائق)
  String? _waitingRequestId;
  bool _waitingIsWinch = false;
  bool _timedOutNoProvider = false;
  int _remainingSeconds = 300;
  double _lastOrderPrice = 0.0;
  int _lastOrderEta = 10;
  Timer? _waitTickTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _waitStreamSub;

  final Map<String, double> _baseFees = const {
    'بطارية': 15.0,
    'إطار': 12.0,
    'محرك': 25.0,
    'وقود': 10.0,
    'حادث': 35.0,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _detectMyLocation();
    // تحديث مواقع السيارات على الخريطة كل 8 ثوانٍ لحركة حية
    _providersRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _loadNearestProviders(silent: true);
    });
  }

  @override
  void dispose() {
    _providersRefreshTimer?.cancel();
    _waitTickTimer?.cancel();
    _waitStreamSub?.cancel();
    _carCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', ['winch_price_per_km', 'emergency_search_radius_km']);
      if (!mounted) return;
      double kmRate = _kmRate;
      double radius = _nearbyRadiusKm;
      for (final row in (rows as List)) {
        final k = row['key'] as String?;
        final v = double.tryParse(row['value']?.toString() ?? '');
        if (k == 'winch_price_per_km' && v != null && v > 0) kmRate = v;
        if (k == 'emergency_search_radius_km' && v != null && v > 0) radius = v;
      }
      setState(() {
        _kmRate = kmRate;
        _nearbyRadiusKm = radius;
        _loadingRate = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRate = false);
    }
  }

  Future<void> _loadNearestProviders({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingProviders = true);
    try {
      final useWinch = EnvConfig.winchEnabled.value && _serviceType == 'winch';
      final rows = await _db
          .from('customers')
          .select(
            'id, full_name, username, role, has_towing, is_available, latitude, longitude, workshop_latitude, workshop_longitude, rating_avg',
          )
          .eq('is_available', true)
          .inFilter('role', ['mechanic', 'towing']);

      final all = <_NearbyProvider>[];
      for (final r in (rows as List)) {
        final map = Map<String, dynamic>.from(r as Map);
        final id = (map['id'] as String?) ?? '';
        if (id.isEmpty || id == widget.profile.id) continue;

        final role = (map['role'] as String?) ?? '';
        final hasTowing = map['has_towing'] == true;
        final matchesType = useWinch
            ? (role == 'towing' || hasTowing)
            : (role == 'mechanic');
        if (!matchesType) continue;

        final lat = (map['latitude'] as num?)?.toDouble() ??
            (map['workshop_latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble() ??
            (map['workshop_longitude'] as num?)?.toDouble();

        double distKm = 9999.0;
        if (lat != null && lng != null) {
          distKm = Geolocator.distanceBetween(
                _pickupLatLng.latitude,
                _pickupLatLng.longitude,
                lat,
                lng,
              ) /
              1000.0;
        }

        final name = ((map['full_name'] as String?)?.trim().isNotEmpty == true)
            ? (map['full_name'] as String).trim()
            : ((map['username'] as String?) ??
                (useWinch ? 'ونش طوارئ' : 'ميكانيكي طوارئ'));

        all.add(
          _NearbyProvider(
            id: id,
            name: name,
            distanceKm: distKm,
            lat: lat,
            lng: lng,
            ratingAvg: (map['rating_avg'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }

      all.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      final nearby = all
          .where((p) =>
              p.lat != null && p.lng != null && p.distanceKm <= _nearbyRadiusKm)
          .toList();

      if (!mounted) return;
      setState(() {
        _allAvailableProviders = all;
        _nearbyProviders = nearby;
        _loadingProviders = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  Future<void> _detectMyLocation() async {
    setState(() => _loadingGps = true);
    try {
      final res = await _locationService.getCurrentLocation();
      if (!mounted) return;
      final dist =
          _locationService.calculateDistanceKm(res.coordinates, _dropoffLatLng);
      setState(() {
        _pickupLatLng = res.coordinates;
        _pickupAddress = res.address;
        _distanceKm = dist < 0.5 ? 1.0 : double.parse(dist.toStringAsFixed(2));
        _loadingGps = false;
      });
      _mapController.move(_pickupLatLng, 13.5);
      await _loadNearestProviders();
    } catch (_) {
      if (mounted) setState(() => _loadingGps = false);
      await _loadNearestProviders();
    }
  }

  Future<void> _onMapTap(LatLng latLng) async {
    FocusScope.of(context).unfocus();
    final addr = await _locationService.getAddressFromLatLng(latLng);
    if (!mounted) return;
    setState(() {
      if (_pickingDropoff &&
          _serviceType == 'winch' &&
          EnvConfig.winchEnabled.value) {
        _dropoffLatLng = latLng;
        _dropoffAddress = addr;
      } else {
        _pickupLatLng = latLng;
        _pickupAddress = addr;
      }
      final dist =
          _locationService.calculateDistanceKm(_pickupLatLng, _dropoffLatLng);
      _distanceKm = dist < 0.5 ? 1.0 : double.parse(dist.toStringAsFixed(2));
    });
    if (!_pickingDropoff) {
      await _loadNearestProviders();
    }
  }

  void _startWaitingForAcceptance(String reqId, bool isWinch) {
    _waitTickTimer?.cancel();
    _waitStreamSub?.cancel();

    setState(() {
      _waitingRequestId = reqId;
      _waitingIsWinch = isWinch;
      _timedOutNoProvider = false;
      _remainingSeconds = 300; // 5 دقائق
    });

    // متابعة فورية لحالة الطلب
    _waitStreamSub = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .eq('id', reqId)
        .listen((rows) {
          if (rows.isEmpty || !mounted) return;
          final row = rows.first;
          final status = (row['status'] as String?) ?? 'pending';
          if (status == 'accepted' || status == 'completed') {
            _waitTickTimer?.cancel();
            _waitStreamSub?.cancel();
            setState(() {
              _waitingRequestId = null;
              _timedOutNoProvider = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isWinch
                      ? 'تم قبول طلبك! ونش الطوارئ في طريقه إليك الآن ✓'
                      : 'تم قبول طلبك! ميكانيكي الطوارئ في طريقه إليك الآن ✓',
                ),
                backgroundColor: AppColors.success,
              ),
            );
          } else if (status == 'cancelled' || status == 'rejected') {
            _waitTickTimer?.cancel();
            _waitStreamSub?.cancel();
            setState(() {
              _waitingRequestId = null;
              _timedOutNoProvider = true;
            });
          }
        }, onError: (_) {});

    // عدّاد 5 دقائق
    _waitTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _waitStreamSub?.cancel();
        final expiredId = _waitingRequestId;
        if (expiredId != null) {
          try {
            await _db
                .from('mechanic_requests')
                .update({'status': 'cancelled'})
                .eq('id', expiredId)
                .eq('status', 'pending');
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _waitingRequestId = null;
            _timedOutNoProvider = true;
          });
        }
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  Future<void> _cancelWaitingOrder() async {
    final reqId = _waitingRequestId;
    _waitTickTimer?.cancel();
    _waitStreamSub?.cancel();
    setState(() {
      _waitingRequestId = null;
      _timedOutNoProvider = false;
    });
    if (reqId != null) {
      try {
        await _db
            .from('mechanic_requests')
            .update({'status': 'cancelled'})
            .eq('id', reqId)
            .eq('status', 'pending');
      } catch (_) {}
    }
  }

  Future<void> _submitOrder(
    double finalPrice,
    int etaMinutes, {
    bool forceBroadcastAll = false,
  }) async {
    FocusScope.of(context).unfocus();
    final carText = _carCtrl.text.trim();
    if (carText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة نوع وموديل السيارة أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final useWinch = EnvConfig.winchEnabled.value && _serviceType == 'winch';
    _lastOrderPrice = finalPrice;
    _lastOrderEta = etaMinutes;

    setState(() {
      _submitting = true;
      _timedOutNoProvider = false;
    });

    try {
      await _loadNearestProviders(silent: true);
      final bool broadcastAll = forceBroadcastAll || _nearbyProviders.isEmpty;

      final inserted = await _db
          .from('mechanic_requests')
          .insert({
            'user_id': widget.profile.id,
            'service_type': useWinch ? 'winch' : 'mechanic',
            'car_details': carText,
            'phone': widget.profile.phone,
            'description': _selectedProblem,
            'latitude': null,
            'longitude': null,
            'pickup_latitude': _pickupLatLng.latitude,
            'pickup_longitude': _pickupLatLng.longitude,
            'dropoff_latitude': useWinch ? _dropoffLatLng.latitude : null,
            'dropoff_longitude': useWinch ? _dropoffLatLng.longitude : null,
            'dropoff_address': useWinch ? _dropoffAddress : _pickupAddress,
            'total_amount': (useWinch || EnvConfig.paymentsEnabled.value)
                ? finalPrice
                : 0.0,
            'estimated_time': '$etaMinutes دقيقة',
            'status': 'pending',
            'progress_step': 'pending',
            'broadcast_all': broadcastAll,
          })
          .select('id')
          .single();

      final reqId = inserted['id'] as String;

      final targets = broadcastAll ? _allAvailableProviders : _nearbyProviders;
      for (final provider in targets.take(25)) {
        try {
          await _notifs.sendNotification(
            targetUserId: provider.id,
            title: useWinch
                ? (broadcastAll
                    ? '🚨 طلب ونش طوارئ عام جديد'
                    : '🚨 طلب ونش طوارئ قريب منك')
                : (broadcastAll
                    ? '🚨 طلب ميكانيكي طوارئ عام جديد'
                    : '🚨 طلب ميكانيكي طوارئ قريب منك'),
            body: '$_selectedProblem · $carText · $_pickupAddress',
            type: 'emergency_request',
            referenceId: reqId,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      _startWaitingForAcceptance(reqId, useWinch);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إرسال الطلب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatCountdown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EnvConfig.winchEnabled,
        EnvConfig.paymentsEnabled,
      ]),
      builder: (context, _) {
        final showWinch = EnvConfig.winchEnabled.value;
        final showPayments = EnvConfig.paymentsEnabled.value;

        if (!showWinch && _serviceType == 'winch') {
          _serviceType = 'mechanic';
          _pickingDropoff = false;
        }

        final isWinch = showWinch && _serviceType == 'winch';
        final baseFee = _baseFees[_selectedProblem] ?? 15.0;
        final winchDistanceCost = isWinch
            ? double.parse((_distanceKm * _kmRate).toStringAsFixed(2))
            : 5.0;
        final rawTotal = baseFee + winchDistanceCost;
        final isPro = AppSubscriptionCatalog.customerFeeRate(
              widget.profile.subscriptionPlan,
            ) ==
            0.0;
        final proDiscount = isPro
            ? double.parse((rawTotal * 0.15).toStringAsFixed(2))
            : 0.0;
        final finalPrice =
            double.parse((rawTotal - proDiscount).toStringAsFixed(2));
        final nearest =
            _nearbyProviders.isNotEmpty ? _nearbyProviders.first : null;
        final etaKm = nearest != null ? nearest.distanceKm : _distanceKm;
        final eta = (etaKm * 2.4).round().clamp(5, 45);

        // سيارات سكنية 2D على الخريطة (القريبين أو كل المتاحين)
        final mapVehicles = (_nearbyProviders.isNotEmpty
                ? _nearbyProviders
                : _allAvailableProviders)
            .where((p) => p.lat != null && p.lng != null)
            .take(12)
            .toList();

        return SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            showWinch
                                ? 'طلب مساعدة طارئة'
                                : 'طلب ميكانيكي طوارئ',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'تحديث أقرب المزوّدين',
                          onPressed: () {
                            _loadSettings();
                            _loadNearestProviders();
                          },
                          icon: const Icon(
                            Icons.refresh,
                            color: AppColors.navy,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // شريط انتظار قبول الطلب (خط يتحرك يمين وشمال) أو رسالة انتهاء الـ 5 دقائق
                    if (_waitingRequestId != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _waitingIsWinch
                                      ? Icons.local_shipping_rounded
                                      : Icons.build_circle_rounded,
                                  color: AppColors.orange,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _waitingIsWinch
                                        ? 'بانتظار قبول ونش طوارئ...'
                                        : 'بانتظار قبول ميكانيكي طوارئ...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _formatCountdown(_remainingSeconds),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const _SlidingRadarBar(),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'سيظهر التتبع المباشر على الشاشة الرئيسية فور قبول طلبك',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _cancelWaitingOrder,
                                  child: const Text(
                                    'إلغاء الطلب',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (_timedOutNoProvider) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _waitingIsWinch
                                        ? 'عذراً، لا يوجد ونش طوارئ متاح حالياً'
                                        : 'عذراً، لا يوجد ميكانيكي طوارئ متاح حالياً',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'مضت 5 دقائق دون قبول الطلب. يمكنك إعادة إرسال الطلب لجميع المزوّدين المتاحين الآن.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _submitting
                                  ? null
                                  : () => _submitOrder(
                                        _lastOrderPrice > 0
                                            ? _lastOrderPrice
                                            : finalPrice,
                                        _lastOrderEta > 0 ? _lastOrderEta : eta,
                                        forceBroadcastAll: true,
                                      ),
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text(
                                'إعادة الطلب',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (showWinch) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            _segTab('ونش سحب', isWinch, () {
                              setState(() => _serviceType = 'winch');
                              _loadSettings();
                              _loadNearestProviders();
                            }),
                            _segTab('ميكانيكي طوارئ', !isWinch, () {
                              setState(() {
                                _serviceType = 'mechanic';
                                _pickingDropoff = false;
                              });
                              _loadNearestProviders();
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (isWinch)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('نقطة الالتقاط (موقعك)'),
                                ),
                                selected: !_pickingDropoff,
                                selectedColor: AppColors.navy,
                                labelStyle: TextStyle(
                                  color: !_pickingDropoff
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (_) =>
                                    setState(() => _pickingDropoff = false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('تحديد الوجهة على الخريطة'),
                                ),
                                selected: _pickingDropoff,
                                selectedColor: AppColors.orange,
                                labelStyle: TextStyle(
                                  color: _pickingDropoff
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (_) =>
                                    setState(() => _pickingDropoff = true),
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(
                      height: 220,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _pickupLatLng,
                                initialZoom: 13.5,
                                onTap: (_, latLng) => _onMapTap(latLng),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.autoparts.app',
                                ),
                                if (isWinch)
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: [
                                          _pickupLatLng,
                                          _dropoffLatLng
                                        ],
                                        color: AppColors.orange,
                                        strokeWidth: 4,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    // سيارات سكنية 2D للميكانيكيين / الونشات
                                    ...mapVehicles.map(
                                      (p) => Marker(
                                        point: LatLng(p.lat!, p.lng!),
                                        width: 46,
                                        height: 46,
                                        child: Tooltip(
                                          message:
                                              '${p.name} (${p.distanceKm.toStringAsFixed(1)} كم)',
                                          child: _GreyCar2DMarker(
                                            isWinch: isWinch,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Marker(
                                      point: _pickupLatLng,
                                      width: 72,
                                      height: 72,
                                      child: const PulsingPin(
                                        color: AppColors.orange,
                                      ),
                                    ),
                                    if (isWinch)
                                      Marker(
                                        point: _dropoffLatLng,
                                        width: 44,
                                        height: 44,
                                        child: const Icon(
                                          Icons.flag,
                                          color: AppColors.navy,
                                          size: 34,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              bottom: 10,
                              left: 10,
                              child: FloatingActionButton.small(
                                heroTag: 'emg_gps_btn',
                                backgroundColor: AppColors.navy,
                                foregroundColor: Colors.white,
                                onPressed: _detectMyLocation,
                                child: _loadingGps
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.my_location),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // حالة أقرب مزوّد أو البث للجميع
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: nearest != null
                            ? AppColors.success.withValues(alpha: 0.08)
                            : AppColors.orangeLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: nearest != null
                              ? AppColors.success.withValues(alpha: 0.35)
                              : AppColors.orange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: _loadingProviders
                          ? const Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.navy,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'جاري البحث عن أقرب مزوّد متاح حولك...',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ],
                            )
                          : nearest != null
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 38,
                                      height: 38,
                                      child: _GreyCar2DMarker(isWinch: isWinch),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'أقرب ${isWinch ? 'ونش' : 'ميكانيكي'} متاح: ${nearest.name}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                              color: AppColors.navy,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'يبعد عنك ${nearest.distanceKm.toStringAsFixed(1)} كم${nearest.ratingAvg > 0 ? ' · ★ ${nearest.ratingAvg.toStringAsFixed(1)}' : ''} · متاح ${_nearbyProviders.length} بالقرب منك',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.success,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    const Icon(
                                      Icons.campaign_rounded,
                                      color: AppColors.orange,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'لا يوجد ${isWinch ? 'ونش' : 'ميكانيكي'} قريب ضمن ${_nearbyRadiusKm.toInt()} كم حالياً — سيتم إرسال طلبك تلقائياً لجميع المزوّدين المتاحين (${_allAvailableProviders.length}).',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.navy,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                    ),

                    const SizedBox(height: 10),
                    _infoRow('موقعك الحالي', _pickupAddress),
                    if (isWinch) ...[
                      const SizedBox(height: 8),
                      _infoRow('الوجهة المطلوبة', _dropoffAddress),
                      const SizedBox(height: 8),
                      _infoRow(
                        'المسافة التقديرية',
                        '${_distanceKm.toStringAsFixed(1)} كم',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _carCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                        labelText: 'نوع وموديل السيارة',
                        hintText: 'مثال: تويوتا كامري 2022',
                        prefixIcon: const Icon(Icons.directions_car_outlined),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'ما المشكلة؟',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _baseFees.keys.map((problem) {
                        final selected = _selectedProblem == problem;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedProblem = problem),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.orangeLight
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: selected
                                    ? AppColors.orange
                                    : AppColors.border,
                                width: selected ? 1.6 : 1,
                              ),
                            ),
                            child: Text(
                              problem,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.orange
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _infoRow('الوصول المتوقع', '$eta دقيقة'),
                          if (isWinch || showPayments) ...[
                            const Divider(height: 18),
                            _infoRow(
                              'رسوم الخدمة الأساسية ($_selectedProblem)',
                              '${baseFee.toStringAsFixed(2)} د.أ',
                            ),
                            const SizedBox(height: 6),
                            if (isWinch)
                              _infoRow(
                                _loadingRate
                                    ? 'أجرة السحب (جاري تحميل التسعيرة...)'
                                    : 'أجرة السحب (${_distanceKm.toStringAsFixed(1)} كم × ${_kmRate.toStringAsFixed(2)} د.أ)',
                                '${winchDistanceCost.toStringAsFixed(2)} د.أ',
                              )
                            else
                              _infoRow(
                                'بدل حضور فني الطوارئ',
                                '${winchDistanceCost.toStringAsFixed(2)} د.أ',
                              ),
                            if (isPro) ...[
                              const SizedBox(height: 6),
                              _infoRow(
                                'خصم عضوية برو (15%)',
                                '-${proDiscount.toStringAsFixed(2)} د.أ',
                                valueColor: AppColors.success,
                              ),
                            ],
                            const Divider(height: 18),
                            _infoRow(
                              'الإجمالي التقديري',
                              '${finalPrice.toStringAsFixed(2)} د.أ',
                              bold: true,
                              valueColor: AppColors.navy,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_waitingRequestId == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: BounceTap(
                    onTap: _submitting
                        ? () {}
                        : () => _submitOrder(finalPrice, eta),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.4,
                              ),
                            )
                          : Text(
                              isWinch
                                  ? 'تأكيد طلب الونش (${finalPrice.toStringAsFixed(2)} د.أ)'
                                  : 'تأكيد طلب الطوارئ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _segTab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: bold ? 14 : 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(
            color: valueColor ?? AppColors.textSecondary,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 15 : 13,
          ),
        ),
      ],
    );
  }
}

/// شريط تحميل يتحرك بسلاسة يمين وشمال أثناء انتظار قبول الطلب
class _SlidingRadarBar extends StatefulWidget {
  const _SlidingRadarBar();

  @override
  State<_SlidingRadarBar> createState() => _SlidingRadarBarState();
}

class _SlidingRadarBarState extends State<_SlidingRadarBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final alignX = -1.0 + (_ctrl.value * 2.0);
          return Align(
            alignment: Alignment(alignX, 0),
            child: FractionallySizedBox(
              widthFactor: 0.36,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// سيارة سكنية 2D (منظور علوي مثل Uber) للميكانيكي أو الونش
class _GreyCar2DMarker extends StatelessWidget {
  final bool isWinch;
  const _GreyCar2DMarker({required this.isWinch});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(40, 40),
      painter: _GreyCar2DPainter(isWinch: isWinch),
    );
  }
}

class _GreyCar2DPainter extends CustomPainter {
  final bool isWinch;
  const _GreyCar2DPainter({required this.isWinch});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ظل ناعم تحت السيارة
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.52, h * 0.54),
          width: w * 0.48,
          height: h * 0.78,
        ),
        const Radius.circular(8),
      ),
      shadowPaint,
    );

    // العجلات الأربع
    final wheelPaint = Paint()..color = const Color(0xFF1F2937);
    final wheelRects = [
      Rect.fromLTWH(w * 0.20, h * 0.18, w * 0.09, h * 0.16),
      Rect.fromLTWH(w * 0.71, h * 0.18, w * 0.09, h * 0.16),
      Rect.fromLTWH(w * 0.20, h * 0.64, w * 0.09, h * 0.16),
      Rect.fromLTWH(w * 0.71, h * 0.64, w * 0.09, h * 0.16),
    ];
    for (final wr in wheelRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(wr, const Radius.circular(2)),
        wheelPaint,
      );
    }

    // هيكل السيارة السكني (فضي/رمادي)
    final bodyPaint = Paint()..color = const Color(0xFF9CA3AF);
    final borderPaint = Paint()
      ..color = const Color(0xFF4B5563)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.5),
        width: w * 0.46,
        height: h * 0.78,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(bodyRect, bodyPaint);
    canvas.drawRRect(bodyRect, borderPaint);

    // الزجاج الأمامي الداكن
    final glassPaint = Paint()..color = const Color(0xFF1F2937);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.32, h * 0.24, w * 0.36, h * 0.15),
        const Radius.circular(3),
      ),
      glassPaint,
    );

    if (isWinch) {
      // سطح الونش الخلفي (Flatbed) + ضوء طوارئ برتقالي
      final bedPaint = Paint()..color = const Color(0xFF6B7280);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.30, h * 0.45, w * 0.40, h * 0.38),
          const Radius.circular(3),
        ),
        bedPaint,
      );
      final beaconPaint = Paint()..color = AppColors.orange;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.36, h * 0.40, w * 0.28, h * 0.05),
          const Radius.circular(2),
        ),
        beaconPaint,
      );
    } else {
      // سقف السيارة والزجاج الخلفي للميكانيكي
      final roofPaint = Paint()..color = const Color(0xFFD1D5DB);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.33, h * 0.41, w * 0.34, h * 0.22),
          const Radius.circular(3),
        ),
        roofPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.34, h * 0.65, w * 0.32, h * 0.11),
          const Radius.circular(2.5),
        ),
        glassPaint,
      );
    }

    // المصابيح الأمامية
    final headPaint = Paint()..color = const Color(0xFFFEF08A);
    canvas.drawCircle(Offset(w * 0.35, h * 0.14), 2.1, headPaint);
    canvas.drawCircle(Offset(w * 0.65, h * 0.14), 2.1, headPaint);

    // المصابيح الخلفية
    final tailPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(Offset(w * 0.35, h * 0.86), 1.9, tailPaint);
    canvas.drawCircle(Offset(w * 0.65, h * 0.86), 1.9, tailPaint);
  }

  @override
  bool shouldRepaint(covariant _GreyCar2DPainter oldDelegate) =>
      oldDelegate.isWinch != isWinch;
}