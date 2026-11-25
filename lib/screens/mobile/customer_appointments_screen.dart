import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../services/live_progress_tracker.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/service_rating_dialog.dart';
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
  State<CustomerAppointmentsScreen> createState() =>
      _CustomerAppointmentsScreenState();
}

class _CustomerAppointmentsScreenState
    extends State<CustomerAppointmentsScreen> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker.instance;
  final _notifs = NotificationsService.instance;
  final _loc = AppLocaleService.instance;
  final Set<String> _trackingStartedIds = {};
  final Map<String, ({double? lat, double? lng, String address})>
      _workshopLocs = {};

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  Future<void> _ensureLocationTracking(Map<String, dynamic> appt) async {
    final workshopId = appt['workshop_id'] as String?;
    if (workshopId == null) return;

    final id = appt['id'] as String;
    if (!_workshopLocs.containsKey(workshopId)) {
      try {
        final workshop = await _db
            .from('customers')
            .select(
              'workshop_latitude, workshop_longitude, street_name, workshop_address',
            )
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
      } catch (_) {}
    }

    // لا يبدأ تتبع GPS للورشة إلا قبل الموعد بساعة واحدة فقط
    if (!isWorkshopProgressWindowActive(appt)) return;
    if (_trackingStartedIds.contains(id)) return;
    _trackingStartedIds.add(id);

    final loc = _workshopLocs[workshopId];
    if (appt['status'] == 'accepted' &&
        appt['progress_step'] == 'on_the_way' &&
        loc?.lat != null &&
        loc?.lng != null) {
      await _tracker.startTrackingToWorkshop(
        appointmentId: id,
        workshopLat: loc!.lat!,
        workshopLng: loc.lng!,
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
        title: 'وافق العميل على الموعد البديل ✓',
        body:
            'تم تثبيت الموعد الجديد بتاريخ ${appt['proposed_date']} الساعة ${appt['proposed_time']}.',
        type: 'order_accepted',
        referenceId: appt['id'],
      );
    }
  }

  Future<void> _rejectProposedReschedule(Map<String, dynamic> appt) async {
    final model = DbWorkshopAppointment.fromMap(appt);
    if (model.isInvoiceLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(_loc.tr(
            'ممنوع الإلغاء بعد إصدار الفاتورة',
            'Cancellation disabled after invoice issuance',
          )),
        ),
      );
      return;
    }
    await _db.from('workshop_appointments').update({
      'status': 'cancelled',
      'progress_step': 'cancelled',
    }).eq('id', appt['id']);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return Center(
          child: Text(_loc.tr('يرجى تسجيل الدخول', 'Please sign in')));
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
                Text(
                  _loc.tr('مواعيدي بالورشة', 'My Workshop Appointments'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
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
                        SelectWorkshopScreen(
                            viewerProfile: widget.customerProfile),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_loc.tr('حجز موعد', 'Book Now')),
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
                  return Center(
                    child: Text(
                      _loc.tr(
                        'لا توجد مواعيد ورشة حالياً، اضغط "حجز موعد"',
                        'No workshop appointments yet. Tap "Book Now".',
                      ),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: appointments.length,
                  itemBuilder: (context, index) {
                    final appt = appointments[index];
                    final model = DbWorkshopAppointment.fromMap(appt);
                    _ensureLocationTracking(appt);

                    final status = model.status;
                    final step = model.progressStep;
                    final totalAmount = model.totalAmount;
                    final payStatus = model.paymentStatus;
                    final progressVisible =
                        isWorkshopProgressWindowActive(appt);

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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${appt['appointment_date']} · ${appt['appointment_time']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  _statusBadge(status),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                appt['service_description'] ??
                                    _loc.tr('صيانة مركبة', 'Vehicle Service'),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _loc.tr(
                                          'الورشة ممتلئة، وتقترح موعداً بديلاً:',
                                          'Workshop is full and suggests another slot:',
                                        ),
                                        style: const TextStyle(
                                          color: AppColors.orange,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${appt['proposed_date']} · ${appt['proposed_time']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.success,
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () =>
                                                  _acceptProposedReschedule(
                                                      appt),
                                              child: Text(_loc.tr(
                                                  'قبول الموعد', 'Accept')),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _rejectProposedReschedule(
                                                      appt),
                                              child: Text(
                                                  _loc.tr('رفض', 'Decline')),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // إظهار البروجرس فقط قبل الموعد بساعة (وإلا بطاقة موعد مؤكد قادم)
                              if (status == 'accepted' && !progressVisible) ...[
                                const Divider(height: 22),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.navy.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.navy
                                          .withValues(alpha: 0.16),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.schedule_rounded,
                                          color: AppColors.navy, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _loc.tr(
                                            'تم قبول موعدك! سيظهر شريط التتبع والبروجرس تلقائياً قبل موعدك بساعة واحدة.',
                                            'Appointment confirmed! Live tracking & progress will appear 1 hour before your slot.',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.navy,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (status == 'accepted' ||
                                  status == 'completed') ...[
                                const Divider(height: 22),
                                _buildProgressStepper(
                                    step, appt['workshop_id'] as String?),
                              ],
                              if (showPayments &&
                                  (step == 'awaiting_payment' ||
                                      (status == 'completed' &&
                                          payStatus != 'paid')) &&
                                  totalAmount > 0 &&
                                  payStatus != 'paid') ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        animatedRoute(WorkshopCheckoutScreen(
                                          appointment: model,
                                          customerProfile:
                                              widget.customerProfile,
                                          onPaymentCompleted:
                                              widget.onRefreshProfile,
                                        )),
                                      );
                                    },
                                    child: Text(
                                      _loc.tr(
                                        'السيارة جاهزة! ادفع الفاتورة (${totalAmount.toStringAsFixed(2)} د.أ)',
                                        'Car Ready! Pay Invoice (${totalAmount.toStringAsFixed(2)} JOD)',
                                      ),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                              // زر التقييم بعد انتهاء الطلب والدفع
                              if (status == 'completed' &&
                                  (payStatus == 'paid' || !showPayments) &&
                                  model.workshopId != null) ...[
                                const SizedBox(height: 10),
                                if (model.customerRating == null)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.orange,
                                        side: const BorderSide(
                                            color: AppColors.orange),
                                      ),
                                      onPressed: () => showServiceRatingDialog(
                                        context: context,
                                        serviceKind: 'workshop',
                                        referenceId: model.id,
                                        providerId: model.workshopId!,
                                      ),
                                      icon: const Icon(Icons.star_rounded),
                                      label: Text(_loc.tr(
                                        'قيّم الورشة الآن',
                                        'Rate Workshop Now',
                                      )),
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          color: Colors.amber, size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        _loc.tr(
                                          'تقييمك: ${model.customerRating}/5 نجوم',
                                          'Your rating: ${model.customerRating}/5 stars',
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                    ],
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
                    ? _loc.tr('تم الوصول إلى الورشة (تلقائي عبر GPS)',
                        'Arrived at workshop (GPS)')
                    : _loc.tr('في الطريق إلى الورشة (يتحدث تلقائياً)...',
                        'On the way to workshop (live GPS)...'),
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
            icon: const Icon(Icons.map_outlined,
                color: AppColors.navy, size: 18),
            label: Text(
              _loc.tr('فتح موقع الورشة على Google Maps',
                  'Open Workshop in Google Maps'),
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        if (arrived) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: currentIdx <= 0
                ? 0.2
                : ((currentIdx + 1) / repairSteps.length),
            color: AppColors.orange,
            backgroundColor: AppColors.placeholder,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 6),
          Text(
            _stepLabel(step),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  String _stepLabel(String step) {
    return switch (step) {
      'arrived_at_workshop' =>
        _loc.tr('تم استلام السيارة في الورشة', 'Car received at workshop'),
      'diagnosis' =>
        _loc.tr('المرحلة الحالية: فحص السيارة وتشخيص العطل', 'Step: Diagnosis'),
      'repairing' => _loc.tr('المرحلة الحالية: جاري الإصلاح', 'Step: Repairing'),
      'testing' =>
        _loc.tr('المرحلة الحالية: الفحص والتجربة النهائية', 'Step: Testing'),
      'awaiting_payment' =>
        _loc.tr('السيارة جاهزة للتسليم — بانتظار الدفع', 'Ready for payment'),
      'completed' => _loc.tr('مكتمل وتم التسليم', 'Completed & delivered'),
      _ => _loc.tr('بانتظار التحديث', 'Awaiting update'),
    };
  }

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'accepted' => (_loc.tr('مقبول', 'Accepted'), AppColors.navy),
      'reschedule_proposed' => (
          _loc.tr('موعد مقترح', 'Rescheduled'),
          AppColors.orange
        ),
      'completed' => (_loc.tr('مكتمل', 'Completed'), AppColors.success),
      'cancelled' => (_loc.tr('ملغي', 'Cancelled'), Colors.red),
      _ => (_loc.tr('بانتظار التأكيد', 'Pending'), AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}