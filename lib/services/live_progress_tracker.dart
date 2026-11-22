import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dynamic_island_service.dart';
import 'notifications_service.dart';

class LiveProgressTracker {
  LiveProgressTracker._();
  static final LiveProgressTracker instance = LiveProgressTracker._();
  factory LiveProgressTracker() => instance;

  StreamSubscription<Position>? _workshopSub;
  StreamSubscription<Position>? _emergencySub;
  final SupabaseClient _db = Supabase.instance.client;
  final NotificationsService _notifs = NotificationsService.instance;

  final ValueNotifier<double?> workshopDistanceKm = ValueNotifier<double?>(null);
  final ValueNotifier<double> workshopGpsProgress = ValueNotifier<double>(0.05);
  final ValueNotifier<double?> emergencyDistanceKm = ValueNotifier<double?>(null);
  final ValueNotifier<double> emergencyGpsProgress = ValueNotifier<double>(0.05);

  final Map<String, double> _initialDistanceKm = {};
  String? _activeWorkshopApptId;
  String? _activeEmergencyReqId;
  DateTime? _lastWorkshopDbSync;
  DateTime? _lastEmergencyDbSync;

  static double distanceKmBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return double.parse((meters / 1000.0).toStringAsFixed(2));
  }

  /// يحسب نسبة التقدم المستمرة من 0.05 إلى 1.0 حسب المسافة الحالية مقارنة بالمسافة الأولية
  double computeGpsProgress(String keyId, double currentKm) {
    if (currentKm <= 0.15) return 1.0; // وصل ضمن 150 متر
    final prevInit = _initialDistanceKm[keyId];
    if (prevInit == null || currentKm > prevInit) {
      _initialDistanceKm[keyId] = currentKm < 0.4 ? 0.4 : currentKm;
    }
    final initial = _initialDistanceKm[keyId]!;
    final ratio = (initial - currentKm) / initial;
    return ratio.clamp(0.05, 0.99);
  }

  Future<bool> _hasPermission() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// تتبع العميل في طريقه إلى الورشة (تحديث كل 5 متر لحركة ناعمة جداً)
  Future<void> startTrackingToWorkshop({
    required String appointmentId,
    required double workshopLat,
    required double workshopLng,
    required String workshopUserId,
  }) async {
    if (_activeWorkshopApptId == appointmentId && _workshopSub != null) {
      return;
    }
    _activeWorkshopApptId = appointmentId;
    await _workshopSub?.cancel();

    if (!await _hasPermission()) return;

    void handlePosition(Position pos) async {
      final km = distanceKmBetween(
        pos.latitude,
        pos.longitude,
        workshopLat,
        workshopLng,
      );
      final smoothProgress = computeGpsProgress('appt_$appointmentId', km);

      workshopDistanceKm.value = km;
      workshopGpsProgress.value = smoothProgress;

      // مزامنة موقع الزبون بالقاعدة كل 4 ثوانٍ لتظهر للورشة أيضاً
      final now = DateTime.now();
      if (_lastWorkshopDbSync == null ||
          now.difference(_lastWorkshopDbSync!).inSeconds >= 4) {
        _lastWorkshopDbSync = now;
        try {
          await _db.from('workshop_appointments').update({
            'customer_latitude': pos.latitude,
            'customer_longitude': pos.longitude,
          }).eq('id', appointmentId);
        } catch (_) {}
      }

      await DynamicIslandService.instance.syncProgress(
        keyId: 'appt_$appointmentId',
        title: 'موعد الورشة',
        statusText: km <= 0.15 ? 'وصلت إلى الورشة' : 'في الطريق إلى الورشة',
        progress: smoothProgress,
        etaOrDistance: km <= 0.15 ? 'وصلت ✓' : '${km.toStringAsFixed(1)} كم',
      );

      if (km <= 0.15) {
        await markWorkshopArrived(
          appointmentId: appointmentId,
          workshopUserId: workshopUserId,
        );
      }
    }

    try {
      final firstPos = await Geolocator.getCurrentPosition();
      handlePosition(firstPos);
    } catch (_) {}

    _workshopSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(handlePosition, onError: (_) {});
  }

  Future<void> markWorkshopArrived({
    required String appointmentId,
    required String workshopUserId,
  }) async {
    await _workshopSub?.cancel();
    _workshopSub = null;
    workshopDistanceKm.value = 0.0;
    workshopGpsProgress.value = 1.0;

    await _db.from('workshop_appointments').update({
      'progress_step': 'arrived_at_workshop',
    }).eq('id', appointmentId);

    await _notifs.sendNotification(
      targetUserId: workshopUserId,
      title: 'وصل العميل إلى ورشتك',
      body: 'يمكنك الآن البدء بفحص السيارة وتحديث مراحل الصيانة.',
      type: 'customer_arrived',
      referenceId: appointmentId,
    );
  }

  /// تتبع الميكانيكي / الونش في طريقه للعميل (بث GPS مستمر كل 5 متر)
  Future<void> startTrackingEmergencyArrival({
    required String requestId,
    required String customerUserId,
    required String serviceType,
    required double pickupLat,
    required double pickupLng,
  }) async {
    if (_activeEmergencyReqId == requestId && _emergencySub != null) {
      return;
    }
    _activeEmergencyReqId = requestId;
    await _emergencySub?.cancel();

    if (!await _hasPermission()) return;

    void handlePosition(Position pos) async {
      final km = distanceKmBetween(
        pos.latitude,
        pos.longitude,
        pickupLat,
        pickupLng,
      );
      final smoothProgress = computeGpsProgress('emg_$requestId', km);

      emergencyDistanceKm.value = km;
      emergencyGpsProgress.value = smoothProgress;

      // بث موقع الفني للقاعدة كل 4 ثوانٍ ليراه الزبون يتحرك بسلاسة
      final now = DateTime.now();
      if (_lastEmergencyDbSync == null ||
          now.difference(_lastEmergencyDbSync!).inSeconds >= 4) {
        _lastEmergencyDbSync = now;
        try {
          await _db.from('mechanic_requests').update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          }).eq('id', requestId);
        } catch (_) {}
      }

      if (km <= 0.15) {
        await markEmergencyArrived(
          requestId: requestId,
          customerUserId: customerUserId,
          serviceType: serviceType,
        );
      }
    }

    try {
      final firstPos = await Geolocator.getCurrentPosition();
      handlePosition(firstPos);
    } catch (_) {}

    _emergencySub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(handlePosition, onError: (_) {});
  }

  Future<void> markEmergencyArrived({
    required String requestId,
    required String customerUserId,
    required String serviceType,
  }) async {
    await _emergencySub?.cancel();
    _emergencySub = null;
    emergencyDistanceKm.value = 0.0;
    emergencyGpsProgress.value = 1.0;

    await _db.from('mechanic_requests').update({
      'progress_step': 'arrived_at_pickup',
    }).eq('id', requestId);

    final isWinch = serviceType == 'winch';
    await _notifs.sendNotification(
      targetUserId: customerUserId,
      title: isWinch ? 'وصل الونش إلى موقعك' : 'وصل ميكانيكي الطوارئ',
      body: isWinch
          ? 'سائق الونش متواجد الآن عند نقطة الالتقاط.'
          : 'الميكانيكي وصل إلى موقع سيارتك الآن.',
      type: isWinch ? 'winch_arrived' : 'mechanic_arrived',
      referenceId: requestId,
    );
  }

  void stop() {
    _workshopSub?.cancel();
    _workshopSub = null;
    _emergencySub?.cancel();
    _emergencySub = null;
  }
}