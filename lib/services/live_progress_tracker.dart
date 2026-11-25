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
  final ValueNotifier<double?> emergencyDistanceKm =
      ValueNotifier<double?>(null);
  final ValueNotifier<double> emergencyGpsProgress = ValueNotifier<double>(0.05);

  final Map<String, double> _initialDistanceKm = {};
  final Set<String> _arrivedWorkshopIds = {};
  final Set<String> _arrivedEmergencyIds = {};
  final Set<String> _markingWorkshopIds = {};
  final Set<String> _markingEmergencyIds = {};

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

  /// تتبع العميل في طريقه إلى الورشة
  Future<void> startTrackingToWorkshop({
    required String appointmentId,
    required double workshopLat,
    required double workshopLng,
    required String workshopUserId,
  }) async {
    if (_arrivedWorkshopIds.contains(appointmentId)) return;
    if (_activeWorkshopApptId == appointmentId && _workshopSub != null) {
      return;
    }
    _activeWorkshopApptId = appointmentId;
    await _workshopSub?.cancel();
    _workshopSub = null;

    if (!await _hasPermission()) return;

    Future<bool> handlePosition(Position pos) async {
      if (_arrivedWorkshopIds.contains(appointmentId)) return true;

      final km = distanceKmBetween(
        pos.latitude,
        pos.longitude,
        workshopLat,
        workshopLng,
      );
      final smoothProgress = computeGpsProgress('appt_$appointmentId', km);

      workshopDistanceKm.value = km;
      workshopGpsProgress.value = smoothProgress;

      if (km <= 0.15) {
        await DynamicIslandService.instance.syncProgress(
          keyId: 'appt_$appointmentId',
          title: 'موعد الورشة',
          statusText: 'وصلت إلى الورشة',
          progress: 1.0,
          etaOrDistance: 'وصلت ✓',
        );
        await markWorkshopArrived(
          appointmentId: appointmentId,
          workshopUserId: workshopUserId,
        );
        return true;
      }

      final now = DateTime.now();
      if (_lastWorkshopDbSync == null ||
          now.difference(_lastWorkshopDbSync!).inSeconds >= 5) {
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
        statusText: 'في الطريق إلى الورشة',
        progress: smoothProgress,
        etaOrDistance: '${km.toStringAsFixed(1)} كم',
      );
      return false;
    }

    try {
      final firstPos = await Geolocator.getCurrentPosition();
      final arrivedNow = await handlePosition(firstPos);
      if (arrivedNow || _arrivedWorkshopIds.contains(appointmentId)) {
        return; // وصل مسبقاً — لا تفتح بث GPS أبداً
      }
    } catch (_) {}

    if (_arrivedWorkshopIds.contains(appointmentId)) return;

    _workshopSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      handlePosition(pos);
    }, onError: (_) {});
  }

  Future<void> markWorkshopArrived({
    required String appointmentId,
    required String workshopUserId,
  }) async {
    if (_arrivedWorkshopIds.contains(appointmentId) ||
        _markingWorkshopIds.contains(appointmentId)) {
      return;
    }
    _markingWorkshopIds.add(appointmentId);
    _arrivedWorkshopIds.add(appointmentId);

    try {
      await _workshopSub?.cancel();
      _workshopSub = null;
      workshopDistanceKm.value = 0.0;
      workshopGpsProgress.value = 1.0;

      // تحديث مشروط: لا يرسل الإشعار إلا إذا كانت الحالة فعلاً on_the_way
      final updated = await _db
          .from('workshop_appointments')
          .update({'progress_step': 'arrived_at_workshop'})
          .eq('id', appointmentId)
          .or('progress_step.is.null,progress_step.eq.on_the_way')
          .select('id');

      if ((updated as List).isEmpty) return;

      await _notifs.sendNotification(
        targetUserId: workshopUserId,
        title: 'وصل العميل إلى ورشتك',
        body: 'يمكنك الآن البدء بفحص السيارة وتحديث مراحل الصيانة.',
        type: 'customer_arrived',
        referenceId: appointmentId,
      );
    } finally {
      _markingWorkshopIds.remove(appointmentId);
    }
  }

  /// تتبع الميكانيكي / الونش في طريقه للعميل
  Future<void> startTrackingEmergencyArrival({
    required String requestId,
    required String customerUserId,
    required String serviceType,
    required double pickupLat,
    required double pickupLng,
  }) async {
    if (_arrivedEmergencyIds.contains(requestId)) return;
    if (_activeEmergencyReqId == requestId && _emergencySub != null) {
      return;
    }
    _activeEmergencyReqId = requestId;
    await _emergencySub?.cancel();
    _emergencySub = null;

    if (!await _hasPermission()) return;

    Future<bool> handlePosition(Position pos) async {
      if (_arrivedEmergencyIds.contains(requestId)) return true;

      final km = distanceKmBetween(
        pos.latitude,
        pos.longitude,
        pickupLat,
        pickupLng,
      );
      final smoothProgress = computeGpsProgress('emg_$requestId', km);

      emergencyDistanceKm.value = km;
      emergencyGpsProgress.value = smoothProgress;

      if (km <= 0.15) {
        await markEmergencyArrived(
          requestId: requestId,
          customerUserId: customerUserId,
          serviceType: serviceType,
        );
        return true;
      }

      final now = DateTime.now();
      if (_lastEmergencyDbSync == null ||
          now.difference(_lastEmergencyDbSync!).inSeconds >= 5) {
        _lastEmergencyDbSync = now;
        try {
          await _db.from('mechanic_requests').update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          }).eq('id', requestId);
        } catch (_) {}
      }
      return false;
    }

    try {
      final firstPos = await Geolocator.getCurrentPosition();
      final arrivedNow = await handlePosition(firstPos);
      if (arrivedNow || _arrivedEmergencyIds.contains(requestId)) {
        return; // وصل مسبقاً — لا تفتح بث GPS أبداً
      }
    } catch (_) {}

    if (_arrivedEmergencyIds.contains(requestId)) return;

    _emergencySub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      handlePosition(pos);
    }, onError: (_) {});
  }

  Future<void> markEmergencyArrived({
    required String requestId,
    required String customerUserId,
    required String serviceType,
  }) async {
    if (_arrivedEmergencyIds.contains(requestId) ||
        _markingEmergencyIds.contains(requestId)) {
      return;
    }
    _markingEmergencyIds.add(requestId);
    _arrivedEmergencyIds.add(requestId);

    try {
      await _emergencySub?.cancel();
      _emergencySub = null;
      emergencyDistanceKm.value = 0.0;
      emergencyGpsProgress.value = 1.0;

      // تحديث مشروط: لا يرسل الإشعار إلا مرة واحدة عند التحوّل من on_the_way
      final updated = await _db
          .from('mechanic_requests')
          .update({'progress_step': 'arrived_at_pickup'})
          .eq('id', requestId)
          .or('progress_step.is.null,progress_step.eq.on_the_way')
          .select('id');

      if ((updated as List).isEmpty) return;

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
    } finally {
      _markingEmergencyIds.remove(requestId);
    }
  }

  void stop() {
    _workshopSub?.cancel();
    _workshopSub = null;
    _emergencySub?.cancel();
    _emergencySub = null;
  }
}