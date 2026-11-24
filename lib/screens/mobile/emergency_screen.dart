import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/live_progress_tracker.dart';
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

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _db = Supabase.instance.client;
  final _locationService = LocationService();
  final _tracker = LiveProgressTracker.instance;
  final _notifs = NotificationsService.instance;
  final _mapController = MapController();
  final _carCtrl = TextEditingController();

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _loadingRate = true;
  bool _submitting = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';
  double _distanceKm = 6.0;
  double _kmRate = 1.5;

  StreamSubscription<List<Map<String, dynamic>>>? _activeEmgSub;
  List<Map<String, dynamic>> _activeRequests = [];
  final Set<String> _cancellingIds = {};
  final Set<String> _fetchingProvIds = {};
  final Map<String, ({double? lat, double? lng})> _provCoords = {};

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
    _listenActiveRequests();
  }

  @override
  void dispose() {
    _activeEmgSub?.cancel();
    _carCtrl.dispose();
    super.dispose();
  }

  void _listenActiveRequests() {
    _activeEmgSub?.cancel();
    _activeEmgSub = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .eq('user_id', widget.profile.id)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            final active = rows.where((e) {
              final status = (e['status'] as String?) ?? 'pending';
              final payStatus = (e['payment_status'] as String?) ?? 'unpaid';
              final amount = (e['total_amount'] as num?)?.toDouble() ?? 0.0;
              if (status == 'cancelled' || status == 'rejected') return false;
              if (status != 'completed') return true;
              return status == 'completed' && amount > 0 && payStatus != 'paid';
            }).toList();
            setState(() => _activeRequests = active);
            for (final r in active) {
              final mId = r['mechanic_id'] as String?;
              if (mId != null && mId.isNotEmpty) {
                _fetchProviderFallbackCoords(mId);
              }
            }
          },
          onError: (_) {},
        );
  }

  Future<void> _fetchProviderFallbackCoords(String mechId) async {
    if (_provCoords.containsKey(mechId) || _fetchingProvIds.contains(mechId)) {
      return;
    }
    _fetchingProvIds.add(mechId);
    try {
      final row = await _db
          .from('customers')
          .select('latitude, longitude, workshop_latitude, workshop_longitude')
          .eq('id', mechId)
          .maybeSingle();
      final lat = (row?['latitude'] as num?)?.toDouble() ??
          (row?['workshop_latitude'] as num?)?.toDouble();
      final lng = (row?['longitude'] as num?)?.toDouble() ??
          (row?['workshop_longitude'] as num?)?.toDouble();
      if (mounted) {
        setState(() => _provCoords[mechId] = (lat: lat, lng: lng));
      }
    } catch (_) {} finally {
      _fetchingProvIds.remove(mechId);
    }
  }

  void _showTopToast(String title, String message, {bool isError = false}) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFDC2626) : AppColors.success,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }

  Future<void> _cancelEmergencyRequest(Map<String, dynamic> req) async {
    final id = req['id'] as String;
    if (_cancellingIds.contains(id)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إلغاء طلب الطوارئ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل أنت متأكد من إلغاء طلب الطوارئ الحالي؟ سيتم إشعار الفني/سائق الونش فوراً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء الطلب'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _cancellingIds.add(id));
    try {
      await _db.from('mechanic_requests').update({
        'status': 'cancelled',
        'progress_step': 'cancelled',
      }).eq('id', id);

      final mechId = req['mechanic_id'] as String?;
      if (mechId != null && mechId.isNotEmpty) {
        await _notifs.sendNotification(
          targetUserId: mechId,
          title: 'تم إلغاء طلب الطوارئ',
          body: 'قام العميل بإلغاء طلب الطوارئ.',
          type: 'order_cancelled',
          referenceId: id,
        );
      }

      _showTopToast('تم الإلغاء', 'تم إلغاء طلب الطوارئ بنجاح.');
    } catch (e) {
      _showTopToast('تعذر الإلغاء', '$e', isError: true);
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(id));
    }
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
  }

  Future<void> _submitOrder(double finalPrice, int etaMinutes) async {
    FocusScope.of(context).unfocus();
    final carText = _carCtrl.text.trim();
    if (carText.isEmpty) {
      _showTopToast(
        'بيانات ناقصة',
        'يرجى كتابة نوع وموديل السيارة أولاً',
        isError: true,
      );
      return;
    }

    final useWinch = EnvConfig.winchEnabled.value && _serviceType == 'winch';
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
        'total_amount': useWinch ? finalPrice : 0.0,
        'estimated_time': '$etaMinutes دقيقة',
        'status': 'pending',
        'progress_step': 'pending',
      });

      if (mounted) {
        _carCtrl.clear();
        _showTopToast(
          'تم إرسال الطلب بنجاح',
          useWinch
              ? 'السعر التقديري ${finalPrice.toStringAsFixed(2)} د.أ · جاري تعيين أقرب ونش'
              : 'جاري البحث عن أقرب ميكانيكي طوارئ لموقعك',
        );
      }
    } catch (e) {
      _showTopToast('تعذر إرسال الطلب', '$e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildActiveRequestCard(Map<String, dynamic> e) {
    final id = e['id'] as String;
    final status = (e['status'] as String?) ?? 'pending';
    final step = (e['progress_step'] as String?) ?? 'pending';
    final serviceType = (e['service_type'] as String?) ?? 'mechanic';
    final isWinch = serviceType == 'winch';
    final mechId = e['mechanic_id'] as String?;
    final pickLat = (e['pickup_latitude'] as num?)?.toDouble();
    final pickLng = (e['pickup_longitude'] as num?)?.toDouble();
    final amount = (e['total_amount'] as num?)?.toDouble() ?? 0.0;
    final payStatus = (e['payment_status'] as String?) ?? 'unpaid';

    double? distKm;
    double progress;
    final isEnRoute = step == 'on_the_way' ||
        status == 'accepted' ||
        status == 'in_progress';

    if (step == 'completed' || status == 'completed') {
      progress = 1.0;
    } else if (step == 'arrived_at_pickup') {
      progress = 0.90;
    } else if (isEnRoute && pickLat != null && pickLng != null) {
      final liveLat = (e['latitude'] as num?)?.toDouble() ??
          (mechId != null ? _provCoords[mechId]?.lat : null);
      final liveLng = (e['longitude'] as num?)?.toDouble() ??
          (mechId != null ? _provCoords[mechId]?.lng : null);
      if (liveLat != null && liveLng != null) {
        distKm = LiveProgressTracker.distanceKmBetween(
          liveLat,
          liveLng,
          pickLat,
          pickLng,
        );
        final ratio = _tracker.computeGpsProgress('emg_scr_$id', distKm);
        progress = (0.22 + (ratio * 0.64)).clamp(0.22, 0.86);
      } else {
        progress = 0.45;
      }
    } else {
      progress = 0.16;
    }

    String statusText;
    if (status == 'completed' || step == 'completed') {
      statusText = 'تم إنهاء المساعدة الطارئة ✓';
    } else if (step == 'arrived_at_pickup') {
      statusText =
          isWinch ? 'وصل الونش إلى موقعك ✓' : 'وصل الميكانيكي إلى موقعك ✓';
    } else if (isEnRoute) {
      final base =
          isWinch ? 'الونش في طريقه إليك' : 'الميكانيكي في طريقه إليك';
      if (distKm != null) {
        final eta = (distKm * 2.2).round().clamp(1, 90);
        final distLabel = distKm < 1.0
            ? '${(distKm * 1000).round()} م'
            : '${distKm.toStringAsFixed(1)} كم';
        statusText = '$base · يبعد $distLabel (~$eta د)';
      } else {
        statusText = base;
      }
    } else {
      statusText = isWinch
          ? 'جاري البحث عن أقرب ونش طوارئ...'
          : 'جاري البحث عن أقرب ميكانيكي طوارئ...';
    }

    final canCancel = status != 'completed' &&
        status != 'cancelled' &&
        payStatus != 'paid';
    final canPay = payStatus != 'paid' &&
        amount > 0 &&
        mechId != null &&
        mechId.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isWinch ? Icons.local_shipping : Icons.build_circle,
                color: AppColors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${isWinch ? 'طلب ونش نشط' : 'طلب ميكانيكي نشط'} · ${e['description'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            statusText,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white24,
              color: AppColors.orange,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (canPay)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    animatedRoute(
                      EmergencyCheckoutScreen(
                        request: DbMechanicRequest.fromMap(e),
                        customerProfile: widget.profile,
                        onPaymentCompleted: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: Text(
                    'دفع الفاتورة (${amount.toStringAsFixed(2)} د.أ)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (canCancel)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    foregroundColor: const Color(0xFFFFB4B4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _cancellingIds.contains(id)
                      ? null
                      : () => _cancelEmergencyRequest(e),
                  icon: _cancellingIds.contains(id)
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cancel_outlined, size: 15),
                  label: const Text(
                    'إلغاء الطلب',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
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
        final eta = (_distanceKm * 2.4).round().clamp(8, 45);

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
                        if (isWinch)
                          IconButton(
                            tooltip: 'تحديث تسعيرة الونش',
                            onPressed: _loadKmRate,
                            icon: const Icon(Icons.refresh,
                                color: AppColors.navy, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // طلبات الطوارئ النشطة مع التتبع المباشر وزر الإلغاء
                    if (_activeRequests.isNotEmpty) ...[
                      ..._activeRequests.map(_buildActiveRequestCard),
                      const SizedBox(height: 6),
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
                              _loadKmRate();
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

                    SizedBox(
                      height: 205,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _pickupLatLng,
                                  initialZoom: 13.5,
                                  minZoom: 3,
                                  maxZoom: 18,
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
                                      Marker(
                                        point: _pickupLatLng,
                                        width: 72,
                                        height: 72,
                                        child: const PulsingPin(
                                            color: AppColors.orange),
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