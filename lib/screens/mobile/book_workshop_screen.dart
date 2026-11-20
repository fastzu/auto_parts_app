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
    parts.add(
        rawBuilding.startsWith('مبنى') ? rawBuilding : 'مبنى $rawBuilding');
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
                          // 1) صورة الورشة + شارة التوفر
                          Stack(
                            children: [
                              SizedBox(
                                height: 165,
                                width: double.infinity,
                                child: (w.workshopImageUrl ?? '').isNotEmpty
                                    ? Image.network(
                                        w.workshopImageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _imagePlaceholder(),
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
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: w.isAvailable
                                        ? AppColors.success
                                        : Colors.red,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 6,
                                      ),
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
                                        w.isAvailable
                                            ? 'متاح الآن'
                                            : 'غير متاح',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // 2) تفاصيل الورشة (الاسم، العنوان، الرقم) + الأزرار
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                            const Icon(Icons.verified,
                                                color: Colors.blue, size: 18),
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
                                        border:
                                            Border.all(color: AppColors.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.phone_outlined,
                                              size: 14,
                                              color: AppColors.orange),
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
                                        size: 16,
                                        color: AppColors.textSecondary),
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
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'يرجى تسجيل الدخول أولاً لحجز موعد'),
                                              ),
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            animatedRoute(BookWorkshopScreen(
                                                workshop: w)),
                                          );
                                        },
                                        child: Container(
                                          height: 46,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: w.isAvailable
                                                ? AppColors.orange
                                                : AppColors.placeholder,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
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
                                                w.isAvailable
                                                    ? 'حجز موعد'
                                                    : 'الورشة غير متاحة',
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
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'يرجى تسجيل الدخول أولاً للدردشة'),
                                              ),
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            animatedRoute(
                                                ChatConversationScreen(
                                              otherUserId: w.id,
                                              otherUserName:
                                                  w.fullName ?? 'الورشة',
                                              otherUserPhone: w.phone,
                                            )),
                                          );
                                        },
                                        child: Container(
                                          height: 46,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppColors.navy,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.chat_bubble_outline,
                                                  size: 16,
                                                  color: Colors.white),
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
          Icon(Icons.build_circle_outlined,
              size: 42, color: AppColors.textSecondary),
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
  DateTime _selectedDate = DateTime.now();
  String _selectedHour = '10:00 ص';
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  final List<String> _hourlySlots = const [
    '08:00 ص',
    '09:00 ص',
    '10:00 ص',
    '11:00 ص',
    '12:00 م',
    '01:00 م',
    '02:00 م',
    '03:00 م',
    '04:00 م',
    '05:00 م',
    '06:00 م',
    '07:00 م',
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  String get _formattedDate =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _submitBooking() async {
    setState(() => _submitting = true);
    try {
      final db = Supabase.instance.client;
      await db.from('workshop_appointments').insert({
        'user_id': db.auth.currentUser!.id,
        'workshop_id': widget.workshop.id,
        'appointment_date': _formattedDate,
        'appointment_time': _selectedHour,
        'service_description': _descCtrl.text.trim().isEmpty
            ? 'فحص وصيانة مركبة'
            : _descCtrl.text.trim(),
        'status': 'pending',
        'progress_step': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب الموعد للورشة بنجاح!'),
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
      appBar: AppBar(
          title: Text('حجز موعد - ${widget.workshop.fullName ?? "الورشة"}')),
      body: ListView(
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
                onDateChanged: (newDate) =>
                    setState(() => _selectedDate = newDate),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'اختر الساعة (فاصل ساعة بين كل موعد وآخر)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hourlySlots.map((slot) {
              final selected = _selectedHour == slot;
              return ChoiceChip(
                label: Text(slot),
                selected: selected,
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary),
                onSelected: (_) => setState(() => _selectedHour = slot),
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
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submitting ? null : _submitBooking,
            child: _submitting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('تأكيد حجز الموعد',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
