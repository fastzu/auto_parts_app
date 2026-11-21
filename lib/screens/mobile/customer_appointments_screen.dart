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
  final Map<String, ({double? lat, double? lng, String address, String? phone})> _workshopLocs = {};
  bool _showHistory = false;

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

    try {
      final workshop = await _db
          .from('customers')
          .select('workshop_latitude, workshop_longitude, street_name, workshop_address, phone')
          .eq('id', workshopId)
          .maybeSingle();

      final lat = (workshop?['workshop_latitude'] as num?)?.toDouble();
      final lng = (workshop?['workshop_longitude'] as num?)?.toDouble();
      final street = (workshop?['street_name'] as String?) ?? '';
      final addr = (workshop?['workshop_address'] as String?) ?? '';
      final phone = workshop?['phone'] as String?;

      if (mounted) {
        setState(() {
          _workshopLocs[workshopId] = (
            lat: lat,
            lng: lng,
            address: street.isNotEmpty ? street : addr,
            phone: phone,
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
    } catch (_) {}
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

  Future<void> _callWorkshop(String? workshopId) async {
    final raw = workshopId != null ? _workshopLocs[workshopId]?.phone : null;
    final cleaned = (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم هاتف الورشة غير متوفر')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: cleaned), mode: LaunchMode.externalApplication);
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

  bool _isHistoryAppt(Map<String, dynamic> a) {
    final status = (a['status'] as String?) ?? '';
    final step = (a['progress_step'] as String?) ?? '';
    return status == 'completed' || status == 'cancelled' || step == 'completed';
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return const Center(child: Text('يرجى تسجيل الدخول'));
    }

    final showPayments = EnvConfig.paymentsEnabled.value;

    return SafeArea(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db
            .from('workshop_appointments')
            .stream(primaryKey: ['id'])
            .eq('user_id', uid)
            .order('created_at', ascending: false),
        builder: (context, snap) {
          final allAppointments = snap.data ?? [];
          final activeAppointments = allAppointments.where((a) => !_isHistoryAppt(a)).toList();
          final historyAppointments = allAppointments.where(_isHistoryAppt).toList();
          final displayed = _showHistory ? historyAppointments : activeAppointments;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      _segTab(
                        'المواعيد الحالية (${activeAppointments.length})',
                        !_showHistory,
                        () => setState(() => _showHistory = false),
                      ),
                      _segTab(
                        'السجل / الهيستوري (${historyAppointments.length})',
                        _showHistory,
                        () => setState(() => _showHistory = true),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: !snap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : displayed.isEmpty
                        ? Center(
                            child: Text(
                              _showHistory
                                  ? 'لا توجد مواعيد منتهية في السجل حالياً'
                                  : 'لا توجد مواعيد ورشة نشطة حالياً، اضغط "حجز موعد"',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: displayed.length,
                            itemBuilder: (context, index) {
                              final appt = displayed[index];
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
                                            Expanded(
                                              child: Text(
                                                '${appt['appointment_date']} · ${appt['appointment_time']}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
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
                                                        onPressed: () =>
                                                            _acceptProposedReschedule(appt),
                                                        child: const Text('قبول الموعد'),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: OutlinedButton(
                                                        onPressed: () =>
                                                            _rejectProposedReschedule(appt),
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
                                          _buildProgressStepper(
                                            appt['id'] as String,
                                            step,
                                            appt['workshop_id'] as String?,
                                          ),
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
                                                    appointment:
                                                        DbWorkshopAppointment.fromMap(appt),
                                                    customerProfile: widget.customerProfile,
                                                    onPaymentCompleted: widget.onRefreshProfile,
                                                  )),
                                                );
                                              },
                                              child: Text(
                                                'السيارة جاهزة! ادفع الفاتورة (${totalAmount.toStringAsFixed(2)} د.أ)',
                                                style:
                                                    const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                        ] else if (!showPayments &&
                                            (step == 'awaiting_payment' ||
                                                step == 'completed')) ...[
                                          const SizedBox(height: 10),
                                          Chip(
                                            backgroundColor:
                                                AppColors.success.withValues(alpha: 0.1),
                                            label: Text(
                                              step == 'completed'
                                                  ? 'تم الانتهاء وتسليم السيارة ✓'
                                                  : 'السيارة جاهزة للتسليم من الورشة ✓',
                                              style: const TextStyle(
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
                          ),
              ),
            ],
          );
        },
      ),
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
            color: selected ? AppColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStepper(String apptId, String step, String? workshopId) {
    final arrived = step != 'pending' && step != 'on_the_way';
    final isMoving = step == 'on_the_way';
    final repairSteps = [
      'arrived_at_workshop',
      'diagnosis',
      'repairing',
      'testing',
      'awaiting_payment',
      'completed'
    ];
    final currentIdx = repairSteps.indexOf(step);
    final hasPhone = (workshopId != null && (_workshopLocs[workshopId]?.phone ?? '').trim().isNotEmpty);

    return ValueListenableBuilder<double?>(
      valueListenable: _tracker.workshopDistanceKm,
      builder: (_, km, __) {
        final gpsProgress = arrived
            ? 1.0
            : (km != null ? _tracker.computeGpsProgress('appt_$apptId', km) : 0.25);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMoving || step == 'arrived_at_workshop') ...[
              GpsCarProgressTrack(
                progress: gpsProgress,
                isWinch: false,
                isArrived: arrived,
                trackColor: AppColors.placeholder,
                activeColor: AppColors.orange,
                labelColor: AppColors.textSecondary,
                startLabel: 'موقعك',
                endLabel: 'الورشة',
                distanceLabel: arrived
                    ? 'تم الوصول إلى الورشة ✓'
                    : (km != null ? 'متبقي $km كم' : 'في الطريق إلى الورشة (GPS)...'),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'تم الوصول إلى الورشة ✓',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.navy),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                  onPressed: () => _openWorkshopMaps(workshopId),
                  icon: const Icon(Icons.map_outlined, color: AppColors.navy, size: 17),
                  label: const Text(
                    'موقع الورشة على الخريطة',
                    style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                if (hasPhone)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    ),
                    onPressed: () => _callWorkshop(workshopId),
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('اتصال بالورشة', style: TextStyle(fontSize: 12)),
                  ),
                if (isMoving && workshopId != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    ),
                    onPressed: () => _tracker.markWorkshopArrived(
                      appointmentId: apptId,
                      workshopUserId: workshopId,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('تأكيد وصولي', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            if (arrived) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: currentIdx <= 0 ? 0.2 : ((currentIdx + 1) / repairSteps.length),
                color: step == 'completed' ? AppColors.success : AppColors.orange,
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
      },
    );
  }

  String _stepArabicLabel(String step) {
    return switch (step) {
      'arrived_at_workshop' => 'تم استلام السيارة في الورشة',
      'diagnosis' => 'المرحلة الحالية: فحص السيارة وتشخيص العطل',
      'repairing' => 'المرحلة الحالية: جاري الإصلاح',
      'testing' => 'المرحلة الحالية: الفحص والتجربة النهائية',
      'awaiting_payment' => 'السيارة جاهزة للتسليم',
      'completed' => 'مكتمل وتم التسليم ✓',
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