import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_locale_service.dart';
import '../theme/app_theme.dart';

/// نافذة تقييم الميكانيكي أو سائق الونش بعد الدفع وإنهاء الخدمة
Future<bool> showServiceRatingDialog({
  required BuildContext context,
  required String serviceKind, // 'workshop' | 'emergency'
  required String referenceId,
  required String providerId,
  String? providerName,
  bool isWinch = false,
}) async {
  final loc = AppLocaleService.instance;
  final db = Supabase.instance.client;
  final reviewCtrl = TextEditingController();
  int selectedStars = 5;
  bool submitting = false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final roleLabel = serviceKind == 'workshop'
            ? loc.tr('الورشة / الميكانيكي', 'Workshop / Mechanic')
            : (isWinch
                ? loc.tr('سائق الونش', 'Towing Driver')
                : loc.tr('ميكانيكي الطوارئ', 'Roadside Mechanic'));

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: AppColors.orange,
                  size: 36,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                loc.tr('قيّم تجربتك الآن', 'Rate Your Experience'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                providerName != null && providerName.trim().isNotEmpty
                    ? '$roleLabel · $providerName'
                    : roleLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (idx) {
                  final star = idx + 1;
                  final active = star <= selectedStars;
                  return IconButton(
                    onPressed: submitting
                        ? null
                        : () => setS(() => selectedStars = star),
                    icon: Icon(
                      active ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 36,
                      color: active ? AppColors.orange : Colors.grey.shade400,
                    ),
                  );
                }),
              ),
              Text(
                switch (selectedStars) {
                  5 => loc.tr('ممتاز جداً! 🔥', 'Excellent! 🔥'),
                  4 => loc.tr('جيد جداً 👍', 'Very Good 👍'),
                  3 => loc.tr('جيد', 'Good'),
                  2 => loc.tr('مقبول', 'Fair'),
                  _ => loc.tr('يحتاج تحسين', 'Needs Improvement'),
                },
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reviewCtrl,
                maxLines: 3,
                enabled: !submitting,
                decoration: InputDecoration(
                  hintText: loc.tr(
                    'اكتب ملاحظتك (اختياري)...',
                    'Write your feedback (optional)...',
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx, false),
              child: Text(loc.tr('لاحقاً', 'Later')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      setS(() => submitting = true);
                      try {
                        await db.rpc('submit_provider_rating', params: {
                          'p_service_kind': serviceKind,
                          'p_reference_id': referenceId,
                          'p_provider_id': providerId,
                          'p_rating': selectedStars,
                          'p_review': reviewCtrl.text.trim(),
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setS(() => submitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red,
                              content: Text(
                                loc.tr(
                                  'تعذر حفظ التقييم: $e',
                                  'Failed to save rating: $e',
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(loc.tr('إرسال التقييم', 'Submit Rating')),
            ),
          ],
        );
      },
    ),
  );

  reviewCtrl.dispose();
  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          loc.tr('شكراً لتقييمك! تم حفظه بنجاح ⭐', 'Thank you! Rating saved ⭐'),
        ),
      ),
    );
  }
  return result == true;
}