import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dynamic_island_service.dart';
import 'notifications_service.dart';

/// تحليل تاريخ ووقت موعد الورشة (يدعم ص/م و AM/PM ونظام 24 ساعة)
DateTime? parseWorkshopAppointmentDateTime(
  String? dateStr,
  String? timeStr,
) {
  if (dateStr == null || dateStr.trim().isEmpty) return null;
  final dateParts = dateStr.trim().split('-');
  if (dateParts.length != 3) return null;
  final year = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  if (year == null || month == null || day == null) return null;

  int hour = 9;
  int minute = 0;
  final raw = (timeStr ?? '').trim();
  if (raw.isNotEmpty) {
    final isPm = raw.contains('م') || raw.toUpperCase().contains('PM');
    final isAm = raw.contains('ص') || raw.toUpperCase().contains('AM');
    final match = RegExp(r'(\d{1,2})\s*:\s*(\d{2})').firstMatch(raw);
    if (match != null) {
      hour = int.tryParse(match.group(1)!) ?? 9;
      minute = int.tryParse(match.group(2)!) ?? 0;
      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;
    }
  }
  return DateTime(year, month, day, hour, minute);
}

/// هل حان وقت إظهار البروجرس لموعد الورشة؟
/// يظهر فقط قبل الموعد بساعة واحدة، أو إذا بدأ الميكانيكي العمل فعلياً أو أصدر فاتورة أو اقترح موعداً بديلاً
bool isWorkshopProgressWindowActive(Map<String, dynamic> appt) {
  final status = (appt['status'] as String?) ?? 'pending';
  final step = (appt['progress_step'] as String?) ?? 'pending';

  if (status == 'reschedule_proposed') return true;
  if (step == 'arrived_at_workshop' ||
      step == 'diagnosis' ||
      step == 'repairing' ||
      step == 'testing' ||
      step == 'awaiting_payment' ||
      step == 'completed') {
    return true;
  }

  final scheduled = parseWorkshopAppointmentDateTime(
    appt['appointment_date'] as String?,
    appt['appointment_time'] as String?,
  );
  if (scheduled == null) return true;

  final revealAt = scheduled.subtract(const Duration(hours: 1));
  return !DateTime.now().isBefore(revealAt);
}

class LiveProgressTracker {
  LiveProgressTracker._();
  static final LiveProgressTracker instance = LiveProgressTracker._();
  factory LiveProgressTracker() => instance;

  StreamSubscription<Position>? _workshopSub;
  StreamSubscription<Position>? _emergencySub;
  final SupabaseClient _db = Supabase.instance.client;
  final NotificationsService _notifs = NotificationsService.instance;

  final ValueNotifier<double?> workshopDistanceKm =
      ValueNotifier<double?>(null);
  final ValueNotifier<double> workshopGpsProgress =
      ValueNotifier<double>(0.05);
  final ValueNotifier<double?> emergencyDistanceKm =
      ValueNotifier<double?>(null);
  final ValueNotifier<double> emergencyGpsProgress =
      ValueNotifier<double>(0.05);

  final Map<String, double> _initialDistanceKm = {};
  String? _activeWorkshopApptId;
  String? _activeEmergencyReqId;
  DateTime? _lastWorkshopDbSync;
  DateTime? _lastEmergencyDbSync;

  // أقفال لمنع تكرار إشعار الوصول أكثر من مرة
  final Set<String> _arrivedWorkshopIds = {};
  final Set<String> _arrivedEmergencyIds = {};
  bool _markingWorkshop = false;
  bool _markingEmergency = false;

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
    if (_arrivedWorkshopIds.contains(appointmentId)) return;
    if (_activeWorkshopApptId == appointmentId && _workshopSub != null) {
      return;
    }
    _activeWorkshopApptId = appointmentId;
    await _workshopSub?.cancel();

    if (!await _hasPermission()) return;

