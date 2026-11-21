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
  final NotificationsService _notifs = NotificationsService();

  final ValueNotifier<double?> workshopDistanceKm = ValueNotifier<double?>(null);
  final ValueNotifier<double?> emergencyDistanceKm = ValueNotifier<double?>(null);
  final ValueNotifier<Map<String, double>> workshopDistancesById =
      ValueNotifier<Map<String, double>>({});
  final ValueNotifier<Map<String, double>> emergencyDistancesById =
      ValueNotifier<Map<String, double>>({});

  final Map<String, double> _initialDistances = {};
  String? _activeWorkshopApptId;
  String? _activeEmergencyReqId;

  static double distanceKmBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return double.parse((meters / 1000).toStringAsFixed(2));
  }

  double computeGpsProgress(String id, double currentKm) {
    if (currentKm <= 0.15) {
      return 1.0;
    }
    final initial = _initialDistances.putIfAbsent(
      id,
      () => currentKm < 0.5 ? 1.0 : currentKm,
    );
    final baseline = initial < currentKm ? currentKm : initial;
    if (baseline <= 0.15) {
      return 1.0;
    }
    return (1.0 - (currentKm / baseline)).clamp(0.08, 0.96);
  }

  Future<bool> _hasPermission() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return false;
      }
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

  /// تتبع العميل في طريقه إلى الورشة + تحديث المسافة ونسبة التقدم + Dynamic Island
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

    if (!await _hasPermission()) {
      return;
    }

    _workshopSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (pos) async {
        final meters = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          workshopLat,
          workshopLng,
        );
        final km = double.parse((meters / 1000).toStringAsFixed(1));
        workshopDistanceKm.value = km;
        workshopDistancesById.value = {
          ...workshopDistancesById.value,
          appointmentId: km,
        };
        final gpsProg = computeGpsProgress('appt_$appointmentId', km);

        await DynamicIslandService.instance.syncProgress(
          keyId: 'appt_$appointmentId',
          title: 'موعد الورشة',
          statusText: meters <= 150 ? 'وصلت إلى الورشة' : 'في الطريق إلى الورشة',
          progress: meters <= 150 ? 1.0 : gpsProg,
          etaOrDistance: meters <= 150 ? 'وصلت ✓' : '$km كم',
        );

        if (meters <= 150) {
          await markWorkshopArrived(
            appointmentId: appointmentId,
            workshopUserId: workshopUserId,
          );
        }
      },
      onError: (_) {},
    );
  }

  Future<void> markWorkshopArrived({
    required String appointmentId,
    required String workshopUserId,
  }) async {
    await _workshopSub?.cancel();
    _workshopSub = null;
    workshopDistanceKm.value = 0.0;
    workshopDistancesById.value = {
      ...workshopDistancesById.value,
      appointmentId: 0.0,
    };

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

  /// تتبع فني الطوارئ / الونش في طريقه لموقع العميل + بث موقعه الحي لـ Supabase
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

    if (!await _hasPermission()) {
      return;
    }

    _emergencySub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (pos) async {
        final meters = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          pickupLat,
          pickupLng,
        );
        final km = double.parse((meters / 1000).toStringAsFixed(1));
        emergencyDistanceKm.value = km;
        emergencyDistancesById.value = {
          ...emergencyDistancesById.value,
          requestId: km,
        };
        final gpsProg = computeGpsProgress('emg_$requestId', km);

        try {
          await _db.from('mechanic_requests').update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          }).eq('id', requestId);
        } catch (_) {}

        await DynamicIslandService.instance.syncProgress(
          keyId: 'emg_$requestId',
          title: serviceType == 'winch' ? 'ونش الطوارئ' : 'ميكانيكي الطوارئ',
          statusText: meters <= 150 ? 'تم الوصول لموقع العميل' : 'في الطريق لموقع العميل',
          progress: meters <= 150 ? 1.0 : gpsProg,
          etaOrDistance: meters <= 150 ? 'وصل ✓' : '$km كم',
        );

        if (meters <= 150) {
          await markEmergencyArrived(
            requestId: requestId,
            customerUserId: customerUserId,
            serviceType: serviceType,
          );
        }
      },
      onError: (_) {},
    );
  }

  Future<void> markEmergencyArrived({
    required String requestId,
    required String customerUserId,
    required String serviceType,
  }) async {
    await _emergencySub?.cancel();
    _emergencySub = null;
    emergencyDistanceKm.value = 0.0;
    emergencyDistancesById.value = {
      ...emergencyDistancesById.value,
      requestId: 0.0,
    };

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