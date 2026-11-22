import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';

class StatusLabels {
  StatusLabels._();

  /// حالات طلبات الطوارئ والونش بالعربية فقط (بدون كلمة "الحالة:" وبدون إنجليزي)
  static String emergency(String? status, {String? progressStep}) {
    final st = (status ?? '').trim().toLowerCase();
    final step = (progressStep ?? '').trim().toLowerCase();

    if (st == 'cancelled' || step == 'cancelled') {
      return 'ملغي';
    }
    if (st == 'completed' || step == 'completed') {
      return 'مكتمل ✓';
    }
    if (step == 'arrived_at_pickup' || st == 'arrived') {
      return 'وصل الفني إلى موقعك ✓';
    }
    if (step == 'towing' || st == 'towing') {
      return 'جاري سحب السيارة إلى الوجهة';
    }
    if (step == 'on_the_way' || st == 'accepted' || st == 'in_progress') {
      return 'في الطريق إلى موقعك';
    }
    if (st == 'pending' || step == 'pending' || st.isEmpty) {
      return 'بانتظار قبول الفني';
    }
    return 'قيد المتابعة';
  }

  /// حالات مواعيد الورشة بالعربية فقط (بدون كلمة "الحالة:" وبدون إنجليزي)
  static String appointment(String? status, {String? progressStep}) {
    final st = (status ?? '').trim().toLowerCase();
    final step = (progressStep ?? '').trim().toLowerCase();

    if (st == 'cancelled' || step == 'cancelled') {
      return 'ملغي';
    }
    if (st == 'completed' || step == 'completed') {
      return 'مكتمل وتم التسليم ✓';
    }
    if (st == 'reschedule_proposed') {
      return 'موعد بديل مقترح';
    }

    switch (step) {
      case 'awaiting_payment':
        return 'السيارة جاهزة للتسليم والدفع';
      case 'testing':
        return 'الفحص والتجربة النهائية';
      case 'repairing':
        return 'جاري الإصلاح في الورشة';
      case 'diagnosis':
        return 'فحص السيارة وتشخيص العطل';
      case 'arrived_at_workshop':
        return 'تم استلام السيارة في الورشة';
      case 'on_the_way':
        return 'في الطريق إلى الورشة';
    }

    if (st == 'accepted') {
      return 'تم قبول الموعد';
    }
    if (st == 'pending' || st.isEmpty) {
      return 'بانتظار تأكيد الورشة';
    }
    return 'قيد المتابعة';
  }

  /// اللون المناسب لكل حالة
  static Color colorFor(String? status, {String? progressStep}) {
    final st = (status ?? '').trim().toLowerCase();
    final step = (progressStep ?? '').trim().toLowerCase();

    if (st == 'cancelled' || step == 'cancelled') {
      return Colors.red;
    }
    if (st == 'completed' ||
        step == 'completed' ||
        step == 'arrived_at_pickup' ||
        step == 'arrived_at_workshop') {
      return AppColors.success;
    }
    if (st == 'reschedule_proposed' ||
        step == 'on_the_way' ||
        step == 'diagnosis' ||
        step == 'repairing' ||
        step == 'testing' ||
        step == 'awaiting_payment') {
      return AppColors.orange;
    }
    if (st == 'accepted' || st == 'in_progress') {
      return AppColors.navy;
    }
    return AppColors.textSecondary;
  }

  static Color statusColor(String? status, {String? progressStep}) =>
      colorFor(status, progressStep: progressStep);

  static String role(String? role) => roleArabic(role);

  static String roleArabic(String? role) {
    return switch ((role ?? '').trim().toLowerCase()) {
      'all' => 'الجميع',
      'specific_user' => 'مستخدم محدد',
      'admin' => 'الإدارة',
      'merchant' => 'تاجر قطع',
      'mechanic' => 'ميكانيكي / ورشة',
      'towing' => 'سائق ونش',
      _ => 'عميل',
    };
  }
}