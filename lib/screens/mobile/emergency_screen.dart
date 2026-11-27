import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class EmergencyScreen extends StatefulWidget {
  final CustomerProfile profile;
  const EmergencyScreen({super.key, required this.profile});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _db = Supabase.instance.client;
  final _locationService = LocationService();
  final _mapController = MapController();
  final _carCtrl = TextEditingController();

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _loadingRate = true;
  bool _loadingRoute = false;
  bool _submitting = false;
  bool _satelliteView = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';
  double _distanceKm = 6.0;
  int? _routeEtaMinutes;
  double _kmRate = 1.5;

  /// نقاط المسار الحقيقي على الشوارع (مثل Google Maps) + مسار بديل
  List<LatLng> _routePoints = [];
  List<LatLng> _altRoutePoints = [];

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
    _loadKmRate();
    _detectMyLocation();
  }

  @override
  void dispose() {
    _carCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKmRate() async {
    try {
      final row = await _db
          .from('system_settings')
          .select('value')
          .eq('key', 'winch_price_per_km')
          .maybeSingle();
      if (mounted) {
        final parsed = double.tryParse(row?['value']?.toString() ?? '');
        setState(() {
          if (parsed != null && parsed > 0) {
            _kmRate = parsed;
          }
          _loadingRate = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRate = false);
    }
  }

  /// جلب المسار الحقيقي على الشوارع عبر OSRM (مع مسار بديل مثل Google Maps)
  Future<void> _fetchRoadRoute({bool moveCamera = false}) async {
    if (!EnvConfig.winchEnabled.value || _serviceType != 'winch') return;
    if (mounted) setState(() => _loadingRoute = true);

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_pickupLatLng.longitude},${_pickupLatLng.latitude};'
        '${_dropoffLatLng.longitude},${_dropoffLatLng.latitude}'
        '?overview=full&geometries=geojson&alternatives=true',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = (data['routes'] as List?) ?? [];
        if (routes.isNotEmpty) {
          final mainRoute = routes.first as Map<String, dynamic>;
          final coords =
              (mainRoute['geometry']['coordinates'] as List?) ?? [];
          final mainPts = coords
              .map((c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ))
              .toList();

          List<LatLng> altPts = [];
          if (routes.length > 1) {
            final altCoords =
                (routes[1]['geometry']['coordinates'] as List?) ?? [];
            altPts = altCoords
                .map((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();
          }

          final distMeters = (mainRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final durSecs = (mainRoute['duration'] as num?)?.toDouble() ?? 0.0;
          final distKm = distMeters > 0
              ? double.parse((distMeters / 1000.0).toStringAsFixed(2))
              : _distanceKm;
          final etaMins =
              durSecs > 0 ? (durSecs / 60.0).ceil().clamp(1, 180) : null;

          if (!mounted) return;
          setState(() {
            _routePoints = mainPts;
            _altRoutePoints = altPts;
            _distanceKm = distKm < 0.5 ? 0.5 : distKm;
            _routeEtaMinutes = etaMins;
            _loadingRoute = false;
          });

          if (moveCamera) {
            _centerMapOnRoute();
          }
          return;
        }
      }
    } catch (_) {}

    // بديل احتياطي في حال تعذر الوصول لسيرفر المسارات
    if (mounted) {
      setState(() {
        _routePoints = [_pickupLatLng, _dropoffLatLng];
        _altRoutePoints = [];
        _routeEtaMinutes = null;
        _loadingRoute = false;
      });
    }
  }

  void _centerMapOnRoute() {
    final midLat = (_pickupLatLng.latitude + _dropoffLatLng.latitude) / 2.0;
    final midLng = (_pickupLatLng.longitude + _dropoffLatLng.longitude) / 2.0;
    final zoom = _distanceKm <= 2
        ? 14.5
        : _distanceKm <= 5
            ? 13.2
            : _distanceKm <= 12
                ? 12.0
                : 11.0;
    _mapController.move(LatLng(midLat, midLng), zoom);
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
      _mapController.move(_pickupLatLng, 13.8);
      if (EnvConfig.winchEnabled.value && _serviceType == 'winch') {
        await _fetchRoadRoute();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGps = false);
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
    if (EnvConfig.winchEnabled.value && _serviceType == 'winch') {
      await _fetchRoadRoute(moveCamera: true);
    }
  }

  Future<void> _submitOrder(double finalPrice, int etaMinutes) async {
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
    final showPayments = EnvConfig.paymentsEnabled.value;
    setState(() => _submitting = true);
    try {
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
        'total_amount': showPayments ? finalPrice : 0.0,
        'estimated_time': '$etaMinutes دقيقة',
        'status': 'pending',
        'progress_step': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              useWinch
                  ? (showPayments
                      ? 'تم إرسال طلب الونش بنجاح! السعر التقديري ${finalPrice.toStringAsFixed(2)} د.أ'
                      : 'تم إرسال طلب الونش بنجاح! جاري تعيين أقرب سائق')
                  : 'تم إرسال طلب الطوارئ بنجاح! جاري تعيين أقرب فني',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
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
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
                widget.profile.subscriptionPlan) ==
            0.0;
        final proDiscount = isPro
            ? double.parse((rawTotal * 0.15).toStringAsFixed(2))
            : 0.0;
        final finalPrice =
            double.parse((rawTotal - proDiscount).toStringAsFixed(2));
        final eta =
            _routeEtaMinutes ?? (_distanceKm * 2.4).round().clamp(5, 60);

        final activeRoutePoints = _routePoints.length >= 2
            ? _routePoints
            : [_pickupLatLng, _dropoffLatLng];

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
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isWinch && showPayments)
                          IconButton(
                            tooltip: 'تحديث تسعيرة الونش',
                            onPressed: _loadKmRate,
                            icon: const Icon(Icons.refresh,
                                color: AppColors.navy, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

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
                              _loadKmRate();
                              _fetchRoadRoute(moveCamera: true);
                            }),
                            _segTab(
                              'ميكانيكي طوارئ',
                              !isWinch,
                              () => setState(() {
                                _serviceType = 'mechanic';
                                _pickingDropoff = false;
                              }),
                            ),
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

                    // الخريطة مع مسار الشوارع الحقيقي بنمط Google Maps
                    SizedBox(
                      height: 240,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _pickupLatLng,
                                initialZoom: 13.8,
                                onTap: (_, latLng) => _onMapTap(latLng),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: _satelliteView
                                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.autoparts.app',
                                ),
                                if (isWinch)
                                  PolylineLayer(
                                    polylines: [
                                      // مسار بديل (أزرق فاتح مع إطار أزرق مثل Google Maps)
                                      if (_altRoutePoints.length >= 2) ...[
                                        Polyline(
                                          points: _altRoutePoints,
                                          color: const Color(0xFF2563EB),
                                          strokeWidth: 7.5,
                                        ),
                                        Polyline(
                                          points: _altRoutePoints,
                                          color: const Color(0xFFBFDBFE),
                                          strokeWidth: 4.5,
                                        ),
                                      ],
                                      // المسار الرئيسي: إطار كحلي داكن + خط أزرق Google Maps
                                      Polyline(
                                        points: activeRoutePoints,
                                        color: const Color(0xFF1E1B4B),
                                        strokeWidth: 10.0,
                                      ),
                                      Polyline(
                                        points: activeRoutePoints,
                                        color: const Color(0xFF3B38F2),
                                        strokeWidth: 6.2,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _pickupLatLng,
                                      width: 68,
                                      height: 68,
                                      child: const PulsingPin(
                                          color: Color(0xFF3B38F2)),
                                    ),
                                    if (isWinch)
                                      Marker(
                                        point: _dropoffLatLng,
                                        width: 44,
                                        height: 44,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Color(0xFFEA4335),
                                          size: 40,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),

                            // زر تبديل الخريطة (قمر صناعي / شوارع)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Material(
                                color: Colors.white,
                                elevation: 3,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: _satelliteView
                                      ? 'خريطة الشوارع'
                                      : 'عرض القمر الصناعي',
                                  icon: Icon(
                                    _satelliteView
                                        ? Icons.map_outlined
                                        : Icons.satellite_alt,
                                    color: AppColors.navy,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _satelliteView = !_satelliteView),
                                ),
                              ),
                            ),

                            // شارة الوقت والمسافة الحقيقية مثل Google Maps
                            if (isWinch)
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.18),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_loadingRoute) ...[
                                        const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                        const SizedBox(width: 6),
                                      ] else
                                        const Icon(
                                          Icons.directions_car,
                                          color: Color(0xFF15803D),
                                          size: 16,
                                        ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '$eta د · ${_distanceKm.toStringAsFixed(1)} كم',
                                        style: const TextStyle(
                                          color: Color(0xFF15803D),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // زر تحديد موقعي GPS
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
                    _infoRow('موقعك الحالي', _pickupAddress),
                    if (isWinch) ...[
                      const SizedBox(height: 8),
                      _infoRow('الوجهة المطلوبة', _dropoffAddress),
                      const SizedBox(height: 8),
                      _infoRow(
                        'مسافة الطريق الفعلية',
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
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('ما المشكلة؟',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
                                horizontal: 16, vertical: 9),
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

                    // بطاقة تفاصيل الوقت (والسعر فقط عند تفعيل المعاملات المالية)
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
                          if (showPayments) ...[
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: BounceTap(
                  onTap:
                      _submitting ? () {} : () => _submitOrder(finalPrice, eta),
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
                                color: Colors.white, strokeWidth: 2.4),
                          )
                        : Text(
                            isWinch
                                ? (showPayments
                                    ? 'تأكيد طلب الونش (${finalPrice.toStringAsFixed(2)} د.أ)'
                                    : 'تأكيد طلب الونش')
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