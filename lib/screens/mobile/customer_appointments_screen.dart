import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/live_progress_tracker.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/status_labels.dart';
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
  State<CustomerAppointmentsScreen> createState() =>
      _CustomerAppointmentsScreenState();
}

class _CustomerAppointmentsScreenState
    extends State<CustomerAppointmentsScreen> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker.instance;
  final Set<String> _trackingStartedIds = {};
  final Set<String> _cancellingIds = {};
  final Map<String, ({double? lat, double? lng, String address})>
      _workshopLocs = {};

  Stream<List<Map<String, dynamic>>>? _appointmentsStream;
  String? _streamUid;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || uid == _streamUid) return;
    _streamUid = uid;
    _appointmentsStream = _db
        .from('workshop_appointments')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(50);
  }

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  void _showTopToast(String title, String message, {bool isError = false}) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFDC2626) : AppColors.success,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }

  Future<void> _ensureLocationTracking(Map<String, dynamic> appt) async {
    final id = appt['id'] as String;
    if (_trackingStartedIds.contains(id)) return;
    _trackingStartedIds.add(id);

    final workshopId = appt['workshop_id'] as String?;
    if (workshopId == null) return;

    try {
      final workshop = await _db
          .from('customers')
          .select(
              'workshop_latitude, workshop_longitude, latitude, longitude, street_name, workshop_address')
          .eq('id', workshopId)
          .maybeSingle();

      final lat = (workshop?['workshop_latitude'] as num?)?.toDouble() ??
          (workshop?['latitude'] as num?)?.toDouble();
      final lng = (workshop?['workshop_longitude'] as num?)?.toDouble() ??
          (workshop?['longitude'] as num?)?.toDouble();
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

  Future<void> _acceptProposedReschedule(Map<String, dynamic> appt) async {
    try {
      await _db.from('workshop_appointments').update({
        'appointment_date': appt['proposed_date'],
        'appointment_time': appt['proposed_time'],
        'status': 'accepted',
        'progress_step': 'on_the_way',
      }).eq('id', appt['id']);

      if (appt['workshop_id'] != null) {
        await NotificationsService.instance.sendNotification(
          targetUserId: appt['workshop_id'] as String,
          title: 'وافق العميل على الموعد البديل',
          body:
              'تم تثبيت الموعد الجديد بتاريخ ${appt['proposed_date']} الساعة ${appt['proposed_time']}.',
          type: 'order_accepted',
          referenceId: appt['id'] as String?,
        );
      }
      _showTopToast('تم التثبيت', 'تم قبول الموعد البديل وتفعيله بنجاح.');
    } catch (e) {
      _showTopToast('تعذر التحديث', '$e', isError: true);
    }
  }

  Future<void> _cancelAppointment(Map<String, dynamic> appt) async {
    final id = appt['id'] as String;
    if (_cancellingIds.contains(id)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إلغاء حجز الورشة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل أنت متأكد من إلغاء هذا الحجز؟ سيتم إشعار الورشة بالإلغاء فوراً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء الحجز'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _cancellingIds.add(id));
    try {
      await _db.from('workshop_appointments').update({
        'status': 'cancelled',
        'progress_step': 'cancelled',
      }).eq('id', id);

      _tracker.stop();

      final workshopId = appt['workshop_id'] as String?;
      if (workshopId != null && workshopId.isNotEmpty) {
        await NotificationsService.instance.sendNotification(
          targetUserId: workshopId,
          title: 'تم إلغاء حجز موعد',
          body:
              'قام العميل بإلغاء الموعد بتاريخ ${appt['appointment_date'] ?? ''} الساعة ${appt['appointment_time'] ?? ''}.',
          type: 'order_cancelled',
          referenceId: id,
        );
      }

      _showTopToast('تم إلغاء الحجز', 'تم إلغاء موعد الورشة بنجاح.');
    } catch (e) {
      _showTopToast('تعذر إلغاء الحجز', '$e', isError: true);
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return const Center(child: Text('يرجى تسجيل الدخول'));
    }
    _initStream();

    return ValueListenableBuilder<bool>(
      valueListenable: EnvConfig.paymentsEnabled,
      builder: (context, showPayments, _) {
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
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                      label: const Text('حجز موعد'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _appointmentsStream,
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
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: appointments.length,
                      itemBuilder: (context, index) {
                        final appt = appointments[index];
                        _ensureLocationTracking(appt);

                        final id = appt['id'] as String;
                        final status = appt['status'] as String? ?? 'pending';
                        final step =
                            appt['progress_step'] as String? ?? 'pending';
                        final payStatus =
                            (appt['payment_status'] as String?) ?? 'unpaid';
                        final totalAmount =
                            (appt['total_amount'] as num?)?.toDouble() ?? 0.0;
                        final discountCode =
                            (appt['discount_code'] as String?) ?? '';
                        final discountAmount =
                            (appt['discount_amount'] as num?)?.toDouble() ??
                                0.0;

                        final canCancel = (status == 'pending' ||
                                status == 'accepted' ||
                                status == 'reschedule_proposed') &&
                            payStatus != 'paid';

                        final canPay = showPayments &&
                            (step == 'awaiting_payment' ||
                                status == 'completed') &&
                            payStatus != 'paid' &&
                            totalAmount > 0;

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
                                      Expanded(
                                        child: Text(
                                          '${appt['appointment_date'] ?? ''} · ${appt['appointment_time'] ?? ''}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      _statusBadge(status, step),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (appt['service_description'] as String?) ??
                                        'صيانة مركبة',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (discountCode.isNotEmpty &&
                                      discountAmount > 0) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'خصم مطبّق ($discountCode): -${discountAmount.toStringAsFixed(2)} د.أ',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  if (status == 'reschedule_proposed') ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.orangeLight,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppColors.orange),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ElevatedButton(
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppColors.success,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                  onPressed: () =>
                                                      _acceptProposedReschedule(
                                                          appt),
                                                  child:
                                                      const Text('قبول الموعد'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () =>
                                                      _cancelAppointment(appt),
                                                  child: const Text('رفض وإلغاء'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (status == 'accepted' ||
                                      status == 'completed') ...[
                                    const Divider(height: 22),
                                    _buildProgressStepper(
                                      apptId: id,
                                      status: status,
                                      step: step,
                                      workshopId:
                                          appt['workshop_id'] as String?,
                                    ),
                                  ],
                                  if (canPay) ...[
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
                                            animatedRoute(
                                              WorkshopCheckoutScreen(
                                                appointment:
                                                    DbWorkshopAppointment
                                                        .fromMap(appt),
                                                customerProfile:
                                                    widget.customerProfile,
                                                onPaymentCompleted:
                                                    widget.onRefreshProfile,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          'السيارة جاهزة! ادفع الفاتورة (${totalAmount.toStringAsFixed(2)} د.أ)',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ] else if (!showPayments &&
                                      (step == 'awaiting_payment' ||
                                          step == 'completed')) ...[
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

                                  // زر إلغاء الحجز لأي موعد نشط قبل الاكتمال والدفع
                                  if (canCancel &&
                                      status != 'reschedule_proposed') ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: BorderSide(
                                            color: Colors.red
                                                .withValues(alpha: 0.55),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                        ),
                                        onPressed: _cancellingIds.contains(id)
                                            ? null
                                            : () => _cancelAppointment(appt),
                                        icon: _cancellingIds.contains(id)
                                            ? const SizedBox(
                                                width: 15,
                                                height: 15,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.red,
                                                ),
                                              )
                                            : const Icon(Icons.cancel_outlined,
                                                size: 17),
                                        label: const Text(
                                          'إلغاء الحجز',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
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
      },
    );
  }

  Widget _buildProgressStepper({
    required String apptId,
    required String status,
    required String step,
    required String? workshopId,
  }) {
    final arrived = step != 'pending' && step != 'on_the_way';
    final pureArabicLabel =
        StatusLabels.appointment(status, progressStep: step);

    final double postArrivalProgress = switch (step) {
      'arrived_at_workshop' => 0.48,
      'diagnosis' => 0.62,
      'repairing' => 0.76,
      'testing' => 0.88,
      'awaiting_payment' => 0.95,
      'completed' => 1.0,
      _ => 0.45,
    };

    return ListenableBuilder(
      listenable: Listenable.merge([
        _tracker.workshopGpsProgress,
        _tracker.workshopDistanceKm,
      ]),
      builder: (_, __) {
        final km = _tracker.workshopDistanceKm.value;
        // عندما يكون في الطريق: يتحرك الشريط بسلاسة من 8% إلى 44% حسب المسافة الفعلية بالـ GPS
        final double liveProgress = arrived
            ? postArrivalProgress
            : (0.08 +
                (_tracker.workshopGpsProgress.value.clamp(0.0, 1.0) * 0.36));

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
                    (!arrived && km != null)
                        ? '$pureArabicLabel · متبقي ${km.toStringAsFixed(1)} كم'
                        : pureArabicLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: arrived ? AppColors.success : AppColors.orange,
                    ),
                  ),
                ),
                Text(
                  '${(liveProgress * 100).round()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: liveProgress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, val, __) {
                return LayoutBuilder(
                  builder: (_, constraints) {
                    final barW = constraints.maxWidth;
                    const thumbSize = 24.0;
                    final carStart = (barW - thumbSize) * val;
                    return SizedBox(
                      height: 28,
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          Container(
                            height: 7,
                            width: barW,
                            decoration: BoxDecoration(
                              color: AppColors.placeholder,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          PositionedDirectional(
                            start: 0,
                            child: Container(
                              height: 7,
                              width: barW * val,
                              decoration: BoxDecoration(
                                color: AppColors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            start: carStart.clamp(0.0, barW - thumbSize),
                            child: Container(
                              width: thumbSize,
                              height: thumbSize,
                              decoration: const BoxDecoration(
                                color: AppColors.navy,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                arrived
                                    ? Icons.build_circle
                                    : Icons.directions_car,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.navy),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _openWorkshopMaps(workshopId),
                    icon: const Icon(Icons.map_outlined,
                        color: AppColors.navy, size: 18),
                    label: const Text(
                      'موقع الورشة',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (!arrived && workshopId != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _tracker.markWorkshopArrived(
                        appointmentId: apptId,
                        workshopUserId: workshopId,
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text(
                        'وصلت للورشة',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _statusBadge(String status, String step) {
    final label = StatusLabels.appointment(status, progressStep: step);
    final color = StatusLabels.colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}