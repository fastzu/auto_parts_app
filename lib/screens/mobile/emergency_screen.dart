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
  final _notifs = NotificationsService.instance;
  final _loc = AppLocaleService.instance;
  final _mapController = MapController();
  final _carCtrl = TextEditingController(text: 'تويوتا كامري 2022');

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _submitting = false;
  bool _actionBusy = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';
  double _distanceKm = 5.0;

  StreamSubscription<List<Map<String, dynamic>>>? _activeReqSub;
  Map<String, dynamic>? _activeRequest;
  Map<String, dynamic>? _assignedProvider;
  String? _loadedProviderId;
  LatLng? _providerLatLng;

  final List<({String id, String ar, String en, IconData icon})> _problems =
      const [
    (
      id: 'بطارية',
      ar: 'بطارية',
      en: 'Battery',
      icon: Icons.battery_alert_rounded,
    ),
    (
      id: 'بنشر / إطار',
      ar: 'بنشر / إطار',
      en: 'Flat Tire',
      icon: Icons.tire_repair_rounded,
    ),
    (
      id: 'عطل محرك',
      ar: 'عطل محرك',
      en: 'Engine Issue',
      icon: Icons.engineering_rounded,
    ),
    (
      id: 'نفاد وقود',
      ar: 'نفاد وقود',
      en: 'Out of Fuel',
      icon: Icons.local_gas_station_rounded,
    ),
    (
      id: 'حادث / سحب',
      ar: 'حادث / سحب',
      en: 'Accident / Tow',
      icon: Icons.car_crash_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _detectMyLocation();
    _listenToActiveRequest();
  }

  @override
  void dispose() {
    _activeReqSub?.cancel();
    _carCtrl.dispose();
    super.dispose();
  }

  void _listenToActiveRequest() {
    _activeReqSub?.cancel();
    _activeReqSub = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .eq('user_id', widget.profile.id)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            Map<String, dynamic>? current;
            for (final r in rows) {
              final st = (r['status'] as String? ?? '').toLowerCase();
              final pay = (r['payment_status'] as String? ?? 'unpaid')
                  .toLowerCase();
              final amt = ((r['total_amount'] as num?) ?? 0).toDouble();
              if (st == 'cancelled') continue;
              if (st == 'completed' && (pay == 'paid' || amt <= 0)) continue;
              current = r;
              break;
            }

            if (!mounted) return;
            final mechId = current?['mechanic_id'] as String?;
            final pLat = (current?['latitude'] as num?)?.toDouble();
            final pLng = (current?['longitude'] as num?)?.toDouble();

            setState(() {
              _activeRequest = current;
              if (mechId == null || mechId.isEmpty) {
                _assignedProvider = null;
                _loadedProviderId = null;
                _providerLatLng = null;
              } else if (pLat != null && pLng != null) {
                _providerLatLng = LatLng(pLat, pLng);
              }
            });

            if (mechId != null &&
                mechId.isNotEmpty &&
                mechId != _loadedProviderId) {
              _fetchProviderProfile(mechId);
            }
          },
          onError: (_) {},
        );
  }

  Future<void> _fetchProviderProfile(String providerId) async {
    _loadedProviderId = providerId;
    try {
      final row = await _db
          .from('customers')
          .select(
              'id, full_name, username, phone, rating_avg, rating_count, latitude, longitude')
          .eq('id', providerId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _assignedProvider = row;
        if (_providerLatLng == null &&
            row?['latitude'] != null &&
            row?['longitude'] != null) {
          _providerLatLng = LatLng(
            (row!['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble(),
          );
        }
      });
    } catch (_) {}
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
      _mapController.move(_pickupLatLng, 15.0);
    } catch (_) {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _onMapTap(LatLng latLng) async {
    if (_activeRequest != null) return;
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

  double? _providerDistanceKm() {
    if (_activeRequest == null || _providerLatLng == null) return null;
    final pickupLat = (_activeRequest!['pickup_latitude'] as num?)?.toDouble() ??
        _pickupLatLng.latitude;
    final pickupLng =
        (_activeRequest!['pickup_longitude'] as num?)?.toDouble() ??
            _pickupLatLng.longitude;
    final meters = Geolocator.distanceBetween(
      _providerLatLng!.latitude,
      _providerLatLng!.longitude,
      pickupLat,
      pickupLng,
    );
    return meters / 1000.0;
  }

  Future<void> _submitEmergencyRequest() async {
    FocusScope.of(context).unfocus();
    final carText = _carCtrl.text.trim();
    if (carText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى كتابة نوع وموديل السيارة أولاً',
            'Please enter your car make and model first',
          )),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final useWinch = EnvConfig.winchEnabled.value && _serviceType == 'winch';
    setState(() => _submitting = true);
    try {
      await _db.from('mechanic_requests').insert({
        'user_id': widget.profile.id,
        'mechanic_id': null,
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
        'broadcast_all': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'تم إرسال طلبك بنجاح! بانتظار عروض الأسعار من أقرب مزود',
              'Request sent! Waiting for price quotes from nearby providers',
            )),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// قبول عرض السعر -> يبدأ التتبع المباشر (في الطريق -> وصل -> جاري الإصلاح) ولا يصدر فاتورة بعد!
  Future<void> _acceptQuote(Map<String, dynamic> req) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final reqId = req['id'] as String;
      final mechId = req['mechanic_id'] as String?;

      await _db.from('mechanic_requests').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
        'payment_status': 'unpaid',
      }).eq('id', reqId);

      if (mechId != null && mechId.isNotEmpty) {
        try {
          await _notifs.sendNotification(
            targetUserId: mechId,
            title: 'وافق العميل على عرض السعر ✓',
            body: 'انطلق الآن لموقع العميل وابدأ خطوات التنفيذ.',
            type: 'emergency_quote_accepted',
            referenceId: reqId,
          );
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'تم قبول العرض بنجاح ✓ المزود في طريقه إليك الآن',
              'Quote accepted! The provider is now on the way',
            )),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر قبول العرض: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// رفض عرض السعر -> يمسح المزود ويصفّر السعر ويعيد الطلب للبحث (بدون إصدار فاتورة أبداً!)
  Future<void> _rejectQuote(Map<String, dynamic> req) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final reqId = req['id'] as String;
      final mechId = req['mechanic_id'] as String?;

      await _db.from('mechanic_requests').update({
        'status': 'pending',
        'progress_step': 'pending',
        'mechanic_id': null,
        'total_amount': 0.0,
        'payment_status': 'unpaid',
        'latitude': null,
        'longitude': null,
      }).eq('id', reqId);

      if (mechId != null && mechId.isNotEmpty) {
        try {
          await _notifs.sendNotification(
            targetUserId: mechId,
            title: 'تم رفض عرض السعر',
            body: 'قام العميل برفض عرض السعر وبحث عن عرض آخر.',
            type: 'emergency_quote_rejected',
            referenceId: reqId,
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _assignedProvider = null;
          _loadedProviderId = null;
          _providerLatLng = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'تم رفض العرض — جاري البحث عن مزود آخر (أو يمكنك إلغاء الطلب)',
              'Quote rejected — searching for another provider',
            )),
            backgroundColor: AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر رفض العرض: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// إلغاء الطلب نهائياً (مسموح فقط قبل إصدار الفاتورة)
  Future<void> _cancelRequest(Map<String, dynamic> req) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _db.from('mechanic_requests').update({
        'status': 'cancelled',
        'progress_step': 'cancelled',
        'total_amount': 0.0,
        'payment_status': 'unpaid',
      }).eq('id', req['id'] as String);

      if (mounted) {
        setState(() {
          _activeRequest = null;
          _assignedProvider = null;
          _loadedProviderId = null;
          _providerLatLng = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('تم إلغاء الطلب بنجاح', 'Request cancelled')),
            backgroundColor: AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إلغاء الطلب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    await launchUrl(Uri.parse('tel:${phone.trim()}'));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EnvConfig.winchEnabled,
        EnvConfig.paymentsEnabled,
        _loc.langCode,
      ]),
      builder: (context, _) {
        final showWinch = EnvConfig.winchEnabled.value;
        if (!showWinch && _serviceType == 'winch') {
          _serviceType = 'mechanic';
          _pickingDropoff = false;
        }
        final isWinch = showWinch && _serviceType == 'winch';

        final req = _activeRequest;
        final status = (req?['status'] as String? ?? '').toLowerCase();
        final step = (req?['progress_step'] as String? ?? '').toLowerCase();
        final payStatus =
            (req?['payment_status'] as String? ?? 'unpaid').toLowerCase();
        final mechId = (req?['mechanic_id'] as String?)?.trim() ?? '';
        final totalAmount = ((req?['total_amount'] as num?) ?? 0).toDouble();

        // تحديد المرحلة بدقة تامة — مستحيل ظهور الفاتورة عند الرفض أو قبل انتهاء العمل
        final bool isInvoiceReady = req != null &&
            mechId.isNotEmpty &&
            totalAmount > 0 &&
            payStatus != 'paid' &&
            (status == 'awaiting_payment' ||
                step == 'awaiting_payment' ||
                payStatus == 'invoiced' ||
                status == 'completed');

        final bool isQuoteReceived = req != null &&
            !isInvoiceReady &&
            mechId.isNotEmpty &&
            totalAmount > 0 &&
            (status == 'quoted' || step == 'quote_sent');

        final bool isInProgress = req != null &&
            !isInvoiceReady &&
            !isQuoteReceived &&
            mechId.isNotEmpty &&
            (status == 'accepted' || status == 'in_progress');

        final bool isPendingSearch =
            req != null && !isInvoiceReady && !isQuoteReceived && !isInProgress;

        final distKm = _providerDistanceKm();
        final etaMin =
            distKm != null ? math.max(1, (distKm * 2.5).round()) : null;

        final topPillText = (isInProgress && distKm != null)
            ? _loc.tr(
                'المزود على بُعد ${distKm.toStringAsFixed(1)} كم (~$etaMin د)',
                'Provider is ${distKm.toStringAsFixed(1)} km away (~$etaMin min)',
              )
            : _loc.tr('طوارئ غيارك المباشرة', 'Ghiyarak Live Emergency');

        final topDotColor = isInProgress ? AppColors.success : AppColors.orange;

        final activePickup = req != null &&
                req['pickup_latitude'] != null &&
                req['pickup_longitude'] != null
            ? LatLng(
                (req['pickup_latitude'] as num).toDouble(),
                (req['pickup_longitude'] as num).toDouble(),
              )
            : _pickupLatLng;

        return Stack(
          children: [
            // الخريطة بملء الشاشة — OpenStreetMap مجانية تماماً بدون API Key
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: activePickup,
                  initialZoom: 15.0,
                  onTap: (_, latLng) => _onMapTap(latLng),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.ghayarakjo.app',
                    maxZoom: 19,
                  ),
                  if ((req == null && isWinch) ||
                      (req != null &&
                          req['dropoff_latitude'] != null &&
                          req['dropoff_longitude'] != null))
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            activePickup,
                            req != null && req['dropoff_latitude'] != null
                                ? LatLng(
                                    (req['dropoff_latitude'] as num).toDouble(),
                                    (req['dropoff_longitude'] as num)
                                        .toDouble(),
                                  )
                                : _dropoffLatLng,
                          ],
                          color: AppColors.orange,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                  if (isInProgress && _providerLatLng != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [_providerLatLng!, activePickup],
                          color: AppColors.navy,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: activePickup,
                        width: 64,
                        height: 64,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.orange, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_car_filled_rounded,
                            color: AppColors.navy,
                            size: 28,
                          ),
                        ),
                      ),
                      if (req == null && isWinch)
                        Marker(
                          point: _dropoffLatLng,
                          width: 44,
                          height: 44,
                          child: const Icon(
                            Icons.flag_rounded,
                            color: AppColors.navy,
                            size: 34,
                          ),
                        ),
                      if ((isInProgress || isQuoteReceived) &&
                          _providerLatLng != null)
                        Marker(
                          point: _providerLatLng!,
                          width: 54,
                          height: 54,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              req['service_type'] == 'winch'
                                  ? Icons.local_shipping_rounded
                                  : Icons.build_rounded,
                              color: AppColors.orange,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // الشريط العلوي (بدون كلمة كم مزود متاح)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: topDotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              topPillText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 5,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _detectMyLocation,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: _loadingGps
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.navy,
                                  ),
                                )
                              : const Icon(Icons.my_location,
                                  color: AppColors.navy, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // البطاقة السفلية حسب المرحلة الحالية
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.56,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(26)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 4.5,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      if (req == null)
                        _buildNewRequestSheet(showWinch, isWinch)
                      else if (isPendingSearch)
                        _buildPendingSearchSheet(req)
                      else if (isQuoteReceived)
                        _buildQuoteDecisionSheet(req, totalAmount)
                      else if (isInProgress)
                        _buildLiveProgressSheet(req, step, totalAmount)
                      else if (isInvoiceReady)
                        _buildInvoicePaymentSheet(req, totalAmount, payStatus),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// المرحلة 0: إنشاء طلب طوارئ جديد
  Widget _buildNewRequestSheet(bool showWinch, bool isWinch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.request_quote_rounded,
                  color: AppColors.orange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _loc.tr(
                    'التسعير بنظام عرض السعر: بعد إرسال الطلب يصلك عرض سعر مباشر من المزود ولك حرية القبول أو الرفض، وتصدر الفاتورة فقط بعد انتهاء العمل.',
                    'Quote-based pricing: Receive a direct quote, accept or reject freely, and pay only after work is completed.',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showWinch) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _segTab(
                  _loc.tr('ميكانيكي طوارئ', 'Mechanic'),
                  !isWinch,
                  () => setState(() {
                    _serviceType = 'mechanic';
                    _pickingDropoff = false;
                  }),
                ),
                _segTab(
                  _loc.tr('ونش سحب', 'Tow Truck'),
                  isWinch,
                  () => setState(() => _serviceType = 'winch'),
                ),
              ],
            ),
          ),
        ],
        if (isWinch) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Center(
                    child: Text(_loc.tr('نقطة الالتقاط', 'Pickup')),
                  ),
                  selected: !_pickingDropoff,
                  selectedColor: AppColors.navy,
                  labelStyle: TextStyle(
                    color:
                        !_pickingDropoff ? Colors.white : AppColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => _pickingDropoff = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: Center(
                    child: Text(_loc.tr('الوجهة على الخريطة', 'Drop-off')),
                  ),
                  selected: _pickingDropoff,
                  selectedColor: AppColors.orange,
                  labelStyle: TextStyle(
                    color:
                        _pickingDropoff ? Colors.white : AppColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => _pickingDropoff = true),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _loc.tr('نوع العطل', 'Issue Type'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _problems.map((item) {
            final selected = _selectedProblem == item.id;
            return GestureDetector(
              onTap: () => setState(() => _selectedProblem = item.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.navy : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.navy : AppColors.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 16,
                      color: selected ? Colors.white : AppColors.navy,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _loc.tr(item.ar, item.en),
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _carCtrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: _loc.tr('نوع وموديل السيارة', 'Car Make & Model'),
            prefixIcon: const Icon(Icons.directions_car_rounded),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _loc.tr('موقعك الحالي', 'Your Current Location'),
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _pickupAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              if (isWinch) ...[
                const SizedBox(height: 4),
                Text(
                  '${_loc.tr('الوجهة', 'Drop-off')}: $_dropoffAddress (${_distanceKm.toStringAsFixed(1)} كم)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
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
                : Icon(
                    isWinch
                        ? Icons.local_shipping_rounded
                        : Icons.radar_rounded,
                  ),
            label: Text(
              isWinch
                  ? _loc.tr('تأكيد طلب الونش واستلام عروض السعر',
                      'Request Tow & Get Quotes')
                  : _loc.tr('تأكيد طلب الميكانيكي واستلام عروض السعر',
                      'Request Mechanic & Get Quotes'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// المرحلة 1: جاري البحث عن مزود واستلام عرض سعر
  Widget _buildPendingSearchSheet(Map<String, dynamic> req) {
    final isWinch = req['service_type'] == 'winch';
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: AppColors.orange,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isWinch
                          ? _loc.tr('جاري البحث عن أقرب ونش سحب...',
                              'Searching for nearest tow truck...')
                          : _loc.tr('جاري البحث عن أقرب ميكانيكي طوارئ...',
                              'Searching for nearest mechanic...'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${req['car_details'] ?? ''} · ${req['description'] ?? ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _actionBusy ? null : () => _cancelRequest(req),
            icon: const Icon(Icons.close_rounded),
            label: Text(
              _loc.tr('إلغاء الطلب', 'Cancel Request'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  /// المرحلة 2: وصل عرض سعر جديد — قبول (يبدأ البروجرس) أو رفض (يعود للبحث بدون فاتورة)
  Widget _buildQuoteDecisionSheet(Map<String, dynamic> req, double price) {
    final providerName = (_assignedProvider?['full_name'] as String?) ??
        (_assignedProvider?['username'] as String?) ??
        _loc.tr('مزود خدمة غيارك', 'Ghiyarak Provider');
    final ratingAvg =
        ((_assignedProvider?['rating_avg'] as num?) ?? 5.0).toDouble();

    return Column(
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
                  Row(
                    children: [
                      const Icon(Icons.local_offer_rounded,
                          color: AppColors.orange, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        _loc.tr('وصلك عرض سعر جديد!', 'New Price Quote!'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
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
                      '${price.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_circle_outlined,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        providerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        ratingAvg.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
                onPressed: _actionBusy ? null : () => _acceptQuote(req),
                icon: _actionBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  _loc.tr('قبول العرض والمتابعة', 'Accept Quote'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade400, width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _actionBusy ? null : () => _rejectQuote(req),
                icon: const Icon(Icons.close_rounded, size: 19),
                label: Text(
                  _loc.tr('رفض العرض', 'Reject'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// المرحلة 3: التتبع المباشر بعد قبول العرض (لا توجد فاتورة حتى يُنهي الميكانيكي عمله)
  Widget _buildLiveProgressSheet(
    Map<String, dynamic> req,
    String step,
    double agreedPrice,
  ) {
    final isWinch = req['service_type'] == 'winch';
    final providerName = (_assignedProvider?['full_name'] as String?) ??
        (_assignedProvider?['username'] as String?) ??
        (isWinch
            ? _loc.tr('سائق الونش', 'Tow Driver')
            : _loc.tr('الميكانيكي', 'Mechanic'));
    final providerPhone = _assignedProvider?['phone'] as String?;

    final int currentStage = switch (step) {
      'arrived_at_pickup' => 1,
      'repairing' || 'towing' => 2,
      _ => 0, // on_the_way
    };

    final double progressVal = switch (currentStage) {
      0 => 0.35,
      1 => 0.65,
      _ => 0.88,
    };

    final String statusHeadline = switch (currentStage) {
      0 => isWinch
          ? _loc.tr('الونش في طريقه إلى موقعك', 'Tow truck is on the way')
          : _loc.tr('الميكانيكي في طريقه إلى موقعك', 'Mechanic is on the way'),
      1 => isWinch
          ? _loc.tr('وصل الونش إلى موقعك ✓', 'Tow truck has arrived ✓')
          : _loc.tr('وصل الميكانيكي إلى موقعك ✓', 'Mechanic has arrived ✓'),
      _ => isWinch
          ? _loc.tr('جاري سحب السيارة إلى الوجهة...', 'Towing vehicle...')
          : _loc.tr('جاري فحص وإصلاح السيارة...', 'Repairing vehicle...'),
    };

    final steps = [
      _loc.tr('في الطريق', 'On the way'),
      _loc.tr('وصل للموقع', 'Arrived'),
      isWinch ? _loc.tr('جاري السحب', 'Towing') : _loc.tr('جاري الإصلاح', 'Repairing'),
      _loc.tr('الفاتورة', 'Invoice'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isWinch ? Icons.local_shipping_rounded : Icons.build_rounded,
                color: AppColors.orange,
                size: 24,
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
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusHeadline,
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (providerPhone != null && providerPhone.isNotEmpty)
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success.withValues(alpha: 0.12),
                  foregroundColor: AppColors.success,
                ),
                onPressed: () => _callPhone(providerPhone),
                icon: const Icon(Icons.phone_rounded),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progressVal,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(steps.length, (i) {
            final done = i <= currentStage;
            return Expanded(
              child: Column(
                children: [
                  Icon(
                    done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    size: 18,
                    color: done ? AppColors.success : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    steps[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: done ? FontWeight.bold : FontWeight.normal,
                      color: done ? AppColors.navy : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _loc.tr('السعر المتفق عليه (يُدفع بعد إنهاء العمل)',
                    'Agreed quote (paid after work)'),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${agreedPrice.toStringAsFixed(2)} د.أ',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// المرحلة 4: صدرت الفاتورة رسمياً بعد انتهاء العمل — الدفع الآن
  Widget _buildInvoicePaymentSheet(
    Map<String, dynamic> req,
    double amount,
    String payStatus,
  ) {
    final providerName = (_assignedProvider?['full_name'] as String?) ??
        (_assignedProvider?['username'] as String?) ??
        _loc.tr('مزود خدمة غيارك', 'Ghiyarak Provider');
    final providerPhone = _assignedProvider?['phone'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.orange,
                size: 24,
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
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _loc.tr(
                      'أنهى المزود عمله وتم إصدار الفاتورة — يرجى الدفع الآن',
                      'Work completed & invoice issued — please pay now',
                    ),
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (providerPhone != null && providerPhone.isNotEmpty)
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success.withValues(alpha: 0.12),
                  foregroundColor: AppColors.success,
                ),
                onPressed: () => _callPhone(providerPhone),
                icon: const Icon(Icons.phone_rounded),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _loc.tr(
            'ملاحظة: تم إصدار الفاتورة رسمياً بعد إتمام الخدمة ولا يمكن إلغاء الطلب أو الدفع بعد الإصدار.',
            'Note: Invoice has been officially issued after completion and cannot be cancelled.',
          ),
          style: TextStyle(
            color: Colors.red.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (payStatus == 'pending_verification')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Text(
              _loc.tr(
                'تم إرسال إثبات تحويل CliQ — بانتظار تأكيد الإدارة ✓',
                'CliQ transfer submitted — pending verification ✓',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(
                  EmergencyCheckoutScreen(
                    request: DbMechanicRequest.fromMap(req),
                    customerProfile: widget.profile,
                    onPaymentCompleted: () {
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
              icon: const Icon(Icons.credit_card_rounded),
              label: Text(
                '${_loc.tr('دفع الفاتورة', 'Pay Invoice')} (${amount.toStringAsFixed(2)} د.أ)',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                ),
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
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}