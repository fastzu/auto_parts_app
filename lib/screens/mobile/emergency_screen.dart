import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../services/location_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/service_rating_dialog.dart';
import 'workshop_checkout_screen.dart';

class EmergencyScreen extends StatefulWidget {
  final CustomerProfile profile;
  const EmergencyScreen({super.key, required this.profile});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with TickerProviderStateMixin {
  final _db = Supabase.instance.client;
  final _locationService = LocationService();
  final _notifs = NotificationsService.instance;
  final _loc = AppLocaleService.instance;
  final _mapController = MapController();
  final _carCtrl = TextEditingController();

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _submitting = false;
  bool _handlingQuote = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';

  // المزودون المتاحون حول العميل
  List<Map<String, dynamic>> _nearbyProviders = [];
  StreamSubscription<List<Map<String, dynamic>>>? _providersSub;

  // متابعة الطلب النشط لحظياً
  String? _activeRequestId;
  DbMechanicRequest? _activeRequest;
  StreamSubscription<List<Map<String, dynamic>>>? _activeReqSub;

  // متابعة موقع المزود الحي بعد القبول (تتبع السيارة الـ 2D وهي تقترب من العميل)
  String? _trackedProviderId;
  Map<String, dynamic>? _assignedProviderInfo;
  LatLng? _providerLivePos;
  LatLng? _prevProviderPos;
  double _providerHeadingRad = 0.0;
  StreamSubscription<List<Map<String, dynamic>>>? _providerPosSub;

  // مؤقت الانتظار 5 دقائق (300 ثانية)
  static const int _waitDurationSeconds = 300;
  Timer? _waitTimer;
  int _waitSecondsLeft = _waitDurationSeconds;
  bool _timedOutNoProvider = false;
  late final AnimationController _radarSlideCtrl;
  bool _ratingPrompted = false;

  final List<({String key, String ar, String en, IconData icon})> _problems =
      const [
    (key: 'بطارية', ar: 'بطارية', en: 'Battery', icon: Icons.battery_alert),
    (key: 'إطار', ar: 'بنشر / إطار', en: 'Flat Tire', icon: Icons.tire_repair),
    (key: 'محرك', ar: 'عطل محرك', en: 'Engine', icon: Icons.engineering),
    (key: 'وقود', ar: 'نفاد وقود', en: 'Fuel', icon: Icons.local_gas_station),
    (key: 'حادث', ar: 'حادث / سحب', en: 'Accident', icon: Icons.car_crash),
  ];

  @override
  void initState() {
    super.initState();
    _carCtrl.text = _loc.tr('تويوتا كامري 2022', 'Toyota Camry 2022');
    _radarSlideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _detectMyLocation();
    _listenAvailableProviders();
    _restoreExistingActiveRequest();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _providersSub?.cancel();
    _activeReqSub?.cancel();
    _providerPosSub?.cancel();
    _radarSlideCtrl.dispose();
    _carCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectMyLocation() async {
    setState(() => _loadingGps = true);
    final res = await _locationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _pickupLatLng = res.coordinates;
      _pickupAddress = res.address;
      _loadingGps = false;
    });
    try {
      _mapController.move(_pickupLatLng, 14.2);
    } catch (_) {}
  }

