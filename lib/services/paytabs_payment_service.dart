import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';

class PayTabsPaymentService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<bool> startPaymentFlow({
    required BuildContext context,
    required double baseAmount,
    double feeAmount = 0.0,
    required String title,
    required String orderType, // 'sub' | 'wrk' | 'ord' | 'emg' | 'debt'
    required String referenceId,
    String? email,
    String? phone,
    String? name,
    String? userRole,
  }) async {
    final totalAmount =
        double.parse((baseAmount + feeAmount).toStringAsFixed(2));

    String cliqAlias = 'GHYARAK';
    try {
      final row = await _client
          .from('system_settings')
          .select('value')
          .eq('key', 'cliq_alias')
          .maybeSingle();
      final val = (row?['value'] as String?)?.trim();
      if (val != null && val.isNotEmpty) cliqAlias = val;
    } catch (_) {}

    if (!context.mounted) return false;

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
            _sheetOption(
              icon: Icons.credit_card,
              title: 'Visa / Mastercard',
              onTap: () => Navigator.pop(ctx, 'visa'),
            ),
            const SizedBox(height: 8),
            _sheetOption(
              icon: Icons.apple,
              title: 'Apple Pay',
              onTap: () => Navigator.pop(ctx, 'apple_pay'),
            ),
            const SizedBox(height: 8),
            _sheetOption(
              icon: Icons.g_mobiledata,
              title: 'Google Pay',
              onTap: () => Navigator.pop(ctx, 'google_pay'),
            ),
            const SizedBox(height: 8),
            _sheetOption(
              icon: Icons.account_balance,
              title: 'CliQ',
              subtitle: 'Alias: $cliqAlias',
              onTap: () => Navigator.pop(ctx, 'cliq'),
            ),
            const SizedBox(height: 8),
            _sheetOption(
              icon: Icons.payments_outlined,
              title: 'Cash (كاش)',
              onTap: () => Navigator.pop(ctx, 'cash'),
            ),
          ],
        ),
      ),
    );

    if (chosenMethod == null || !context.mounted) return false;

    if (chosenMethod == 'cliq' || chosenMethod == 'cash') {
      return _handleManualCliqOrCash(
        context: context,
        method: chosenMethod,
        cliqAlias: cliqAlias,
        totalAmount: totalAmount,
        title: title,
        orderType: orderType,
        referenceId: referenceId,
      );
    }

    final methodLabel = chosenMethod == 'apple_pay'
        ? 'Apple Pay'
        : (chosenMethod == 'google_pay' ? 'Google Pay' : 'Visa / Mastercard');
    final gatewayMethod = chosenMethod == 'apple_pay'
        ? 'ApplePay'
        : (chosenMethod == 'google_pay' ? 'GooglePay' : 'Card');

    final bool? paid = await Navigator.of(context).push<bool>(
      animatedRoute(
        _MepsCheckoutPage(
          title: title,
          methodLabel: methodLabel,
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
            paymentMethod: gatewayMethod,
          ),
        ),
      ),
    );

    return paid == true;
  }

  Widget _sheetOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.orange, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 15,
          color: AppColors.navy,
        ),
        onTap: onTap,
      ),
    );
  }

  Future<bool> _handleManualCliqOrCash({
    required BuildContext context,
    required String method,
    required String cliqAlias,
    required double totalAmount,
    required String title,
    required String orderType,
    required String referenceId,
  }) async {
    final refCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(method == 'cliq' ? 'الدفع عبر CliQ' : 'الدفع نقداً (كاش)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title · ${totalAmount.toStringAsFixed(2)} د.أ'),
            if (method == 'cliq') ...[
              const SizedBox(height: 8),
              Text(
                'Alias: $cliqAlias',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'رقم مرجع الحوالة',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (method == 'cliq' && refCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    final ref = refCtrl.text.trim();
    refCtrl.dispose();
    if (confirmed != true) return false;

    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      if (orderType == 'sub') {
        await _client.from('customers').update({
          'subscription_plan': referenceId,
          'is_trusted_merchant': true,
        }).eq('id', user.id);
      }
      await _client.from('wallet_transactions').insert({
        'provider_id': user.id,
        'customer_id': user.id,
        'reference_id': referenceId,
        'transaction_type': '${orderType}_$method',
        'payment_method': method,
        'gross_amount': totalAmount,
        'commission_rate': 0.0,
        'commission_amount': 0.0,
        'net_amount': totalAmount,
        'status': method == 'cliq' ? 'pending_verification' : 'completed',
        if (ref.isNotEmpty) 'notes': 'CliQ Ref: $ref',
      });
    } catch (_) {}
    return true;
  }

  Future<bool> payWithCardRedirect({
    required BuildContext context,
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    String? email,
    String? phone,
    String? name,
    String paymentMethod = 'Card',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final res = await _client.functions.invoke(
      'create-payment',
      body: {
        'user_id': user.id,
        'amount': amount,
        'payment_method': paymentMethod,
        'description': title,
        'order_type': orderType,
        'reference_id': referenceId,
        'customer_email': email ?? user.email,
        'customer_phone': phone ?? '0790000000',
        'customer_name': name ?? 'Customer',
      },
    );

    if (res.status != 200 ||
        res.data == null ||
        res.data['redirect_url'] == null) {
      throw Exception(res.data?['error'] ?? 'تعذر إنشاء جلسة الدفع من البوابة');
    }

    final String redirectUrl = res.data['redirect_url'] as String;
    if (!context.mounted) return false;

    final bool isMobileNative = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileNative) {
      final bool? completed = await Navigator.of(context).push<bool>(
        animatedRoute(
          PaymentWebViewScreen(redirectUrl: redirectUrl, title: title),
        ),
      );
      return completed == true;
    } else {
      await launchUrl(
        Uri.parse(redirectUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted) return false;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إكمال الدفع'),
          content: const Text('بعد إتمام الدفع، اضغط على "تم الدفع".'),
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

class _MepsCheckoutPage extends StatefulWidget {
  final String title;
  final String methodLabel;
  final double baseAmount;
  final double feeAmount;
  final double totalAmount;
  final Future<bool> Function() onPayNow;

  const _MepsCheckoutPage({
    required this.title,
    required this.methodLabel,
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
      appBar: AppBar(title: const Text('ملخص الدفع')),
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
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'وسيلة الدفع: ${widget.methodLabel}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const Divider(height: 28),
                    _row(
                      'المبلغ الأساسي',
                      '${widget.baseAmount.toStringAsFixed(2)} د.أ',
                    ),
                    if (widget.feeAmount > 0) ...[
                      const SizedBox(height: 10),
                      _row(
                        'عمولة الخدمة',
                        '${widget.feeAmount.toStringAsFixed(2)} د.أ',
                        color: AppColors.orange,
                      ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                              SnackBar(
                                content: Text('خطأ بالدفع: $e'),
                                backgroundColor: Colors.red,
                              ),
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
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'ادفع الآن (${widget.totalAmount.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
        Text(
          label,
          style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500),
        ),
        Text(
          val,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.bold,
            fontSize: bold ? 18 : 14,
            color: color,
          ),
        ),
      ],
    );
  }
}