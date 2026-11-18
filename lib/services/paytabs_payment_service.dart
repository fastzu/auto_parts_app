import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';

class PayTabsPaymentService {
  final SupabaseClient _client = Supabase.instance.client;

  /// 1) يفتح أولاً خيارات الدفع (Visa/Mastercard, Apple Pay قريباً, Google Pay قريباً)
  /// وعند اختيار Visa/Mastercard ينتقل لصفحة الـ Checkout ثم زر Pay Now نحو MEPS
  Future<bool> startPaymentFlow({
    required BuildContext context,
    required double baseAmount,
    double feeAmount = 0.0,
    required String title,
    required String orderType, // 'sub' | 'wrk' | 'ord' | 'emg'
    required String referenceId,
    String? email,
    String? phone,
    String? name,
  }) async {
    final totalAmount = double.parse((baseAmount + feeAmount).toStringAsFixed(2));

    final chosenMethod = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اختر وسيلة الدفع',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),

            // 1) Visa / Mastercard (مفعّل)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.orange, width: 1.4),
              ),
              child: ListTile(
                leading: const Icon(Icons.credit_card, color: AppColors.orange, size: 28),
                title: const Text('Visa / Mastercard',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('الدفع الإلكتروني الآمن عبر MEPS'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.orange),
                onTap: () => Navigator.pop(ctx, 'visa'),
              ),
            ),
            const SizedBox(height: 10),

            // 2) Apple Pay (قريباً - غير مفعل حالياً)
            Card(
              color: AppColors.background,
              child: ListTile(
                leading: const Icon(Icons.apple, color: AppColors.textSecondary, size: 30),
                title: const Text('Apple Pay',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                subtitle: const Text('سيتم تفعيل الخدمة قريباً'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.placeholder,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('قريباً',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('خدمة Apple Pay قيد التفعيل حالياً، يرجى استخدام Visa / Mastercard'),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // 3) Google Pay (قريباً - غير مفعل حالياً)
            Card(
              color: AppColors.background,
              child: ListTile(
                leading: const Icon(Icons.g_mobiledata, color: AppColors.textSecondary, size: 34),
                title: const Text('Google Pay',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                subtitle: const Text('سيتم تفعيل الخدمة قريباً'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.placeholder,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('قريباً',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('خدمة Google Pay قيد التفعيل حالياً، يرجى استخدام Visa / Mastercard'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (chosenMethod != 'visa' || !context.mounted) return false;

    // 2) الانتقال لصفحة Checkout وعرض الإجمالي مع زر Pay Now
    final bool? paid = await Navigator.of(context).push<bool>(
      animatedRoute(
        _MepsCheckoutPage(
          title: title,
          baseAmount: baseAmount,
          feeAmount: feeAmount,
          totalAmount: totalAmount,
          onPayNow: () => payWithCardRedirect(
            context: context,
            amount: totalAmount,
            title: title,
            orderType: orderType,
            referenceId: referenceId,
            email: email,
            phone: phone,
            name: name,
          ),
        ),
      ),
    );

    return paid == true;
  }

  /// 3) الاتصال بدالة create-payment وفتح صفحة MEPS حسب نوع الجهاز
  Future<bool> payWithCardRedirect({
    required BuildContext context,
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    String? email,
    String? phone,
    String? name,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final res = await _client.functions.invoke(
      'create-payment',
      body: {
        'user_id': user.id,
        'amount': amount,
        'payment_method': 'Card',
        'description': title,
        'order_type': orderType,
        'reference_id': referenceId,
        'customer_email': email ?? user.email,
        'customer_phone': phone ?? '0790000000',
        'customer_name': name ?? 'Customer',
      },
    );

    if (res.status != 200 || res.data == null || res.data['redirect_url'] == null) {
      throw Exception(res.data?['error'] ?? 'تعذر إنشاء جلسة الدفع من البوابة');
    }

    final String redirectUrl = res.data['redirect_url'] as String;
    if (!context.mounted) return false;

    final bool isMobileNative = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileNative) {
      final bool? completed = await Navigator.of(context).push<bool>(
        animatedRoute(PaymentWebViewScreen(
          redirectUrl: redirectUrl,
          title: title,
        )),
      );
      return completed == true;
    } else {
      // على Windows و Web: نفتح صفحة الدفع في المتصفح الخارجي لتفادي خطأ WebViewPlatform
      await launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.externalApplication);
      if (!context.mounted) return false;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إكمال الدفع عبر MEPS'),
          content: const Text(
            'تم فتح صفحة الدفع في المتصفح.\nبعد إتمام الدفع بنجاح، اضغط على "تم الدفع" لتحديث حسابك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تم الدفع'),
            ),
          ],
        ),
      );
      return confirmed == true;
    }
  }
}

/// صفحة الـ Checkout التي تعرض الإجمالي قبل الضغط على Pay Now
class _MepsCheckoutPage extends StatefulWidget {
  final String title;
  final double baseAmount;
  final double feeAmount;
  final double totalAmount;
  final Future<bool> Function() onPayNow;

  const _MepsCheckoutPage({
    required this.title,
    required this.baseAmount,
    required this.feeAmount,
    required this.totalAmount,
    required this.onPayNow,
  });

  @override
  State<_MepsCheckoutPage> createState() => _MepsCheckoutPageState();
}

class _MepsCheckoutPageState extends State<_MepsCheckoutPage> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص الدفع (Checkout)')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('وسيلة الدفع: Visa / Mastercard (MEPS)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    const Divider(height: 28),
                    _row('المبلغ الأساسي', '${widget.baseAmount.toStringAsFixed(2)} د.أ'),
                    if (widget.feeAmount > 0) ...[
                      const SizedBox(height: 10),
                      _row('عمولة الخدمة', '${widget.feeAmount.toStringAsFixed(2)} د.أ',
                          color: AppColors.orange),
                    ],
                    const Divider(height: 28),
                    _row(
                      'الإجمالي للدفع',
                      '${widget.totalAmount.toStringAsFixed(2)} د.أ',
                      bold: true,
                      color: AppColors.navy,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        try {
                          final ok = await widget.onPayNow();
                          if (ok && context.mounted) {
                            Navigator.pop(context, true);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ بالدفع: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'Pay Now · ادفع الآن (${widget.totalAmount.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String val, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        Text(val,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.bold,
              fontSize: bold ? 18 : 14,
              color: color,
            )),
      ],
    );
  }
}