  void _listenAvailableProviders() {
    _providersSub?.cancel();
    _providersSub = _db
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('is_available', true)
        .listen((rows) {
      if (!mounted) return;
      final filtered = rows.where((r) {
        final role = (r['role'] as String?) ?? '';
        final isDeleted = r['is_deleted'] == true;
        if (isDeleted) return false;
        final lat = (r['latitude'] as num?)?.toDouble() ??
            (r['workshop_latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble() ??
            (r['workshop_longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return false;
        if (_serviceType == 'winch') {
          return role == 'towing' || (role == 'mechanic' && r['has_towing'] == true);
        }
        return role == 'mechanic';
      }).toList();
      setState(() => _nearbyProviders = filtered);
    }, onError: (_) {});
  }

  Future<void> _restoreExistingActiveRequest() async {
    try {
      final rows = await _db
          .from('mechanic_requests')
          .select()
          .eq('user_id', widget.profile.id)
          .order('created_at', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty || !mounted) return;
      final req = DbMechanicRequest.fromMap(
        Map<String, dynamic>.from(rows.first as Map),
      );
      final isActive = req.status == 'pending' ||
          req.status == 'quote_sent' ||
          req.status == 'accepted' ||
          (req.status == 'completed' &&
              req.totalAmount > 0 &&
              req.paymentStatus != 'paid');
      if (isActive) {
        _bindActiveRequestStream(req.id, restartTimer: req.status == 'pending');
      }
    } catch (_) {}
  }

  void _bindActiveRequestStream(String requestId, {bool restartTimer = false}) {
    _activeRequestId = requestId;
    _activeReqSub?.cancel();
    _timedOutNoProvider = false;
    if (restartTimer) _startWaitTimer();

    _activeReqSub = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .eq('id', requestId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final req = DbMechanicRequest.fromMap(rows.first);
      setState(() {
        _activeRequest = req;
        if (req.pickupLatitude != null && req.pickupLongitude != null) {
          _pickupLatLng = LatLng(req.pickupLatitude!, req.pickupLongitude!);
        }
      });

      if (req.status == 'pending') {
        _stopProviderLiveTracking();
        if (_waitTimer == null || !_waitTimer!.isActive) {
          _startWaitTimer();
        }
      } else {
        _waitTimer?.cancel();
        _timedOutNoProvider = false;
      }

      if (req.mechanicId != null && req.mechanicId!.isNotEmpty) {
        _startProviderLiveTracking(req.mechanicId!);
      } else {
        _stopProviderLiveTracking();
      }

      // فتح التقييم تلقائياً بعد انتهاء الطلب والدفع
      if (req.status == 'completed' &&
          req.paymentStatus == 'paid' &&
          req.customerRating == null &&
          req.mechanicId != null &&
          !_ratingPrompted) {
        _ratingPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showServiceRatingDialog(
            context: context,
            serviceKind: 'emergency',
            referenceId: req.id,
            providerId: req.mechanicId!,
            providerName: _assignedProviderInfo?['full_name'] as String?,
            isWinch: req.serviceType == 'winch',
          );
        });
      }
    });
  }

  void _startProviderLiveTracking(String providerId) {
    if (_trackedProviderId == providerId && _providerPosSub != null) return;
    _trackedProviderId = providerId;
    _providerPosSub?.cancel();

    _providerPosSub = _db
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', providerId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      final lat = (row['latitude'] as num?)?.toDouble() ??
          (row['workshop_latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble() ??
          (row['workshop_longitude'] as num?)?.toDouble();

      LatLng? nextPos;
      double nextHeading = _providerHeadingRad;
      if (lat != null && lng != null) {
        nextPos = LatLng(lat, lng);
        if (_prevProviderPos != null &&
            (_prevProviderPos!.latitude != nextPos.latitude ||
                _prevProviderPos!.longitude != nextPos.longitude)) {
          nextHeading = _bearingRad(_prevProviderPos!, nextPos);
        } else {
          nextHeading = _bearingRad(nextPos, _pickupLatLng);
        }
      }

      setState(() {
        _assignedProviderInfo = row;
        _prevProviderPos = _providerLivePos;
        _providerLivePos = nextPos;
        _providerHeadingRad = nextHeading;
      });
    }, onError: (_) {});
  }

  void _stopProviderLiveTracking() {
    _providerPosSub?.cancel();
    _providerPosSub = null;
    _trackedProviderId = null;
    if (mounted) {
      setState(() {
        _providerLivePos = null;
        _assignedProviderInfo = null;
      });
    }
  }

  double _bearingRad(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * math.pi / 180.0;
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return math.atan2(y, x);
  }

  void _startWaitTimer() {
    _waitTimer?.cancel();
    setState(() {
      _waitSecondsLeft = _waitDurationSeconds;
      _timedOutNoProvider = false;
    });
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_waitSecondsLeft <= 1) {
        t.cancel();
        final reqId = _activeRequestId;
        if (reqId != null && _activeRequest?.status == 'pending') {
          try {
            await _db
                .from('mechanic_requests')
                .update({'status': 'cancelled', 'progress_step': 'cancelled'})
                .eq('id', reqId)
                .eq('status', 'pending');
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _waitSecondsLeft = 0;
            _timedOutNoProvider = true;
          });
        }
      } else {
        setState(() => _waitSecondsLeft--);
      }
    });
  }

  Future<void> _onMapTap(LatLng latLng) async {
    if (_activeRequest != null &&
        _activeRequest!.status != 'cancelled' &&
        _activeRequest!.status != 'completed') {
      return;
    }
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
    });
  }

  Future<void> _submitEmergencyRequest() async {
    final carText = _carCtrl.text.trim();
    if (carText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(_loc.tr('يرجى إدخال نوع وموديل السيارة',
              'Please enter your vehicle make & model')),
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _timedOutNoProvider = false;
      _ratingPrompted = false;
    });

    try {
      final useWinch =
          EnvConfig.winchEnabled.value && _serviceType == 'winch';

      // البحث عن أقرب مزود ضمن 15 كم، وإن لم يوجد يتم الإرسال للجميع (broadcast_all)
      final matchingWithin15 = _nearbyProviders.where((p) {
        final lat = (p['latitude'] as num?)?.toDouble() ??
            (p['workshop_latitude'] as num?)?.toDouble();
        final lng = (p['longitude'] as num?)?.toDouble() ??
            (p['workshop_longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return false;
        final km = Geolocator.distanceBetween(
              _pickupLatLng.latitude,
              _pickupLatLng.longitude,
              lat,
              lng,
            ) /
            1000.0;
        return km <= 15.0;
      }).toList();

      final bool broadcastAll = matchingWithin15.isEmpty;

      // بدون تسعيرة عداد — المزود يرسل عرض سعر بعد القبول
      final inserted = await _db
          .from('mechanic_requests')
          .insert({
            'user_id': widget.profile.id,
            'service_type': useWinch ? 'winch' : 'mechanic',
            'car_details': carText,
            'phone': widget.profile.phone,
            'description': _selectedProblem,
            'status': 'pending',
            'progress_step': 'pending',
            'total_amount': 0.0,
            'quoted_price': 0.0,
            'payment_status': 'unpaid',
            'latitude': _pickupLatLng.latitude,
            'longitude': _pickupLatLng.longitude,
            'pickup_latitude': _pickupLatLng.latitude,
            'pickup_longitude': _pickupLatLng.longitude,
            'dropoff_latitude': useWinch ? _dropoffLatLng.latitude : null,
            'dropoff_longitude': useWinch ? _dropoffLatLng.longitude : null,
            'dropoff_address': useWinch ? _dropoffAddress : _pickupAddress,
            'broadcast_all': broadcastAll,
          })
          .select()
          .single();

      final reqId = inserted['id'] as String;

      // إرسال إشعار فوري لأقرب مزودين أو للكل
      final targets = broadcastAll ? _nearbyProviders : matchingWithin15;
      for (final p in targets.take(15)) {
        final pid = p['id'] as String?;
        if (pid != null && pid != widget.profile.id) {
          try {
            await _notifs.sendNotification(
              targetUserId: pid,
              title: useWinch
                  ? 'طلب ونش طوارئ جديد 🚨'
                  : 'طلب ميكانيكي طوارئ جديد 🚨',
              body:
                  'عطل: $_selectedProblem · $carText — افتح الطلب وأرسل عرض السعر للزبون.',
              type: 'new_emergency',
              referenceId: reqId,
            );
          } catch (_) {}
        }
      }

      if (mounted) {
        _bindActiveRequestStream(reqId, restartTimer: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(_loc.tr('تعذر إرسال الطلب: $e', 'Request failed: $e')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _acceptQuote(DbMechanicRequest req) async {
    setState(() => _handlingQuote = true);
    try {
      final finalPrice =
          req.quotedPrice > 0 ? req.quotedPrice : req.totalAmount;
      await _db.from('mechanic_requests').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
        'total_amount': finalPrice,
      }).eq('id', req.id);

      if (req.mechanicId != null) {
        await _notifs.sendNotification(
          targetUserId: req.mechanicId!,
          title: 'وافق العميل على عرض السعر ✅',
          body:
              'تم تثبيت السعر (${finalPrice.toStringAsFixed(2)} د.أ) — يرجى الانطلاق فوراً لموقع العميل.',
          type: 'quote_accepted',
          referenceId: req.id,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              _loc.tr(
                'تم قبول العرض! يمكنك متابعة موقع المزود لحظياً على الخريطة ✓',
                'Quote accepted! Track provider live on the map ✓',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _handlingQuote = false);
    }
  }

  Future<void> _rejectQuoteAndSearchNext(DbMechanicRequest req) async {
    setState(() => _handlingQuote = true);
    try {
      await _db.rpc('reject_emergency_quote', params: {
        'p_request_id': req.id,
      });

      // إشعار المزودين الآخرين غير المرفوضين
      final rejectedSet = {
        ...req.rejectedProviderIds,
        if (req.mechanicId != null) req.mechanicId!,
      };
      for (final p in _nearbyProviders) {
        final pid = p['id'] as String?;
        if (pid != null &&
            pid != widget.profile.id &&
            !rejectedSet.contains(pid)) {
          try {
            await _notifs.sendNotification(
              targetUserId: pid,
              title: req.serviceType == 'winch'
                  ? 'طلب ونش طوارئ متاح الآن 🚨'
                  : 'طلب ميكانيكي طوارئ متاح الآن 🚨',
              body:
                  'عطل: ${req.description ?? "-"} · ${req.carDetails} — أرسل عرض سعرك الآن.',
              type: 'new_emergency',
              referenceId: req.id,
            );
          } catch (_) {}
        }
      }

      _startWaitTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.navy,
            content: Text(
              _loc.tr(
                'تم رفض العرض — جاري البحث تلقائياً عن مزود آخر...',
                'Quote declined — searching automatically for another provider...',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _handlingQuote = false);
    }
  }

  Future<void> _cancelPendingRequest(DbMechanicRequest req) async {
    if (req.isInvoiceLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            _loc.tr(
              'ممنوع إلغاء الطلب أو الدفع بعد إصدار الفاتورة',
              'Cancellation is locked after invoice issuance',
            ),
          ),
        ),
      );
      return;
    }
    try {
      await _db
          .from('mechanic_requests')
          .update({'status': 'cancelled', 'progress_step': 'cancelled'})
          .eq('id', req.id);
      _waitTimer?.cancel();
      _stopProviderLiveTracking();
      setState(() {
        _activeRequest = null;
        _activeRequestId = null;
        _timedOutNoProvider = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('$e')),
        );
      }
    }
  }

  String _formatCountdown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _loc.langCode,
      builder: (_, __, ___) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            EnvConfig.winchEnabled,
            EnvConfig.paymentsEnabled,
          ]),
          builder: (_, __) {
            final showWinch = EnvConfig.winchEnabled.value;
            if (!showWinch && _serviceType == 'winch') {
              _serviceType = 'mechanic';
            }
            final req = _activeRequest;
            final isTrackingLive = req != null &&
                (req.status == 'accepted' || req.status == 'quote_sent');

            // حساب المسافة والوقت المتوقع للمزود المتجه نحو العميل
            double? liveKm;
            int? etaMins;
            if (_providerLivePos != null && isTrackingLive) {
              final meters = Geolocator.distanceBetween(
                _providerLivePos!.latitude,
                _providerLivePos!.longitude,
                _pickupLatLng.latitude,
                _pickupLatLng.longitude,
              );
              liveKm = double.parse((meters / 1000.0).toStringAsFixed(1));
              etaMins = math.max(1, (liveKm * 2.2).round());
            }

            return Scaffold(
              backgroundColor: AppColors.background,
              body: Stack(
                children: [
                  // 1) الخريطة الحديثة المصممة بنمط Petra Ride / Ghiyarak (CartoDB Voyager HD)
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _pickupLatLng,
                        initialZoom: 14.2,
                        maxZoom: 18.5,
                        onTap: (_, latLng) => _onMapTap(latLng),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'com.autoparts.ghiyarak',
                          retinaMode: true,
                        ),
                        // خط مسار حي بين المزود والعميل عند قبول الطلب
                        if (isTrackingLive && _providerLivePos != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: [_providerLivePos!, _pickupLatLng],
                                color: AppColors.navy,
                                strokeWidth: 5.0,
                                borderColor: Colors.white,
                                borderStrokeWidth: 2.0,
                              ),
                            ],
                          )
                        else if (_serviceType == 'winch' && showWinch)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: [_pickupLatLng, _dropoffLatLng],
                                color: AppColors.orange.withValues(alpha: 0.8),
                                strokeWidth: 4.0,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            // دبوس موقع العميل الحديث
                            Marker(
                              point: _pickupLatLng,
                              width: 56,
                              height: 56,
                              child: _CustomerPulsePin(
                                label: _loc.tr('موقعي', 'Me'),
                              ),
                            ),
                            // دبوس الوجهة للونش
                            if (_serviceType == 'winch' &&
                                showWinch &&
                                !isTrackingLive)
                              Marker(
                                point: _dropoffLatLng,
                                width: 46,
                                height: 46,
                                child: const Icon(
                                  Icons.flag_circle,
                                  color: AppColors.navy,
                                  size: 38,
                                ),
                              ),
                            // إظهار المزود المعين وهو يتحرك حياً نحو العميل
                            if (isTrackingLive && _providerLivePos != null)
                              Marker(
                                point: _providerLivePos!,
                                width: 64,
                                height: 64,
                                child: Transform.rotate(
                                  angle: _providerHeadingRad,
                                  child: CustomPaint(
                                    painter: _GhiyarakVehicle2DPainter(
                                      isWinch: req.serviceType == 'winch',
                                      highlighted: true,
                                    ),
                                  ),
                                ),
                              )
                            else
                              // إظهار السيارات الـ 2D القريبة المتاحة حول العميل
                              ..._nearbyProviders.map((p) {
                                final lat = (p['latitude'] as num?)?.toDouble() ??
                                    (p['workshop_latitude'] as num?)?.toDouble();
                                final lng = (p['longitude'] as num?)?.toDouble() ??
                                    (p['workshop_longitude'] as num?)?.toDouble();
                                if (lat == null || lng == null) {
                                  return const Marker(
                                    point: LatLng(0, 0),
                                    width: 0,
                                    height: 0,
                                    child: SizedBox.shrink(),
                                  );
                                }
                                final pos = LatLng(lat, lng);
                                final heading = _bearingRad(pos, _pickupLatLng);
                                return Marker(
                                  point: pos,
                                  width: 52,
                                  height: 52,
                                  child: Transform.rotate(
                                    angle: heading,
                                    child: CustomPaint(
                                      painter: _GhiyarakVehicle2DPainter(
                                        isWinch: _serviceType == 'winch',
                                        highlighted: false,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 2) الشريط العلوي العائم بنمط عصري
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 14,
                    right: 14,
                    child: Row(
                      children: [
                        if (Navigator.canPop(context))
                          _floatingCircleBtn(
                            icon: Icons.arrow_back_ios_new_rounded,
                            onTap: () => Navigator.pop(context),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: isTrackingLive
                                        ? AppColors.success
                                        : AppColors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isTrackingLive && liveKm != null
                                        ? _loc.tr(
                                            'المزود على بُعد $liveKm كم (~$etaMins د)',
                                            'Provider $liveKm km away (~$etaMins min)',
                                          )
                                        : _loc.tr(
                                            'طوارئ غيارك المباشرة · ${_nearbyProviders.length} متاح',
                                            'Ghiyarak Roadside · ${_nearbyProviders.length} online',
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _floatingCircleBtn(
                          icon: _loadingGps
                              ? Icons.hourglass_top
                              : Icons.my_location_rounded,
                          onTap: _detectMyLocation,
                        ),
                      ],
                    ),
                  ),

                  // 3) اللوحة السفلية الذكية حسب حالة الطلب
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.56,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 24,
                            offset: const Offset(0, -6),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          18,
                          12,
                          18,
                          MediaQuery.of(context).padding.bottom + 18,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 42,
                                height: 4.5,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            if (_timedOutNoProvider)
                              _buildTimeoutCard()
                            else if (req != null && req.status == 'pending')
                              _buildWaitingRadarCard(req)
                            else if (req != null && req.status == 'quote_sent')
                              _buildQuoteApprovalCard(req)
                            else if (req != null &&
                                (req.status == 'accepted' ||
                                    (req.status == 'completed' &&
                                        req.totalAmount > 0 &&
                                        req.paymentStatus != 'paid')))
                              _buildLiveTrackingCard(req, liveKm, etaMins)
                            else
                              _buildRequestForm(showWinch),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _floatingCircleBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, color: AppColors.navy, size: 20),
        ),
      ),
    );
  }

  /// نموذج إنشاء طلب جديد (بدون تسعيرة عداد)
  Widget _buildRequestForm(bool showWinch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWinch)
          Row(
            children: [
              Expanded(
                child: _serviceTypeBtn(
                  code: 'mechanic',
                  icon: Icons.build_circle_outlined,
                  label: _loc.tr('ميكانيكي طوارئ', 'Roadside Mechanic'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _serviceTypeBtn(
                  code: 'winch',
                  icon: Icons.local_shipping_outlined,
                  label: _loc.tr('ونش سحب', 'Towing Winch'),
                ),
              ),
            ],
          ),
        if (showWinch) const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.navy.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              const Icon(Icons.request_quote_rounded,
                  color: AppColors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loc.tr(
                    'التسعير بنظام عرض السعر: بعد إرسال الطلب يصلك عرض سعر مباشر من المزود ولك حرية القبول أو الرفض.',
                    'Quote-based pricing: Provider sends a direct price quote after accepting — you can accept or decline.',
                  ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _loc.tr('نوع العطل', 'Issue Type'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _problems.map((p) {
            final selected = _selectedProblem == p.key;
            return ChoiceChip(
              avatar: Icon(
                p.icon,
                size: 16,
                color: selected ? Colors.white : AppColors.navy,
              ),
              label: Text(_loc.tr(p.ar, p.en)),
              selected: selected,
              selectedColor: AppColors.navy,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              onSelected: (_) => setState(() => _selectedProblem = p.key),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _carCtrl,
          decoration: InputDecoration(
            labelText: _loc.tr('نوع وموديل السيارة', 'Vehicle Make & Model'),
            prefixIcon: const Icon(Icons.directions_car, color: AppColors.navy),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _pickingDropoff = false),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: !_pickingDropoff
                        ? AppColors.orangeLight
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: !_pickingDropoff
                          ? AppColors.orange
                          : AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loc.tr('موقعك الحالي', 'Pickup Location'),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.orange,
                        ),
                      ),
                      Text(
                        _pickupAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_serviceType == 'winch' && showWinch) ...[
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _pickingDropoff = true),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _pickingDropoff
                          ? AppColors.orangeLight
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _pickingDropoff
                            ? AppColors.orange
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loc.tr('وجهة السحب (اضغط عالخريطة)', 'Dropoff Point'),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                        ),
                        Text(
                          _dropoffAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _submitting ? null : _submitEmergencyRequest,
            icon: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : const Icon(Icons.radar_rounded),
            label: Text(
              _serviceType == 'winch'
                  ? _loc.tr('تأكيد طلب الونش واستلام عرض سعر',
                      'Request Winch & Get Quote')
                  : _loc.tr('تأكيد طلب الميكانيكي واستلام عرض سعر',
                      'Request Mechanic & Get Quote'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _serviceTypeBtn({
    required String code,
    required IconData icon,
    required String label,
  }) {
    final active = _serviceType == code;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() => _serviceType = code);
        _listenAvailableProviders();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? AppColors.navy : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? AppColors.orange : AppColors.navy, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// شريط الانتظار المتحرك يميناً ويساراً (5 دقائق)
  Widget _buildWaitingRadarCard(DbMechanicRequest req) {
    final isWinch = req.serviceType == 'winch';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.radar_rounded, color: AppColors.orange, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isWinch
                        ? _loc.tr('بانتظار ونش طوارئ لتقديم عرض سعر...',
                            'Searching for a tow winch quote...')
                        : _loc.tr('بانتظار ميكانيكي طوارئ لتقديم عرض سعر...',
                            'Searching for a mechanic quote...'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    _loc.tr(
                      'الوقت المتبقي للبحث: ${_formatCountdown(_waitSecondsLeft)}',
                      'Remaining search time: ${_formatCountdown(_waitSecondsLeft)}',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // خط تحميل يتحرك يميناً ويساراً بسلاسة
        AnimatedBuilder(
          animation: _radarSlideCtrl,
          builder: (_, __) {
            return LayoutBuilder(
              builder: (_, c) {
                final w = c.maxWidth;
                final barW = w * 0.34;
                final left = (w - barW) * _radarSlideCtrl.value;
                return Container(
                  height: 8,
                  width: w,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: left,
                        child: Container(
                          width: barW,
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.navy, AppColors.orange],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          req.rejectedProviderIds.isNotEmpty
              ? _loc.tr(
                  'جاري تحويل طلبك لأقرب مزود متاح آخر (${req.rejectedProviderIds.length} تم استبعادهم)...',
                  'Forwarding request to next available provider...',
                )
              : _loc.tr(
                  'فور استلام عرض السعر ستتمكن من قبوله أو رفضه مباشرة.',
                  'You can accept or decline as soon as a quote arrives.',
                ),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () => _cancelPendingRequest(req),
          icon: const Icon(Icons.close),
          label: Text(_loc.tr('إلغاء البحث', 'Cancel Search')),
        ),
      ],
    );
  }

  /// بطاقة انتهاء الـ 5 دقائق بدون قبول + زر إعادة الطلب
  Widget _buildTimeoutCard() {
    final isWinch = _serviceType == 'winch';
    return Column(
      children: [
        const Icon(Icons.sentiment_dissatisfied_rounded,
            size: 46, color: AppColors.orange),
        const SizedBox(height: 8),
        Text(
          isWinch
              ? _loc.tr('لا يوجد ونش متاح حالياً', 'No tow winch available now')
              : _loc.tr(
                  'لا يوجد ميكانيكي متاح حالياً', 'No mechanic available now'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _loc.tr(
            'مضت 5 دقائق دون استجابة. يمكنك إعادة الطلب الآن وسيُرسل لجميع المزودين المتاحين.',
            '5 minutes passed without response. Tap retry to re-broadcast.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _submitEmergencyRequest,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              _loc.tr('إعادة الطلب', 'Retry Request'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  /// بطاقة عرض السعر القادم من الميكانيكي / الونش (قبول أو رفض + بحث تلقائي)
  Widget _buildQuoteApprovalCard(DbMechanicRequest req) {
    final isWinch = req.serviceType == 'winch';
    final pName = (_assignedProviderInfo?['full_name'] as String?) ??
        (isWinch
            ? _loc.tr('سائق ونش معتمد', 'Certified Winch Driver')
            : _loc.tr('ميكانيكي طوارئ معتمد', 'Certified Mechanic'));
    final pRating =
        (_assignedProviderInfo?['rating_avg'] as num?)?.toDouble() ?? 0.0;
    final price = req.quotedPrice > 0 ? req.quotedPrice : req.totalAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_offer_rounded,
                      color: AppColors.orange, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loc.tr('وصلك عرض سعر جديد!', 'New Price Quote Received!'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${price.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_pin, color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (pRating > 0) ...[
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 16),
                    const SizedBox(width: 3),
                    Text(
                      pRating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
              if ((req.quoteNotes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${_loc.tr("ملاحظة المزود", "Provider Note")}: ${req.quoteNotes}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _handlingQuote ? null : () => _acceptQuote(req),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  _loc.tr('قبول العرض والمتابعة', 'Accept Quote'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _handlingQuote
                    ? null
                    : () => _rejectQuoteAndSearchNext(req),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  _loc.tr('رفض والبحث عن آخر', 'Find Another'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// بطاقة التتبع الحي بعد قبول العرض + دفع الفاتورة بدون إمكانية الإلغاء بعد إصدارها
  Widget _buildLiveTrackingCard(
    DbMechanicRequest req,
    double? liveKm,
    int? etaMins,
  ) {
    final isWinch = req.serviceType == 'winch';
    final pName = (_assignedProviderInfo?['full_name'] as String?) ??
        (isWinch
            ? _loc.tr('سائق الونش', 'Winch Driver')
            : _loc.tr('الميكانيكي', 'Mechanic'));
    final pPhone = (_assignedProviderInfo?['phone'] as String?) ?? '';
    final stepLabel = switch (req.progressStep) {
      'on_the_way' => isWinch
          ? _loc.tr('الونش في طريقه إليك الآن 🚚', 'Tow truck is on the way 🚚')
          : _loc.tr('الميكانيكي في طريقه إليك الآن 🔧',
              'Mechanic is on the way 🔧'),
      'arrived_at_pickup' => _loc.tr(
          'وصل المزود إلى موقعك ✓', 'Provider arrived at your location ✓'),
      'awaiting_payment' => _loc.tr(
          'تم إصدار الفاتورة — يرجى الدفع الآن',
          'Invoice issued — please complete payment'),
      'completed' => _loc.tr('تم إنهاء الخدمة ✓', 'Service completed ✓'),
      _ => _loc.tr('جاري المتابعة...', 'In progress...'),
    };
    final needsPayment =
        req.totalAmount > 0 && req.paymentStatus != 'paid';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isWinch ? Icons.local_shipping : Icons.build_circle,
                color: AppColors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    stepLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (pPhone.isNotEmpty)
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success.withValues(alpha: 0.14),
                ),
                onPressed: () => launchUrl(Uri.parse('tel:$pPhone')),
                icon: const Icon(Icons.call, color: AppColors.success),
              ),
          ],
        ),
        if (liveKm != null && req.progressStep == 'on_the_way') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _loc.tr('المسافة المباشرة: $liveKm كم',
                      'Live Distance: $liveKm km'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  _loc.tr('الوصول خلال ~$etaMins دقيقة', 'ETA ~$etaMins min'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.orange,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (needsPayment && EnvConfig.paymentsEnabled.value) ...[
          if (req.isInvoiceLocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _loc.tr(
                  'ملاحظة: تم إصدار الفاتورة رسمياً ولا يمكن إلغاء الطلب أو الدفع بعد الإصدار.',
                  'Note: Invoice has been issued; cancellation is locked.',
                ),
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                final paid = await Navigator.push<bool>(
                  context,
                  animatedRoute(
                    EmergencyCheckoutScreen(
                      request: req,
                      customerProfile: widget.profile,
                      onPaymentCompleted: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                );
                if (paid == true && mounted) {
                  setState(() {});
                }
              },
              icon: const Icon(Icons.payment_rounded),
              label: Text(
                _loc.tr(
                  'دفع الفاتورة (${req.totalAmount.toStringAsFixed(2)} د.أ)',
                  'Pay Invoice (${req.totalAmount.toStringAsFixed(2)} JOD)',
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// دبوس موقع العميل العصري (نبض دائري)
class _CustomerPulsePin extends StatelessWidget {
  final String label;
  const _CustomerPulsePin({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// رسام سيارة 2D واقعية مطوّرة (منظور علوي احترافي بنمط تطبيقات النقل الحديثة)
class _GhiyarakVehicle2DPainter extends CustomPainter {
  final bool isWinch;
  final bool highlighted;

  _GhiyarakVehicle2DPainter({
    required this.isWinch,
    required this.highlighted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // 1) ظل ناعم تحت السيارة
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: highlighted ? 0.32 : 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, h * 0.54),
          width: w * 0.46,
          height: h * 0.78,
        ),
        const Radius.circular(11),
      ),
      shadowPaint,
    );

    // 2) الإطارات الأربعة
    final wheelPaint = Paint()..color = const Color(0xFF1F242D);
    final wheelW = w * 0.08;
    final wheelH = h * 0.16;
    for (final dy in [h * 0.25, h * 0.73]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx - w * 0.23, dy), width: wheelW, height: wheelH),
          const Radius.circular(2.5),
        ),
        wheelPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx + w * 0.23, dy), width: wheelW, height: wheelH),
          const Radius.circular(2.5),
        ),
        wheelPaint,
      );
    }

    // 3) هيكل السيارة (تدرج فضي/معدني أنيق)
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, h * 0.5),
      width: w * 0.44,
      height: h * 0.78,
    );
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: highlighted
            ? [
                const Color(0xFFB8C4D4),
                const Color(0xFFF3F6FA),
                const Color(0xFF9AA8BC),
              ]
            : [
                const Color(0xFF9BA5B4),
                const Color(0xFFE5EAF0),
                const Color(0xFF8C97A8),
              ],
      ).createShader(bodyRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(11)),
      bodyPaint,
    );

    // إطار خفيف حول الهيكل
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(11)),
      Paint()
        ..color = highlighted ? AppColors.navy : const Color(0xFF5D6878)
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 1.5 : 1.0,
    );

    // 4) مرايا جانبية
    final mirrorPaint = Paint()..color = const Color(0xFFCED6E0);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - w * 0.25, h * 0.34),
          width: w * 0.08,
          height: h * 0.05),
      mirrorPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + w * 0.25, h * 0.34),
          width: w * 0.08,
          height: h * 0.05),
      mirrorPaint,
    );

    if (isWinch) {
      // كابينة الونش الأمامية + السطحة الخلفية + سفتي برتقالي
      final cabinWindshield = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, h * 0.27), width: w * 0.34, height: h * 0.12),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        cabinWindshield,
        Paint()..color = const Color(0xFF1A2538),
      );

      // سطحة السحب الخلفية المخططة
      final bedRect = Rect.fromCenter(
        center: Offset(cx, h * 0.64),
        width: w * 0.38,
        height: h * 0.40,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bedRect, const Radius.circular(4)),
        Paint()..color = const Color(0xFF2B3445),
      );
      final railPaint = Paint()
        ..color = AppColors.orange
        ..strokeWidth = 1.6;
      canvas.drawLine(
        Offset(bedRect.left + 4, bedRect.top + 3),
        Offset(bedRect.left + 4, bedRect.bottom - 3),
        railPaint,
      );
      canvas.drawLine(
        Offset(bedRect.right - 4, bedRect.top + 3),
        Offset(bedRect.right - 4, bedRect.bottom - 3),
        railPaint,
      );

      // شريط ضوء الطوارئ البرتقالي أعلى الكابينة
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, h * 0.39), width: w * 0.26, height: h * 0.055),
          const Radius.circular(3),
        ),
        Paint()..color = AppColors.orange,
      );
    } else {
      // زجاج أمامي بانورامي + سقف + زجاج خلفي لسيارة الميكانيكي
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, h * 0.33), width: w * 0.34, height: h * 0.14),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFF182233),
      );
      // لمعة زجاج أمامي
      canvas.drawLine(
        Offset(cx - w * 0.12, h * 0.30),
        Offset(cx + w * 0.08, h * 0.30),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      // السقف
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, h * 0.53), width: w * 0.30, height: h * 0.22),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFE7ECF2),
      );
      // شارة غيارك البرتقالية على السقف
      canvas.drawCircle(
        Offset(cx, h * 0.53),
        w * 0.055,
        Paint()..color = AppColors.orange,
      );
      // زجاج خلفي
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, h * 0.72), width: w * 0.31, height: h * 0.10),
          const Radius.circular(5),
        ),
        Paint()..color = const Color(0xFF1E2A3D),
      );
    }

    // 5) أضواء أمامية LED بيضاء
    final headlightPaint = Paint()..color = const Color(0xFFFFF8D6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx - w * 0.14, h * 0.13),
            width: w * 0.10,
            height: h * 0.035),
        const Radius.circular(2),
      ),
      headlightPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx + w * 0.14, h * 0.13),
            width: w * 0.10,
            height: h * 0.035),
        const Radius.circular(2),
      ),
      headlightPaint,
    );

    // 6) أضواء خلفية حمراء
    final tailPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx - w * 0.13, h * 0.87),
            width: w * 0.11,
            height: h * 0.03),
        const Radius.circular(2),
      ),
      tailPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx + w * 0.13, h * 0.87),
            width: w * 0.11,
            height: h * 0.03),
        const Radius.circular(2),
      ),
      tailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GhiyarakVehicle2DPainter oldDelegate) =>
      oldDelegate.isWinch != isWinch || oldDelegate.highlighted != highlighted;
}