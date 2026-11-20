import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/db_models.dart';
import '../services/dynamic_island_service.dart';
import '../services/live_progress_tracker.dart';
import '../theme/app_theme.dart';

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
  final Map<String, ({double? lat, double? lng, String address})> _workshopLocations = {};

  Future<void> _ensureWorkshopGps(Map<String, dynamic> appt) async {
    final id = appt['id'] as String;
    if (_startedTracking.contains(id)) {
      return;
    }
    _startedTracking.add(id);

    final wId = appt['workshop_id'] as String?;
    if (wId == null) {
      return;
    }
    try {
      final w = await _db
          .from('customers')
          .select('workshop_latitude, workshop_longitude, street_name, workshop_address')
          .eq('id', wId)
          .maybeSingle();

      final lat = (w?['workshop_latitude'] as num?)?.toDouble();
      final lng = (w?['workshop_longitude'] as num?)?.toDouble();
      final street = (w?['street_name'] as String?) ?? '';
      final addr = (w?['workshop_address'] as String?) ?? '';
      final fallbackAddr = street.isNotEmpty ? street : addr;

      if (mounted) {
        setState(() {
          _workshopLocations[wId] = (lat: lat, lng: lng, address: fallbackAddr);
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

  Future<void> _openInGoogleMaps({double? lat, double? lng, String? addressQuery}) async {
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

  double _workshopProgressValue(String step) {
    return switch (step) {
      'pending' => 0.10,
      'on_the_way' => 0.25,
      'arrived_at_workshop' => 0.42,
      'diagnosis' => 0.58,
      'repairing' => 0.74,
      'testing' => 0.88,
      'awaiting_payment' => 0.95,
      'completed' => 1.0,
      _ => 0.15,
    };
  }

  String _workshopStepLabel(String step) {
    return switch (step) {
      'on_the_way' => 'في الطريق إلى الورشة (GPS)',
      'arrived_at_workshop' => 'تم الوصول للورشة ✓',
      'diagnosis' => 'فحص السيارة وتشخيص العطل',
      'repairing' => 'جاري الإصلاح في الورشة',
      'testing' => 'الفحص والتجربة النهائية',
      'awaiting_payment' => 'السيارة جاهزة للتسليم',
      'completed' => 'مكتمل وتم التسليم ✓',
      _ => 'بانتظار تأكيد الورشة',
    };
  }

  double _emergencyProgressValue(String step) {
    return switch (step) {
      'pending' => 0.20,
      'on_the_way' => 0.55,
      'arrived_at_pickup' => 0.85,
      'completed' => 1.0,
      _ => 0.20,
    };
  }

  String _emergencyStepLabel(String step) {
    return switch (step) {
      'pending' => 'جاري البحث عن أقرب فني طوارئ...',
      'on_the_way' => 'الميكانيكي في طريقه إلى موقعك',
      'arrived_at_pickup' => 'وصل الميكانيكي إلى موقعك ✓',
      'completed' => 'تم إنهاء المساعدة الطارئة ✓',
      _ => 'قيد المتابعة',
    };
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
          .order('created_at', ascending: false),
      builder: (_, apptSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('mechanic_requests')
              .stream(primaryKey: ['id'])
              .eq('user_id', uid)
              .order('created_at', ascending: false),
          builder: (_, emgSnap) {
            final activeAppts = (apptSnap.data ?? [])
                .where((a) =>
                    a['status'] == 'accepted' || a['status'] == 'reschedule_proposed')
                .toList();
            final activeEmgs = (emgSnap.data ?? [])
                .where((e) => e['status'] != 'completed' && e['status'] != 'cancelled')
                .toList();

            if (activeAppts.isEmpty && activeEmgs.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                if (activeAppts.isNotEmpty)
                  Builder(builder: (_) {
                    final a = activeAppts.first;
                    final step = (a['progress_step'] as String?) ?? 'pending';
                    final progress = _workshopProgressValue(step);
                    final label = a['status'] == 'reschedule_proposed'
                        ? 'اقترحت الورشة موعداً بديلاً'
                        : _workshopStepLabel(step);

                    _ensureWorkshopGps(a);
                    final wLoc = _workshopLocations[a['workshop_id']];

                    DynamicIslandService.instance.syncProgress(
                      keyId: 'appt_${a['id']}',
                      title: 'صيانة الورشة',
                      statusText: label,
                      progress: progress,
                      etaOrDistance: '${a['appointment_time'] ?? ""}',
                    );

                    return ValueListenableBuilder<double?>(
                      valueListenable: _tracker.workshopDistanceKm,
                      builder: (_, km, __) {
                        return _progressCard(
                          icon: Icons.build_circle,
                          title: 'حالة موعد الورشة (${a['appointment_date']})',
                          statusText: (step == 'on_the_way' && km != null)
                              ? '$label · متبقي $km كم'
                              : label,
                          progress: progress,
                          actionLabel: step == 'on_the_way' ? 'تأكيد وصولي للورشة' : null,
                          onAction: step == 'on_the_way' && a['workshop_id'] != null
                              ? () => _tracker.markWorkshopArrived(
                                    appointmentId: a['id'],
                                    workshopUserId: a['workshop_id'],
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
                  Builder(builder: (_) {
                    final e = activeEmgs.first;
                    final step = (e['progress_step'] as String?) ?? 'pending';
                    final progress = _emergencyProgressValue(step);
                    final label = _emergencyStepLabel(step);
                    final lat = (e['pickup_latitude'] as num?)?.toDouble();
                    final lng = (e['pickup_longitude'] as num?)?.toDouble();

                    DynamicIslandService.instance.syncProgress(
                      keyId: 'emg_${e['id']}',
                      title: 'طوارئ غيارك',
                      statusText: label,
                      progress: progress,
                      etaOrDistance: (e['estimated_time'] as String?) ?? '',
                    );

                    return _progressCard(
                      icon: Icons.car_crash,
                      title: 'طلب الطوارئ المباشر (${e['description'] ?? ""})',
                      statusText: label,
                      progress: progress,
                      onOpenMaps: () => _openInGoogleMaps(
                        lat: lat,
                        lng: lng,
                        addressQuery: e['dropoff_address'] as String?,
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _progressCard({
    required IconData icon,
    required String title,
    required String statusText,
    required double progress,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onOpenMaps,
  }) {
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
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(statusText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: val,
                minHeight: 7,
                color: AppColors.orange,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
          if (onOpenMaps != null || (actionLabel != null && onAction != null)) ...[
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('فتح الموقع على Google Maps', style: TextStyle(fontSize: 12)),
                  ),
                if (actionLabel != null && onAction != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onAction,
                    child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}