import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/chat_screen.dart';

String formatWorkshopStreet(CustomerProfile w) {
  final parts = <String>[
    if ((w.streetName ?? '').trim().isNotEmpty) 'شارع ${w.streetName!.trim()}',
    if ((w.buildingNumber ?? '').trim().isNotEmpty) 'مبنى ${w.buildingNumber!.trim()}',
  ];
  if (parts.isNotEmpty) {
    return parts.join(' · ');
  }
  return (w.workshopAddress ?? '').trim().isNotEmpty ? w.workshopAddress! : 'العنوان غير محدد';
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

          return ListView.separated(
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
                    border: Border.all(color: AppColors.navy, width: 1.4),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        children: [
                          SizedBox(
                            height: 145,
                            width: double.infinity,
                            child: (w.workshopImageUrl ?? '').isNotEmpty
                                ? Image.network(w.workshopImageUrl!, fit: BoxFit.cover)
                                : Container(
                                    color: AppColors.placeholder,
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.build_circle_outlined, size: 42, color: AppColors.textSecondary),
                                        SizedBox(height: 4),
                                        Text('صورة الورشة', style: TextStyle(color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: w.isAvailable ? AppColors.success : Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                w.isAvailable ? 'متاح الآن' : 'غير متاح',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 1.5, thickness: 1.5, color: AppColors.navy),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(w.fullName ?? 'ورشة صيانة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(height: 3),
                                      Text(streetAddress, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Text('الرقم', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                      Text(w.phone ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.navy,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () {
                                    if (viewerProfile == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى تسجيل الدخول أولاً للدردشة')));
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
                                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                  label: const Text('دردشة', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: w.isAvailable ? AppColors.orange : AppColors.placeholder,
                                  foregroundColor: w.isAvailable ? Colors.white : AppColors.textSecondary,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: !w.isAvailable
                                    ? null
                                    : () {
                                        if (viewerProfile == null) {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى تسجيل الدخول أولاً لحجز موعد')));
                                          return;
                                        }
                                        Navigator.push(context, animatedRoute(BookWorkshopScreen(workshop: w)));
                                      },
                                child: Text(
                                  w.isAvailable ? 'حجز موعد' : 'الورشة غير متاحة حالياً',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
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
    '08:00 ص', '09:00 ص', '10:00 ص', '11:00 ص',
    '12:00 م', '01:00 م', '02:00 م', '03:00 م',
    '04:00 م', '05:00 م', '06:00 م', '07:00 م',
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
        'service_description': _descCtrl.text.trim().isEmpty ? 'فحص وصيانة مركبة' : _descCtrl.text.trim(),
        'status': 'pending',
        'progress_step': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الموعد للورشة بنجاح!'), backgroundColor: AppColors.success),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FadeSlideIn(
            child: Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 60)),
                onDateChanged: (newDate) => setState(() => _selectedDate = newDate),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('اختر الساعة (فاصل ساعة بين كل موعد وآخر)', style: TextStyle(fontWeight: FontWeight.bold)),
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
                labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary),
                onSelected: (_) => setState(() => _selectedHour = slot),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: InputDecoration(labelText: 'وصف المشكلة أو الخدمة المطلوبة', filled: true, fillColor: AppColors.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _submitting ? null : _submitBooking,
            child: _submitting ? const CircularProgressIndicator(color: Colors.white) : const Text('تأكيد حجز الموعد', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}