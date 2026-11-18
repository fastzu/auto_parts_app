import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notifications_service.dart';

class LiveProgressTracker {
  StreamSubscription<Position>? _sub;
  final SupabaseClient _db = Supabase.instance.client;
  final NotificationsService _notifs = NotificationsService();

  void startTrackingToWorkshop({
    required String appointmentId,
    required double workshopLat,
    required double workshopLng,
    required String workshopUserId,
  }) {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) async {
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        workshopLat,
        workshopLng,
      );
      if (meters <= 150) {
        await _sub?.cancel();
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
    });
  }

  void startTrackingEmergencyArrival({
    required String requestId,
    required String customerUserId,
    required String serviceType,
    required double pickupLat,
    required double pickupLng,
  }) {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) async {
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        pickupLat,
        pickupLng,
      );
      if (meters <= 150) {
        await _sub?.cancel();
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
    });
  }

  void stop() => _sub?.cancel();
}