    void handlePosition(Position pos) async {
      if (_arrivedWorkshopIds.contains(appointmentId) || _markingWorkshop) {
        return;
      }
      final km = distanceKmBetween(
        pos.latitude,
        pos.longitude,
        workshopLat,
        workshopLng,
      );
      final smoothProgress = computeGpsProgress('appt_$appointmentId', km);

      workshopDistanceKm.value = km;
      workshopGpsProgress.value = smoothProgress;

      // مزامنة موقع الزبون بنفس الصف (In-Place Update بدون سجل تاريخي)
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
    if (_arrivedWorkshopIds.contains(appointmentId) || _markingWorkshop) {
      return;
    }
    _markingWorkshop = true;
    _arrivedWorkshopIds.add(appointmentId);

    try {
      await _workshopSub?.cancel();
      _workshopSub = null;
      workshopDistanceKm.value = 0.0;
      workshopGpsProgress.value = 1.0;

      final updated = await _db
          .from('workshop_appointments')
          .update({'progress_step': 'arrived_at_workshop'})
          .eq('id', appointmentId)
          .eq('progress_step', 'on_the_way')
          .select('id');

      if ((updated as List).isNotEmpty) {
        await _notifs.sendNotification(
          targetUserId: workshopUserId,
          title: 'وصل العميل إلى ورشتك 🚗',
          body: 'يمكنك الآن البدء بفحص السيارة وتحديث مراحل الصيانة.',
          type: 'customer_arrived',
          referenceId: appointmentId,
        );
      }
    } catch (_) {
    } finally {
      _markingWorkshop = false;
    }
  }

  /// تتبع الميكانيكي / الونش في طريقه للعميل (بث GPS مستمر + تحديث موقع المزود الحي على الخريطة)
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

    if (!await _hasPermission()) return;

    final providerId = _db.auth.currentUser?.id;

    void handlePosition(Position pos) async {
      if (_arrivedEmergencyIds.contains(requestId) || _markingEmergency) {
        return;
      }
      final km = distanceKmBetween(
        pos.latitude,
        pos.longitude,
        pickupLat,
        pickupLng,
      );
      final smoothProgress = computeGpsProgress('emg_$requestId', km);

      emergencyDistanceKm.value = km;
      emergencyGpsProgress.value = smoothProgress;

      // بث موقع الفني بنفس الصف (In-Place Update بدون سجل تاريخي) ليراه الزبون يتحرك حياً على الخريطة
      final now = DateTime.now();
      if (_lastEmergencyDbSync == null ||
          now.difference(_lastEmergencyDbSync!).inSeconds >= 3) {
        _lastEmergencyDbSync = now;
        try {
          await _db.from('mechanic_requests').update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          }).eq('id', requestId);
        } catch (_) {}
        if (providerId != null) {
          try {
            await _db.from('customers').update({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
            }).eq('id', providerId);
          } catch (_) {}
        }
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
    if (_arrivedEmergencyIds.contains(requestId) || _markingEmergency) {
      return;
    }
    _markingEmergency = true;
    _arrivedEmergencyIds.add(requestId);

    try {
      await _emergencySub?.cancel();
      _emergencySub = null;
      emergencyDistanceKm.value = 0.0;
      emergencyGpsProgress.value = 1.0;

      final updated = await _db
          .from('mechanic_requests')
          .update({'progress_step': 'arrived_at_pickup'})
          .eq('id', requestId)
          .eq('progress_step', 'on_the_way')
          .select('id');

      if ((updated as List).isNotEmpty) {
        final isWinch = serviceType == 'winch';
        await _notifs.sendNotification(
          targetUserId: customerUserId,
          title: isWinch ? 'وصل الونش إلى موقعك 🚚' : 'وصل ميكانيكي الطوارئ 🔧',
          body: isWinch
              ? 'سائق الونش متواجد الآن عند نقطة الالتقاط.'
              : 'الميكانيكي وصل إلى موقع سيارتك الآن.',
          type: isWinch ? 'winch_arrived' : 'mechanic_arrived',
          referenceId: requestId,
        );
      }
    } catch (_) {
    } finally {
      _markingEmergency = false;
    }
  }

  void stop() {
    _workshopSub?.cancel();
    _workshopSub = null;
    _emergencySub?.cancel();
    _emergencySub = null;
    _activeWorkshopApptId = null;
    _activeEmergencyReqId = null;
  }
}