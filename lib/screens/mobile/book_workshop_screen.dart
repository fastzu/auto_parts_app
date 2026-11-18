import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

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
            content: Text(
                'تم إرسال طلب الموعد للورشة، سيصلك إشعار عند القبول أو اقتراح وقت بديل.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
          const Text('اختر الساعة (فاصل ساعة بين كل موعد وآخر)',
              style: TextStyle(fontWeight: FontWeight.bold)),
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
