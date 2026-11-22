import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/db_models.dart';
import '../services/dynamic_island_service.dart';
import '../services/live_progress_tracker.dart';
import '../theme/app_theme.dart';
import '../utils/status_labels.dart';

class HomeLiveProgressBanner extends StatefulWidget {
  final CustomerProfile? viewerProfile;

  const HomeLiveProgressBanner({super.key, required this.viewerProfile});

  @override
  State<HomeLiveProgressBanner> createState() => _HomeLiveProgressBannerState();
}

class _HomeLiveProgressBannerState extends State<HomeLiveProgressBanner> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker.instance;
  final Set<String> _startedTracking = {};
  final Map<String, ({double? lat, double? lng, String address})>
      _workshopLocations = {};
  final Map<String, double> _initialApptDistanceKm = {};
  final Map<String, double> _initialEmgDistanceKm = {};

  Future<void> _ensureWorkshopGps(Map<String, dynamic> appt) async {
    final id = appt['id'] as String;
    if (_startedTracking.contains(id)) return;
    _startedTracking.add(id);

    final wId = appt['workshop_id'] as String?;
    if (wId == null) return;

    try {
      final w = await _db
          .from('customers')
          .select(
              'workshop_latitude, workshop_longitude, street_name, workshop_address')
          .eq('id', wId)
          .maybeSingle();

      final lat = (w?['workshop_latitude'] as num?)?.toDouble();
      final lng = (w?['workshop_longitude'] as num?)?.toDouble();
      final street = (w?['street_name'] as String?) ?? '';
      final addr = (w?['workshop_address'] as String?) ?? '';
      final fallbackAddr = street.isNotEmpty ? street : addr;

      if (mounted) {
        setState(() {
          _workshopLocations[wId] =
              (lat: lat, lng: lng, address: fallbackAddr);
        });
      }

      if (lat != null &&
          lng != null &&
          appt['status'] == 'accepted' &&
          appt['progress_step'] == 'on_the_way') {
        await _tracker.startTrackingToWorkshop(
          appointmentId: id,
          workshopLat: lat,
          workshopLng: lng,
          workshopUserId: wId,
        );
      }
    } catch (_) {}
  }

  Future<void> _openInGoogleMaps({
    double? lat,
    double? lng,
    String? addressQuery,
  }) async {
    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      );
    } else {
      final q = Uri.encodeComponent((addressQuery ?? 'Amman Jordan').trim());
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  double _computeWorkshopLiveProgress(
    Map<String, dynamic> appt,
    String step,
    ({double? lat, double? lng, String address})? wLoc,
  ) {
    if (step == 'pending') return 0.06;
    if (step == 'on_the_way') {
      // 1) الأولوية لتتبع الـ GPS المباشر من جهاز العميل
      final trackerProg = _tracker.workshopGpsProgress.value;
      if (trackerProg > 0.0) {
        return (0.08 + (trackerProg.clamp(0.0, 1.0) * 0.36)).clamp(0.08, 0.44);
      }
      // 2) احتياطياً نحسبها من إحداثيات القاعدة إذا توفرت
      final double? cLat = (appt['customer_latitude'] as num?)?.toDouble();
      final double? cLng = (appt['customer_longitude'] as num?)?.toDouble();
      final double? wLat = wLoc?.lat;
      final double? wLng = wLoc?.lng;
      if (cLat != null && cLng != null && wLat != null && wLng != null) {
        final dist =
            LiveProgressTracker.distanceKmBetween(cLat, cLng, wLat, wLng);
        final id = appt['id'] as String;
        final initial = _initialApptDistanceKm.putIfAbsent(
          id,
          () => dist < 0.3 ? 1.0 : dist,
        );
        final ratio = (1.0 - (dist / initial)).clamp(0.0, 1.0);
        return (0.08 + (ratio * 0.36)).clamp(0.08, 0.44);
      }
      return 0.14;
    }

    return switch (step) {
      'arrived_at_workshop' => 0.46,
      'diagnosis' => 0.60,
      'repairing' => 0.75,
      'testing' => 0.88,
      'awaiting_payment' => 0.95,
      'completed' => 1.0,
      _ => 0.12,
    };
  }

  ({double progress, double? remainingKm}) _computeEmergencyLiveProgress(
    Map<String, dynamic> e,
    String step,
  ) {
    if (step == 'pending') return (progress: 0.08, remainingKm: null);
    if (step == 'arrived_at_pickup') {
      return (progress: 0.86, remainingKm: 0.0);
    }
    if (step == 'completed') return (progress: 1.0, remainingKm: 0.0);

    if (step == 'on_the_way') {
      final double? provLat = (e['latitude'] as num?)?.toDouble();
      final double? provLng = (e['longitude'] as num?)?.toDouble();
      final double? pickLat = (e['pickup_latitude'] as num?)?.toDouble();
      final double? pickLng = (e['pickup_longitude'] as num?)?.toDouble();

      if (provLat != null &&
          provLng != null &&
          pickLat != null &&
          pickLng != null) {
        final dist = LiveProgressTracker.distanceKmBetween(
          provLat,
          provLng,
          pickLat,
          pickLng,
        );
        final id = e['id'] as String;
        final initial = _initialEmgDistanceKm.putIfAbsent(
          id,
          () => dist < 0.3 ? 1.0 : dist,
        );
        if (dist > initial) {
          _initialEmgDistanceKm[id] = dist;
        }
        final denom = _initialEmgDistanceKm[id] ?? 1.0;
        final ratio = (1.0 - (dist / denom)).clamp(0.0, 1.0);
        final smooth = (0.14 + (ratio * 0.68)).clamp(0.14, 0.82);
        return (
          progress: smooth,
          remainingKm: double.parse(dist.toStringAsFixed(1)),
        );
      }

      final trackerEmg = _tracker.emergencyGpsProgress.value;
      if (trackerEmg > 0.0) {
        return (
          progress: (0.14 + (trackerEmg.clamp(0.0, 1.0) * 0.68)),
          remainingKm: null,
        );
      }
      return (progress: 0.18, remainingKm: null);
    }

    return (progress: 0.12, remainingKm: null);
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.viewerProfile?.id;
    if (uid == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('workshop_appointments')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(10),
      builder: (_, apptSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('mechanic_requests')
              .stream(primaryKey: ['id'])
              .eq('user_id', uid)
              .order('created_at', ascending: false)
              .limit(10),
          builder: (_, emgSnap) {
            final activeAppts = (apptSnap.data ?? [])
                .where((a) =>
                    a['status'] == 'accepted' ||
                    a['status'] == 'reschedule_proposed')
                .toList();
            final activeEmgs = (emgSnap.data ?? [])
                .where((e) =>
                    e['status'] != 'completed' && e['status'] != 'cancelled')
                .toList();

            if (activeAppts.isEmpty && activeEmgs.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                if (activeAppts.isNotEmpty)
                  Builder(builder: (_) {
                    final a = activeAppts.first;
                    final status = (a['status'] as String?) ?? 'pending';
                    final step = (a['progress_step'] as String?) ?? 'pending';
                    final label = StatusLabels.appointment(
                      status,
                      progressStep: step,
                    );

                    _ensureWorkshopGps(a);
                    final wLoc = _workshopLocations[a['workshop_id']];

                    return ListenableBuilder(
                      listenable: Listenable.merge([
                        _tracker.workshopDistanceKm,
                        _tracker.workshopGpsProgress,
                      ]),
                      builder: (_, __) {
                        final km = _tracker.workshopDistanceKm.value;
                        final progress =
                            _computeWorkshopLiveProgress(a, step, wLoc);
                        final statusLine = (step == 'on_the_way' && km != null)
                            ? '$label · متبقي ${km.toStringAsFixed(1)} كم'
                            : label;

                        DynamicIslandService.instance.syncProgress(
                          keyId: 'appt_${a['id']}',
                          title: 'موعد الورشة',
                          statusText: statusLine,
                          progress: progress,
                          etaOrDistance: km != null
                              ? '${km.toStringAsFixed(1)} كم'
                              : '${a['appointment_time'] ?? ""}',
                        );

                        return _progressCard(
                          icon: Icons.build_circle,
                          movingIcon: Icons.directions_car,
                          title: 'موعد الورشة (${a['appointment_date'] ?? ''})',
                          statusText: statusLine,
                          progress: progress,
                          actionLabel:
                              step == 'on_the_way' ? 'تأكيد وصولي للورشة' : null,
                          onAction:
                              step == 'on_the_way' && a['workshop_id'] != null
                                  ? () => _tracker.markWorkshopArrived(
                                        appointmentId: a['id'] as String,
                                        workshopUserId:
                                            a['workshop_id'] as String,
                                      )
                                  : null,
                          onOpenMaps: () => _openInGoogleMaps(
                            lat: wLoc?.lat,
                            lng: wLoc?.lng,
                            addressQuery: wLoc?.address,
                          ),
                        );
                      },
                    );
                  }),
                if (activeEmgs.isNotEmpty)
                  ListenableBuilder(
                    listenable: _tracker.emergencyGpsProgress,
                    builder: (_, __) {
                      final e = activeEmgs.first;
                      final status = (e['status'] as String?) ?? 'pending';
                      final step = (e['progress_step'] as String?) ?? 'pending';
                      final isWinch = e['service_type'] == 'winch';
                      final label = StatusLabels.emergency(
                        status,
                        progressStep: step,
                      );
                      final live = _computeEmergencyLiveProgress(e, step);
                      final statusLine =
                          (step == 'on_the_way' && live.remainingKm != null)
                              ? '$label · متبقي ${live.remainingKm} كم'
                              : label;

                      final double? lat =
                          (e['latitude'] as num?)?.toDouble() ??
                              (e['pickup_latitude'] as num?)?.toDouble();
                      final double? lng =
                          (e['longitude'] as num?)?.toDouble() ??
                              (e['pickup_longitude'] as num?)?.toDouble();

                      DynamicIslandService.instance.syncProgress(
                        keyId: 'emg_${e['id']}',
                        title: isWinch ? 'ونش غيارك' : 'طوارئ غيارك',
                        statusText: statusLine,
                        progress: live.progress,
                        etaOrDistance: live.remainingKm != null
                            ? '${live.remainingKm} كم'
                            : ((e['estimated_time'] as String?) ?? ''),
                      );

                      return _progressCard(
                        icon: isWinch ? Icons.local_shipping : Icons.car_crash,
                        movingIcon:
                            isWinch ? Icons.local_shipping : Icons.build,
                        title:
                            '${isWinch ? 'طلب ونش مباشر' : 'طلب طوارئ مباشر'} (${e['description'] ?? ''})',
                        statusText: statusLine,
                        progress: live.progress,
                        onOpenMaps: () => _openInGoogleMaps(
                          lat: lat,
                          lng: lng,
                          addressQuery: e['dropoff_address'] as String?,
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _progressCard({
    required IconData icon,
    required IconData movingIcon,
    required String title,
    required String statusText,
    required double progress,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onOpenMaps,
  }) {
    final clamped = progress.clamp(0.0, 1.0);
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
              Icon(icon, color: AppColors.orange, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${(clamped * 100).round()}%',
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
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: clamped),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => LayoutBuilder(
              builder: (_, constraints) {
                final width = constraints.maxWidth;
                final markerLeft = ((width - 24) * val).clamp(0.0, width - 24);
                return SizedBox(
                  height: 26,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: val,
                          minHeight: 7,
                          color: AppColors.orange,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Positioned(
                        left: markerLeft,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(
                            movingIcon,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (onOpenMaps != null ||
              (actionLabel != null && onAction != null)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onOpenMaps != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('فتح الموقع على الخريطة',
                        style: TextStyle(fontSize: 12)),
                  ),
                if (actionLabel != null && onAction != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onAction,
                    child:
                        Text(actionLabel, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}