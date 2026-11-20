import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'chat_screen.dart';

String formatWorkshopStreet(CustomerProfile w) {
  final rawStreet = (w.streetName ?? '').trim();
  final rawBuilding = (w.buildingNumber ?? '').trim();
  final parts = <String>[];
  if (rawStreet.isNotEmpty) {
    parts.add(rawStreet.startsWith('شارع') ? rawStreet : 'شارع $rawStreet');
  }
  if (rawBuilding.isNotEmpty) {
    parts.add(rawBuilding.startsWith('مبنى') ? rawBuilding : 'مبنى $rawBuilding');
  }
  if (parts.isNotEmpty) {
    return parts.join(' · ');
  }
  return (w.workshopAddress ?? '').trim().isNotEmpty
      ? w.workshopAddress!
      : 'العنوان غير محدد';
}

class SelectWorkshopScreen extends StatelessWidget {
  final CustomerProfile? viewerProfile;
  const SelectWorkshopScreen({super.key, this.viewerProfile});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار ورشة وموعد')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.from('customers').select().eq('role', 'mechanic'),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final workshops = snap.data!.map(CustomerProfile.fromMap).toList();
          if (workshops.isEmpty) {
            return const Center(child: Text('لا توجد ورش مسجلة حالياً'));
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: workshops.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final w = workshops[i];
                  final streetAddress = formatWorkshopStreet(w);

                  final badge = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: w.isAvailable ? AppColors.success : Colors.red,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          w.isAvailable ? 'متاح الآن' : 'غير متاح',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );

