import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/live_progress_tracker.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'book_workshop_screen.dart';
import 'workshop_checkout_screen.dart';

class CustomerAppointmentsScreen extends StatefulWidget {
  final CustomerProfile customerProfile;
  final VoidCallback onRefreshProfile;

  const CustomerAppointmentsScreen({
    super.key,
    required this.customerProfile,
    required this.onRefreshProfile,
  });

  @override
  State<CustomerAppointmentsScreen> createState() => _CustomerAppointmentsScreenState();
}

class _CustomerAppointmentsScreenState extends State<CustomerAppointmentsScreen> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker.instance;
  final _notifs = NotificationsService();
  final Set<String> _trackingStartedIds = {};
  final Map<String, ({double? lat, double? lng, String address})> _workshopLocs = {};

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  Future<void> _ensureLocationTracking(Map<String, dynamic> appt) async {
    final id = appt['id'] as String;
    if (_trackingStartedIds.contains(id)) {
      return;
    }
    _trackingStartedIds.add(id);

    final workshopId = appt['workshop_id'] as String?;
    if (workshopId == null) {
      return;
    }

    final workshop = await _db
        .from('customers')
        .select('workshop_latitude, workshop_longitude, street_name, workshop_address')
        .eq('id', workshopId)
        .maybeSingle();

    final lat = (workshop?['workshop_latitude'] as num?)?.toDouble();
    final lng = (workshop?['workshop_longitude'] as num?)?.toDouble();
    final street = (workshop?['street_name'] as String?) ?? '';
    final addr = (workshop?['workshop_address'] as String?) ?? '';

    if (mounted) {
      setState(() {
        _workshopLocs[workshopId] = (
          lat: lat,
          lng: lng,
          address: street.isNotEmpty ? street : addr,
        );
      });
    }

    if (appt['status'] == 'accepted' &&
        appt['progress_step'] == 'on_the_way' &&
        lat != null &&
        lng != null) {
      await _tracker.startTrackingToWorkshop(
        appointmentId: id,
        workshopLat: lat,
        workshopLng: lng,
        workshopUserId: workshopId,
      );
    }
  }

  Future<void> _openWorkshopMaps(String? workshopId) async {
    final loc = workshopId != null ? _workshopLocs[workshopId] : null;
    Uri uri;
    if (loc?.lat != null && loc?.lng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${loc!.lat},${loc.lng}&travelmode=driving',
      );
    } else {
      final q = Uri.encodeComponent((loc?.address ?? 'Amman Jordan').trim());
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _acceptProposedReschedule(Map<String, dynamic> appt) async {
    await _db.from('workshop_appointments').update({
      'appointment_date': appt['proposed_date'],
      'appointment_time': appt['proposed_time'],
      'status': 'accepted',
      'progress_step': 'on_the_way',
    }).eq('id', appt['id']);

    if (appt['workshop_id'] != null) {
      await _notifs.sendNotification(
        targetUserId: appt['workshop_id'],
        title: 'وافق العميل على الموعد البديل',
        body:
            'تم تثبيت الموعد الجديد بتاريخ ${appt['proposed_date']} الساعة ${appt['proposed_time']}.',
        type: 'order_accepted',
        referenceId: appt['id'],
      );
    }
  }

  Future<void> _rejectProposedReschedule(Map<String, dynamic> appt) async {
    await _db.from('workshop_appointments').update({
      'status': 'cancelled',
      'progress_step': 'cancelled',
    }).eq('id', appt['id']);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return const Center(child: Text('يرجى تسجيل الدخول'));
    }

    final showPayments = EnvConfig.paymentsEnabled.value;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'مواعيدي بالورشة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      animatedRoute(
                        SelectWorkshopScreen(viewerProfile: widget.customerProfile),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('حجز موعد'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _db
                  .from('workshop_appointments')
                  .stream(primaryKey: ['id'])
                  .eq('user_id', uid)
                  .order('created_at', ascending: false),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final appointments = snap.data!;

                if (appointments.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا توجد مواعيد ورشة حالياً، اضغط "حجز موعد"',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: appointments.length,
                  itemBuilder: (context, index) {
                    final appt = appointments[index];
                    _ensureLocationTracking(appt);

                    final status = appt['status'] as String? ?? 'pending';
                    final step = appt['progress_step'] as String? ?? 'pending';
                    final totalAmount = (appt['total_amount'] as num?)?.toDouble() ?? 0.0;

                    return FadeSlideIn(
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${appt['appointment_date']} · ${appt['appointment_time']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  _statusBadge(status),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                appt['service_description'] ?? 'صيانة مركبة',
                                style: const TextStyle(
                                    color: AppColors.textSecondary, fontSize: 13),
                              ),
                              if (status == 'reschedule_proposed') ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.orangeLight,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.orange),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'الورشة ممتلئة، وتقترح موعداً بديلاً:',
                                        style: TextStyle(
                                          color: AppColors.orange,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${appt['proposed_date']} الساعة ${appt['proposed_time']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.success,
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () => _acceptProposedReschedule(appt),
                                              child: const Text('قبول الموعد'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _rejectProposedReschedule(appt),
                                              child: const Text('رفض'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (status == 'accepted' || status == 'completed') ...[
                                const Divider(height: 22),
                                _buildProgressStepper(step, appt['workshop_id'] as String?),
                              ],
                              if (showPayments &&
                                  step == 'awaiting_payment' &&
                                  totalAmount > 0) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        animatedRoute(WorkshopCheckoutScreen(
                                          appointment: DbWorkshopAppointment.fromMap(appt),
                                          customerProfile: widget.customerProfile,
                                          onPaymentCompleted: widget.onRefreshProfile,
                                        )),
                                      );
                                    },
                                    child: Text(
                                      'السيارة جاهزة! ادفع الفاتورة (${totalAmount.toStringAsFixed(2)} د.أ)',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ] else if (!showPayments &&
                                  (step == 'awaiting_payment' || step == 'completed')) ...[
                                const SizedBox(height: 10),
                                const Chip(
                                  backgroundColor: AppColors.surface,
                                  label: Text(
                                    'السيارة جاهزة للتسليم من الورشة ✓',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStepper(String step, String? workshopId) {
    final arrived = step != 'pending' && step != 'on_the_way';
    final repairSteps = [
      'arrived_at_workshop',
      'diagnosis',
      'repairing',
      'testing',
      'awaiting_payment',
      'completed'
    ];
    final currentIdx = repairSteps.indexOf(step);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              arrived ? Icons.check_circle : Icons.directions_car,
              color: arrived ? AppColors.success : AppColors.orange,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                arrived
                    ? 'تم الوصول إلى الورشة (تلقائي عبر GPS)'
                    : 'في الطريق إلى الورشة (يتحدث تلقائياً)...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: arrived ? AppColors.success : AppColors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.navy),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () => _openWorkshopMaps(workshopId),
            icon: const Icon(Icons.map_outlined, color: AppColors.navy, size: 18),
            label: const Text(
              'فتح موقع الورشة على Google Maps',
              style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
        if (arrived) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: currentIdx <= 0 ? 0.2 : ((currentIdx + 1) / repairSteps.length),
            color: AppColors.orange,
            backgroundColor: AppColors.placeholder,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 6),
          Text(
            _stepArabicLabel(step),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  String _stepArabicLabel(String step) {
    return switch (step) {
      'arrived_at_workshop' => 'تم استلام السيارة في الورشة',
      'diagnosis' => 'المرحلة الحالية: فحص السيارة وتشخيص العطل',
      'repairing' => 'المرحلة الحالية: جاري الإصلاح',
      'testing' => 'المرحلة الحالية: الفحص والتجربة النهائية',
      'awaiting_payment' => 'السيارة جاهزة للتسليم',
      'completed' => 'مكتمل وتم التسليم',
      _ => 'بانتظار التحديث',
    };
  }

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'accepted' => ('مقبول', AppColors.navy),
      'reschedule_proposed' => ('موعد مقترح', AppColors.orange),
      'completed' => ('مكتمل', AppColors.success),
      'cancelled' => ('ملغي', Colors.red),
      _ => ('بانتظار التأكيد', AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}