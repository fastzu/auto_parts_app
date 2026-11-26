import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/location_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
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
  final _mapController = MapController();
  final _carCtrl = TextEditingController();

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _submitting = false;
  bool _actingOnQuote = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';
  double _distanceKm = 5.0;

  // حالة المزود والسيارة المتحركة والمسار
  String? _loadedProviderId;
  Map<String, dynamic>? _providerInfo;
  StreamSubscription<List<Map<String, dynamic>>>? _providerLocationSub;

  LatLng? _lastRawProviderLatLng;
  LatLng? _providerLatLng;
  LatLng? _animFromLatLng;
  LatLng? _animToLatLng;
  double _providerBearingRad = 0.0;
  late final AnimationController _carMoveCtrl;

  List<LatLng> _routePoints = [];
  LatLng? _lastRouteFrom;
  LatLng? _lastRouteTo;
  bool _fetchingRoute = false;

  final Set<String> _completedIds = {};

  final List<String> _problems = const [
    'بطارية',
    'إطار',
    'محرك',
    'وقود',
    'حادث',
  ];

  bool _isValidCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    return lat.abs() <= 85.0 && lng.abs() <= 180.0;
  }

  bool _isSafePolyline(List<LatLng> pts) {
    if (pts.length < 2) return false;
    for (final p in pts) {
      if (!_isValidCoord(p.latitude, p.longitude)) return false;
    }
    final distMeters = Geolocator.distanceBetween(
      pts.first.latitude,
      pts.first.longitude,
      pts.last.latitude,
      pts.last.longitude,
    );
    return distMeters.isFinite && distMeters <= 500000;
  }

  @override
  void initState() {
    super.initState();
    _carMoveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() {
        if (!mounted || _animFromLatLng == null || _animToLatLng == null) return;
        final t = Curves.easeInOut.transform(_carMoveCtrl.value);
        setState(() {
          _providerLatLng = LatLng(
            _animFromLatLng!.latitude +
                (_animToLatLng!.latitude - _animFromLatLng!.latitude) * t,
            _animFromLatLng!.longitude +
                (_animToLatLng!.longitude - _animFromLatLng!.longitude) * t,
          );
        });
      });
    _detectMyLocation();
  }

  @override
  void dispose() {
    _providerLocationSub?.cancel();
    _carMoveCtrl.dispose();
    _carCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectMyLocation() async {
    setState(() => _loadingGps = true);
    try {
      final res = await _locationService.getCurrentLocation();
      if (!mounted) return;
      if (!_isValidCoord(res.coordinates.latitude, res.coordinates.longitude)) {
        setState(() => _loadingGps = false);
        return;
      }
      final dist =
          _locationService.calculateDistanceKm(res.coordinates, _dropoffLatLng);
      setState(() {
        _pickupLatLng = res.coordinates;
        _pickupAddress = res.address;
        _distanceKm = dist < 0.5 ? 1.0 : double.parse(dist.toStringAsFixed(2));
        _loadingGps = false;
      });
      _mapController.move(_pickupLatLng, 15.5);
    } catch (_) {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _onMapTap(LatLng latLng, bool hasActiveReq) async {
    if (hasActiveReq) return;
    if (!_isValidCoord(latLng.latitude, latLng.longitude)) return;
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
  }

  void _syncProviderData(String? providerId, Map<String, dynamic> req) {
    if (providerId == null || providerId.isEmpty) {
      if (_loadedProviderId != null) {
        _loadedProviderId = null;
        _lastRawProviderLatLng = null;
        _providerLocationSub?.cancel();
        _providerLocationSub = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _providerInfo = null;
            _providerLatLng = null;
            _routePoints = [];
            _lastRouteFrom = null;
            _lastRouteTo = null;
          });
        });
      }
      return;
    }

    final reqLat = (req['latitude'] as num?)?.toDouble();
    final reqLng = (req['longitude'] as num?)?.toDouble();
    if (_isValidCoord(reqLat, reqLng)) {
      _updateProviderPosition(LatLng(reqLat!, reqLng!), req);
    }

    if (_loadedProviderId == providerId) return;
    _loadedProviderId = providerId;
    _providerLocationSub?.cancel();

    _providerLocationSub = _db
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', providerId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      setState(() => _providerInfo = row);
      final lat = (row['latitude'] as num?)?.toDouble() ??
          (row['workshop_latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble() ??
          (row['workshop_longitude'] as num?)?.toDouble();
      if (_isValidCoord(lat, lng)) {
        _updateProviderPosition(LatLng(lat!, lng!), req);
      }
    });
  }

  void _updateProviderPosition(LatLng nextPos, Map<String, dynamic> req) {
    if (!_isValidCoord(nextPos.latitude, nextPos.longitude)) return;

    // مقارنة مع آخر إحداثي خام وصل من القاعدة لمنع إعادة التشغيل اللانهائية
    final lastRaw = _lastRawProviderLatLng;
    if (lastRaw != null) {
      final rawDelta = Geolocator.distanceBetween(
        lastRaw.latitude,
        lastRaw.longitude,
        nextPos.latitude,
        nextPos.longitude,
      );
      if (rawDelta < 2.0) {
        _maybeFetchRoute(nextPos, req);
        return;
      }
    }
    _lastRawProviderLatLng = nextPos;

    final startPos = _providerLatLng;
    if (startPos != null) {
      final bearing = _computeBearingRad(startPos, nextPos);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _animFromLatLng = startPos;
        _animToLatLng = nextPos;
        _providerBearingRad = bearing;
        _carMoveCtrl.forward(from: 0.0);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _providerLatLng = nextPos);
      });
    }
    _maybeFetchRoute(nextPos, req);
  }

  double _computeBearingRad(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final dLng = (to.longitude - from.longitude) * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final angle = math.atan2(y, x);
    return angle.isFinite ? angle : 0.0;
  }

  LatLng _routeTargetFor(Map<String, dynamic> req) {
    final step = ((req['progress_step'] as String?) ?? '').toLowerCase();
    final dropLat = (req['dropoff_latitude'] as num?)?.toDouble();
    final dropLng = (req['dropoff_longitude'] as num?)?.toDouble();
    if (step == 'towing' && _isValidCoord(dropLat, dropLng)) {
      return LatLng(dropLat!, dropLng!);
    }
    final pickLat = (req['pickup_latitude'] as num?)?.toDouble();
    final pickLng = (req['pickup_longitude'] as num?)?.toDouble();
    if (_isValidCoord(pickLat, pickLng)) {
      return LatLng(pickLat!, pickLng!);
    }
    return _pickupLatLng;
  }

  Future<void> _maybeFetchRoute(LatLng from, Map<String, dynamic> req) async {
    final status = ((req['status'] as String?) ?? '').toLowerCase();
    if (status != 'accepted' && status != 'in_progress') return;
    if (_fetchingRoute) return;

    final to = _routeTargetFor(req);
    if (!_isValidCoord(from.latitude, from.longitude) ||
        !_isValidCoord(to.latitude, to.longitude)) {
      return;
    }

    final spanMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    if (!spanMeters.isFinite || spanMeters < 5 || spanMeters > 500000) return;

    if (_lastRouteFrom != null &&
        _lastRouteTo != null &&
        _routePoints.isNotEmpty) {
      final dFrom = Geolocator.distanceBetween(
        _lastRouteFrom!.latitude,
        _lastRouteFrom!.longitude,
        from.latitude,
        from.longitude,
      );
      final dTo = Geolocator.distanceBetween(
        _lastRouteTo!.latitude,
        _lastRouteTo!.longitude,
        to.latitude,
        to.longitude,
      );
      if (dFrom < 25 && dTo < 25) return;
    }

    _fetchingRoute = true;
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = decoded['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final coords =
              routes.first['geometry']['coordinates'] as List<dynamic>;
          final pts = coords
              .map(
                (c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ),
              )
              .where((p) => _isValidCoord(p.latitude, p.longitude))
              .toList();
          if (mounted && _isSafePolyline(pts)) {
            setState(() {
              _routePoints = pts;
              _lastRouteFrom = from;
              _lastRouteTo = to;
            });
            return;
          }
        }
      }
      if (mounted && _isSafePolyline([from, to])) {
        setState(() {
          _routePoints = [from, to];
          _lastRouteFrom = from;
          _lastRouteTo = to;
        });
      }
    } catch (_) {
      if (mounted && _routePoints.isEmpty && _isSafePolyline([from, to])) {
        setState(() => _routePoints = [from, to]);
      }
    } finally {
      _fetchingRoute = false;
    }
  }

  Future<void> _submitOrder() async {
    FocusScope.of(context).unfocus();
    final carText = _carCtrl.text.trim();
    if (carText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال نوع وموديل السيارة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final useWinch = EnvConfig.winchEnabled.value && _serviceType == 'winch';
    setState(() => _submitting = true);
    try {
      await _db
          .from('mechanic_requests')
          .update({'status': 'cancelled', 'progress_step': 'cancelled'})
          .eq('user_id', widget.profile.id)
          .eq('status', 'pending');

      await _db.from('mechanic_requests').insert({
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
        'total_amount': 0.0,
        'payment_status': 'unpaid',
        'status': 'pending',
        'progress_step': 'pending',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الطلب: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _acceptQuote(Map<String, dynamic> req) async {
    if (_actingOnQuote) return;
    setState(() => _actingOnQuote = true);
    try {
      final id = req['id'] as String;
      final providerId = req['mechanic_id'] as String?;
      await _db.from('mechanic_requests').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
        'payment_status': 'unpaid',
      }).eq('id', id);

      if (providerId != null && providerId.isNotEmpty) {
        await _notifs.sendNotification(
          targetUserId: providerId,
          title: 'وافق العميل على عرض السعر',
          body: 'يمكنك الانطلاق الآن نحو موقع العميل.',
          type: 'quote_accepted',
          referenceId: id,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر قبول العرض: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actingOnQuote = false);
    }
  }

  Future<void> _rejectQuote(Map<String, dynamic> req) async {
    if (_actingOnQuote) return;
    setState(() => _actingOnQuote = true);
    try {
      final id = req['id'] as String;
      final providerId = req['mechanic_id'] as String?;
      await _db.from('mechanic_requests').update({
        'status': 'pending',
        'progress_step': 'pending',
        'mechanic_id': null,
        'total_amount': 0.0,
        'payment_status': 'unpaid',
        'latitude': null,
        'longitude': null,
      }).eq('id', id);

      if (providerId != null && providerId.isNotEmpty) {
        await _notifs.sendNotification(
          targetUserId: providerId,
          title: 'تم رفض عرض السعر',
          body: 'رفض العميل العرض وعاد الطلب لقائمة الانتظار.',
          type: 'quote_rejected',
          referenceId: id,
        );
      }
      if (mounted) {
        setState(() {
          _lastRawProviderLatLng = null;
          _providerLatLng = null;
          _routePoints = [];
          _lastRouteFrom = null;
          _lastRouteTo = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر رفض العرض: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actingOnQuote = false);
    }
  }

  Future<void> _cancelRequest(String id) async {
    try {
      await _db.from('mechanic_requests').update({
        'status': 'cancelled',
        'progress_step': 'cancelled',
      }).eq('id', id);
      if (mounted) {
        setState(() {
          _lastRawProviderLatLng = null;
          _providerLatLng = null;
          _routePoints = [];
          _lastRouteFrom = null;
          _lastRouteTo = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إلغاء الطلب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _stageText(String status, String step, bool isWinch) {
    if (status == 'awaiting_payment' || step == 'awaiting_payment') {
      return 'تم إصدار الفاتورة — يرجى الدفع الآن';
    }
    if (step == 'towing') return 'جاري سحب السيارة إلى الوجهة';
    if (step == 'repairing') return 'الميكانيكي يقوم بالإصلاح الآن';
    if (step == 'arrived_at_pickup') {
      return isWinch ? 'وصل الونش إلى موقعك' : 'وصل الميكانيكي إلى موقعك';
    }
    return isWinch ? 'الونش في طريقه إليك الآن' : 'الميكانيكي في طريقه إليك الآن';
  }

  double _stageProgress(String status, String step) {
    if (status == 'awaiting_payment' || step == 'awaiting_payment') return 0.92;
    if (step == 'repairing' || step == 'towing') return 0.72;
    if (step == 'arrived_at_pickup') return 0.52;
    if (step == 'on_the_way' || status == 'accepted' || status == 'in_progress') {
      return 0.30;
    }
    return 0.12;
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
        if (!showWinch && _serviceType == 'winch') {
          _serviceType = 'mechanic';
          _pickingDropoff = false;
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('mechanic_requests')
              .stream(primaryKey: ['id'])
              .eq('user_id', widget.profile.id)
              .order('created_at', ascending: false)
              .limit(5),
          builder: (context, snap) {
            Map<String, dynamic>? req;
            final rows = snap.data ?? const [];
            if (rows.isNotEmpty) {
              final latest = rows.first;
              final id = latest['id'] as String? ?? '';
              final st = ((latest['status'] as String?) ?? '').toLowerCase();
              final pay = ((latest['payment_status'] as String?) ?? 'unpaid')
                  .toLowerCase();
              final amt = ((latest['total_amount'] as num?) ?? 0).toDouble();
              final isDone = _completedIds.contains(id) ||
                  st == 'cancelled' ||
                  (st == 'completed' && (pay == 'paid' || amt <= 0));
              if (!isDone) {
                req = latest;
              }
            }

            final status = ((req?['status'] as String?) ?? '').toLowerCase();
            final step = ((req?['progress_step'] as String?) ?? '').toLowerCase();
            final payStatus =
                ((req?['payment_status'] as String?) ?? 'unpaid').toLowerCase();
            final amount = ((req?['total_amount'] as num?) ?? 0).toDouble();
            final providerId = req?['mechanic_id'] as String?;

            if (req != null) {
              _syncProviderData(providerId, req);
            } else if (_loadedProviderId != null) {
              _syncProviderData(null, const {});
            }

            final isSearching = req != null && status == 'pending';
            final isQuoteReceived =
                req != null && (status == 'quoted' || step == 'quote_sent');
            final isAwaitingPayment = req != null &&
                (status == 'awaiting_payment' ||
                    step == 'awaiting_payment' ||
                    payStatus == 'invoiced' ||
                    (status == 'completed' && amount > 0 && payStatus != 'paid'));
            final isInProgress = req != null &&
                !isSearching &&
                !isQuoteReceived &&
                !isAwaitingPayment;

            final pickLat = (req?['pickup_latitude'] as num?)?.toDouble();
            final pickLng = (req?['pickup_longitude'] as num?)?.toDouble();
            final activePickup = _isValidCoord(pickLat, pickLng)
                ? LatLng(pickLat!, pickLng!)
                : _pickupLatLng;

            final dropLat = (req?['dropoff_latitude'] as num?)?.toDouble();
            final dropLng = (req?['dropoff_longitude'] as num?)?.toDouble();
            final activeDropoff = _isValidCoord(dropLat, dropLng)
                ? LatLng(dropLat!, dropLng!)
                : _dropoffLatLng;

            final isWinchActive = req != null
                ? req['service_type'] == 'winch'
                : (showWinch && _serviceType == 'winch');

            double? providerDistKm;
            int? providerEtaMin;
            if ((isInProgress || isQuoteReceived) &&
                _providerLatLng != null &&
                _isValidCoord(
                  _providerLatLng!.latitude,
                  _providerLatLng!.longitude,
                )) {
              providerDistKm = Geolocator.distanceBetween(
                    _providerLatLng!.latitude,
                    _providerLatLng!.longitude,
                    activePickup.latitude,
                    activePickup.longitude,
                  ) /
                  1000.0;
              providerEtaMin = (providerDistKm * 2.2).round().clamp(1, 60);
            }

            final showRouteLine =
                isInProgress && _isSafePolyline(_routePoints);
            final showWinchPreviewLine = req == null &&
                isWinchActive &&
                _isSafePolyline([_pickupLatLng, _dropoffLatLng]);

            return Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: activePickup,
                      initialZoom: 15.5,
                      minZoom: 3.0,
                      maxZoom: 18.0,
                      cameraConstraint: CameraConstraint.contain(
                        bounds: LatLngBounds(
                          const LatLng(-85.0, -180.0),
                          const LatLng(85.0, 180.0),
                        ),
                      ),
                      onTap: (_, latLng) => _onMapTap(latLng, req != null),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.google.com/vt/lyrs=m&hl=ar&x={x}&y={y}&z={z}',
                        subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                        userAgentPackageName: 'com.ghayarakjo.app',
                        maxNativeZoom: 18,
                      ),
                      if (showRouteLine)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              color: AppColors.navy,
                              strokeWidth: 6.0,
                            ),
                            Polyline(
                              points: _routePoints,
                              color: AppColors.orange,
                              strokeWidth: 3.5,
                            ),
                          ],
                        )
                      else if (showWinchPreviewLine)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [_pickupLatLng, _dropoffLatLng],
                              color: AppColors.orange,
                              strokeWidth: 4.0,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: activePickup,
                            width: 48,
                            height: 48,
                            child: const PulsingPin(color: AppColors.orange),
                          ),
                          if (isWinchActive)
                            Marker(
                              point: activeDropoff,
                              width: 38,
                              height: 38,
                              child: const Icon(
                                Icons.flag,
                                color: AppColors.navy,
                                size: 32,
                              ),
                            ),
                          if ((isInProgress || isQuoteReceived) &&
                              _providerLatLng != null &&
                              _isValidCoord(
                                _providerLatLng!.latitude,
                                _providerLatLng!.longitude,
                              ))
                            Marker(
                              point: _providerLatLng!,
                              width: 36,
                              height: 46,
                              child: Transform.rotate(
                                angle: _providerBearingRad,
                                child: _Minimal2DCarMarker(
                                  isWinch: req['service_type'] == 'winch',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // الشريط العلوي وزر تحديد الموقع
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: IconButton(
                          onPressed: _detectMyLocation,
                          icon: _loadingGps
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.navy,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location,
                                  color: AppColors.navy,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: isInProgress
                                      ? AppColors.success
                                      : AppColors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  providerDistKm != null
                                      ? 'المزود على بُعد ${providerDistKm.toStringAsFixed(1)} كم (~$providerEtaMin د)'
                                      : 'طوارئ غيارك المباشرة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // اللوحة السفلية حسب حالة الطلب
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height *
                          (req == null ? 0.56 : 0.42),
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(26),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 16,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          if (req == null)
                            _buildNewRequestForm(showWinch, isWinchActive)
                          else if (isSearching)
                            _buildSearchingSheet(req)
                          else if (isQuoteReceived)
                            _buildQuoteSheet(req, amount)
                          else if (isAwaitingPayment)
                            _buildInvoiceSheet(req, amount)
                          else
                            _buildActiveTripSheet(
                              req,
                              status,
                              step,
                              isWinchActive,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNewRequestForm(bool showWinch, bool isWinch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                }),
                _segTab('ميكانيكي طوارئ', !isWinch, () {
                  setState(() {
                    _serviceType = 'mechanic';
                    _pickingDropoff = false;
                  });
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (isWinch) ...[
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('نقطة الالتقاط')),
                  selected: !_pickingDropoff,
                  selectedColor: AppColors.navy,
                  labelStyle: TextStyle(
                    color: !_pickingDropoff
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _pickingDropoff = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('الوجهة')),
                  selected: _pickingDropoff,
                  selectedColor: AppColors.orange,
                  labelStyle: TextStyle(
                    color: _pickingDropoff
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _pickingDropoff = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            const Icon(Icons.my_location, size: 16, color: AppColors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _pickupAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (isWinch)
              Text(
                '${_distanceKm.toStringAsFixed(1)} كم',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _carCtrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'نوع وموديل السيارة',
            hintText: 'مثال: تويوتا كامري 2022',
            prefixIcon: const Icon(Icons.directions_car_outlined),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _problems.map((problem) {
            final selected = _selectedProblem == problem;
            return GestureDetector(
              onTap: () => setState(() => _selectedProblem = problem),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppColors.orangeLight : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? AppColors.orange : AppColors.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  problem,
                  style: TextStyle(
                    color: selected ? AppColors.orange : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _submitting ? null : _submitOrder,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.3,
                    ),
                  )
                : Text(
                    isWinch ? 'طلب ونش الآن' : 'طلب ميكانيكي طوارئ الآن',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchingSheet(Map<String, dynamic> req) {
    final isWinch = req['service_type'] == 'winch';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isWinch
                    ? 'جاري البحث عن أقرب ونش سحب...'
                    : 'جاري البحث عن أقرب ميكانيكي طوارئ...',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${req['car_details'] ?? ""} · ${req['description'] ?? ""}',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              const _HorizontalPingPongLine(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _cancelRequest(req['id'] as String),
            icon: const Icon(Icons.close, size: 18),
            label: const Text(
              'إلغاء الطلب',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteSheet(Map<String, dynamic> req, double amount) {
    final providerName = (_providerInfo?['full_name'] as String?) ??
        (_providerInfo?['username'] as String?) ??
        'مزود الخدمة';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_offer, color: AppColors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'وصلك عرض سعر جديد!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${amount.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_pin, color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        providerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 17),
                      SizedBox(width: 4),
                      Text(
                        '5.0',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _actingOnQuote ? null : () => _acceptQuote(req),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'قبول العرض والمتابعة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _actingOnQuote ? null : () => _rejectQuote(req),
                child: const Text(
                  'رفض',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveTripSheet(
    Map<String, dynamic> req,
    String status,
    String step,
    bool isWinch,
  ) {
    final providerName = (_providerInfo?['full_name'] as String?) ??
        (_providerInfo?['username'] as String?) ??
        'مزود الخدمة';
    final providerPhone = (_providerInfo?['phone'] as String?) ?? '';
    final stageText = _stageText(status, step, isWinch);
    final progress = _stageProgress(status, step);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isWinch ? Icons.local_shipping : Icons.build,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    providerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                  Text(
                    stageText,
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (providerPhone.isNotEmpty)
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success.withValues(alpha: 0.14),
                ),
                onPressed: () => launchUrl(Uri.parse('tel:$providerPhone')),
                icon: const Icon(Icons.phone, color: AppColors.success),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: Colors.grey.shade200,
            color: AppColors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceSheet(Map<String, dynamic> req, double amount) {
    final providerName = (_providerInfo?['full_name'] as String?) ??
        (_providerInfo?['username'] as String?) ??
        'مزود الخدمة';
    final providerPhone = (_providerInfo?['phone'] as String?) ?? '';
    final isWinch = req['service_type'] == 'winch';
    final reqId = req['id'] as String;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isWinch ? Icons.local_shipping : Icons.build,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    providerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                  const Text(
                    'تم إصدار الفاتورة — يرجى الدفع الآن',
                    style: TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (providerPhone.isNotEmpty)
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success.withValues(alpha: 0.14),
                ),
                onPressed: () => launchUrl(Uri.parse('tel:$providerPhone')),
                icon: const Icon(Icons.phone, color: AppColors.success),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final paid = await Navigator.push<bool>(
                context,
                animatedRoute(
                  EmergencyCheckoutScreen(
                    request: DbMechanicRequest.fromMap(req),
                    customerProfile: widget.profile,
                    onPaymentCompleted: () {},
                  ),
                ),
              );
              if (paid == true && mounted) {
                setState(() {
                  _completedIds.add(reqId);
                  _lastRawProviderLatLng = null;
                  _providerLatLng = null;
                  _routePoints = [];
                  _lastRouteFrom = null;
                  _lastRouteTo = null;
                });
              }
            },
            icon: const Icon(Icons.credit_card),
            label: Text(
              'دفع الفاتورة (${amount.toStringAsFixed(2)} د.أ)',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _segTab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalPingPongLine extends StatefulWidget {
  const _HorizontalPingPongLine();

  @override
  State<_HorizontalPingPongLine> createState() =>
      _HorizontalPingPongLineState();
}

class _HorizontalPingPongLineState extends State<_HorizontalPingPongLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _alignAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _alignAnim = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 5,
        width: double.infinity,
        color: Colors.white24,
        child: AnimatedBuilder(
          animation: _alignAnim,
          builder: (_, __) => Align(
            alignment: Alignment(_alignAnim.value, 0),
            child: FractionallySizedBox(
              widthFactor: 0.32,
              heightFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Minimal2DCarMarker extends StatelessWidget {
  final bool isWinch;
  const _Minimal2DCarMarker({required this.isWinch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(20, 36),
        painter: _Minimal2DCarPainter(
          bodyColor: isWinch ? AppColors.orange : AppColors.navy,
        ),
      ),
    );
  }
}

class _Minimal2DCarPainter extends CustomPainter {
  final Color bodyColor;
  const _Minimal2DCarPainter({required this.bodyColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 3, w - 2, h - 2),
        const Radius.circular(7),
      ),
      shadowPaint,
    );

    final bodyPaint = Paint()..color = bodyColor;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, w - 2, h - 2),
      const Radius.circular(7),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(bodyRect, borderPaint);

    final glassPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.22, h * 0.22, w * 0.56, h * 0.20),
        const Radius.circular(3),
      ),
      glassPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.26, h * 0.68, w * 0.48, h * 0.13),
        const Radius.circular(2.5),
      ),
      glassPaint..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _Minimal2DCarPainter oldDelegate) =>
      oldDelegate.bodyColor != bodyColor;
}