                  return FadeSlideIn(
                    index: i,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Stack(
                            children: [
                              SizedBox(
                                height: 165,
                                width: double.infinity,
                                child: (w.workshopImageUrl ?? '').isNotEmpty
                                    ? Image.network(
                                        w.workshopImageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                                      )
                                    : _imagePlaceholder(),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.15),
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.35),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: w.isAvailable ? PulseBlink(child: badge) : badge,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              w.fullName ?? 'ورشة صيانة',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 17,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (w.isTrustedMerchant) ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.verified, color: Colors.blue, size: 18),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.phone_outlined,
                                              size: 14, color: AppColors.orange),
                                          const SizedBox(width: 5),
                                          Text(
                                            w.phone ?? '-',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: AppColors.navy,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_outlined,
                                        size: 16, color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        streetAddress,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 22),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: BounceTap(
                                        onTap: () {
                                          if (!w.isAvailable) {
                                            return;
                                          }
                                          if (viewerProfile == null) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('يرجى تسجيل الدخول أولاً لحجز موعد'),
                                              ),
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            animatedRoute(BookWorkshopScreen(workshop: w)),
                                          );
                                        },
                                        child: Container(
                                          height: 46,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: w.isAvailable
                                                ? AppColors.orange
                                                : AppColors.placeholder,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.calendar_today_outlined,
                                                size: 17,
                                                color: w.isAvailable
                                                    ? Colors.white
                                                    : AppColors.textSecondary,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                w.isAvailable ? 'حجز موعد' : 'الورشة غير متاحة',
                                                style: TextStyle(
                                                  color: w.isAvailable
                                                      ? Colors.white
                                                      : AppColors.textSecondary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 1,
                                      child: BounceTap(
                                        onTap: () {
                                          if (viewerProfile == null) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('يرجى تسجيل الدخول أولاً للدردشة'),
                                              ),
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            animatedRoute(ChatConversationScreen(
                                              otherUserId: w.id,
                                              otherUserName: w.fullName ?? 'الورشة',
                                              otherUserPhone: w.phone,
                                            )),
                                          );
                                        },
                                        child: Container(
                                          height: 46,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppColors.navy,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.chat_bubble_outline,
                                                  size: 16, color: Colors.white),
                                              SizedBox(width: 6),
                                              Text(
                                                'دردشة',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AppColors.placeholder,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.build_circle_outlined, size: 42, color: AppColors.textSecondary),
          SizedBox(height: 4),
          Text('صورة الورشة', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class BookWorkshopScreen extends StatefulWidget {
  final CustomerProfile workshop;
  const BookWorkshopScreen({super.key, required this.workshop});

  @override
  State<BookWorkshopScreen> createState() => _BookWorkshopScreenState();
}

class _BookWorkshopScreenState extends State<BookWorkshopScreen> {
  final _db = Supabase.instance.client;
  DateTime _selectedDate = DateTime.now();
  String? _selectedHour;
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  final List<({String label, int hour24})> _hourlySlots = const [
    (label: '08:00 ص', hour24: 8),
    (label: '09:00 ص', hour24: 9),
    (label: '10:00 ص', hour24: 10),
    (label: '11:00 ص', hour24: 11),
    (label: '12:00 م', hour24: 12),
    (label: '01:00 م', hour24: 13),
    (label: '02:00 م', hour24: 14),
    (label: '03:00 م', hour24: 15),
    (label: '04:00 م', hour24: 16),
    (label: '05:00 م', hour24: 17),
    (label: '06:00 م', hour24: 18),
    (label: '07:00 م', hour24: 19),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  String get _formattedDate =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  int _hourForLabel(String label) =>
      _hourlySlots.firstWhere((s) => s.label == label, orElse: () => _hourlySlots.first).hour24;

  bool _isSlotDisabled({
    required ({String label, int hour24}) slot,
    required Set<String> bookedLabels,
  }) {
    if (bookedLabels.contains(slot.label)) {
      return true;
    }

    if (_isToday) {
      final nowHour = DateTime.now().hour;
      if (slot.hour24 <= nowHour) {
        return true;
      }

      final bookedHours = bookedLabels.map(_hourForLabel).toList();
      final hasBookedBeforeNow = bookedHours.any((h) => h <= nowHour);
      final futureBookedHours = bookedHours.where((h) => h > nowHour).toList();
      if (hasBookedBeforeNow && futureBookedHours.isNotEmpty) {
        final maxFutureBooked = futureBookedHours.reduce((a, b) => a > b ? a : b);
        if (slot.hour24 > nowHour && slot.hour24 < maxFutureBooked) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _submitBooking(bool workshopFullToday) async {
    if (_selectedHour == null && !workshopFullToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار ساعة متاحة أولاً')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _db.from('workshop_appointments').insert({
        'user_id': _db.auth.currentUser!.id,
        'workshop_id': widget.workshop.id,
        'appointment_date': _formattedDate,
        'appointment_time': _selectedHour ?? 'حسب توفر الورشة',
        'service_description':
            _descCtrl.text.trim().isEmpty ? 'فحص وصيانة مركبة' : _descCtrl.text.trim(),
        'status': 'pending',
        'progress_step': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(workshopFullToday
                ? 'الورشة ممتلئة حالياً؛ تم إرسال طلبك وسيقترح الميكانيكي موعداً مناسباً لك!'
                : 'تم إرسال طلب الموعد للورشة بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('حجز موعد - ${widget.workshop.fullName ?? "الورشة"}')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db
            .from('workshop_appointments')
            .stream(primaryKey: ['id'])
            .eq('workshop_id', widget.workshop.id),
        builder: (context, snap) {
          final dayAppts = (snap.data ?? [])
              .where((a) => a['appointment_date'] == _formattedDate && a['status'] != 'cancelled')
              .toList();

          final bookedLabels =
              dayAppts.map((a) => (a['appointment_time'] as String?) ?? '').toSet();
          final acceptedCount = dayAppts.where((a) => a['status'] == 'accepted').length;
          final isWorkshopFull = acceptedCount >= widget.workshop.maxCarCapacity;

          if (_selectedHour != null && bookedLabels.contains(_selectedHour)) {
            _selectedHour = null;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FadeSlideIn(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                    onDateChanged: (newDate) => setState(() {
                      _selectedDate = newDate;
                      _selectedHour = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (isWorkshopFull)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.orange),
                  ),
                  child: const Text(
                    'تنبيه: وصلت الورشة للحد الأقصى من السيارات لهذا اليوم، يمكنك إرسال الطلب وسيقترح عليك الميكانيكي موعداً بديلاً في نفس اليوم أو يوم آخر.',
                    style: TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              const Text(
                'اختر الساعة (الساعات الرمادية المشطوبة محجوزة أو غير متاحة)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _hourlySlots.map((slot) {
                  final disabled = _isSlotDisabled(slot: slot, bookedLabels: bookedLabels);
                  final selected = !disabled && _selectedHour == slot.label;

                  return GestureDetector(
                    onTap: disabled ? null : () => setState(() => _selectedHour = slot.label),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: disabled
                            ? AppColors.placeholder
                            : (selected ? AppColors.navy : AppColors.surface),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: disabled
                              ? AppColors.border
                              : (selected ? AppColors.navy : AppColors.border),
                        ),
                      ),
                      child: Text(
                        slot.label,
                        style: TextStyle(
                          color: disabled
                              ? AppColors.textSecondary
                              : (selected ? Colors.white : AppColors.textPrimary),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          decoration:
                              disabled ? TextDecoration.lineThrough : TextDecoration.none,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'وصف المشكلة أو الخدمة المطلوبة',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _submitting ? null : () => _submitBooking(isWorkshopFull),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isWorkshopFull ? 'إرسال طلب لاقتراح موعد آخر' : 'تأكيد حجز الموعد',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}