import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_locale_service.dart';
import '../services/paytabs_payment_service.dart';
import '../theme/app_theme.dart';

class CommissionDebtCard extends StatefulWidget {
  final double debtAmount;
  final double walletBalance;
  final VoidCallback onSettled;

  const CommissionDebtCard({
    super.key,
    required this.debtAmount,
    required this.onSettled,
    this.walletBalance = 0.0,
  });

  @override
  State<CommissionDebtCard> createState() => _CommissionDebtCardState();
}

class _CommissionDebtCardState extends State<CommissionDebtCard> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    final hasDebt = widget.debtAmount > 0.009;

    if (!hasDebt) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.verified, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.tr('لا توجد عمولات مستحقة عليك',
                        'No outstanding commission'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.tr('حسابك المالي مسوّى بالكامل ✓',
                        'Your financial account is fully settled ✓'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '0.00 ${loc.tr('د.أ', 'JOD')}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_balance, color: Colors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.tr('عمولة مستحقة للتطبيق', 'Platform Commission Due'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.tr(
                        'عمولة طلبات الكاش — تُخصم تلقائياً من أول دفعة بطاقة أو سدّدها الآن لتتمكن من السحب',
                        'Cash orders commission — auto-deducted from next card order or pay now to enable withdrawal',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.debtAmount.toStringAsFixed(2)} ${loc.tr('د.أ', 'JOD')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _opening
                ? null
                : () async {
                    setState(() => _opening = true);
                    final paid = await showCommissionPaymentSheet(
                      context,
                      debtAmount: widget.debtAmount,
                      walletBalance: widget.walletBalance,
                    );
                    if (mounted) {
                      setState(() => _opening = false);
                      if (paid) widget.onSettled();
                    }
                  },
            icon: const Icon(Icons.credit_card, size: 19),
            label: Text(
              loc.tr('دفع العمولة المستحقة الآن', 'Pay Due Commission Now'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// نافذة سداد العمولة المستحقة عبر الوسائل الإلكترونية فقط (Visa/Mastercard, Apple Pay, Google Pay)
Future<bool> showCommissionPaymentSheet(
  BuildContext context, {
  required double debtAmount,
  double walletBalance = 0.0,
}) async {
  final loc = AppLocaleService.instance;
  final db = Supabase.instance.client;
  final user = db.auth.currentUser;
  if (user == null) return false;

  // تحقق فوري من الرصيد الفعلي للذمة في قاعدة البيانات لمنع أي دفع مكرر
  double liveDebt = debtAmount;
  try {
    final row = await db
        .from('customers')
        .select('pending_commission_debt')
        .eq('id', user.id)
        .maybeSingle();
    liveDebt =
        ((row?['pending_commission_debt'] as num?)?.toDouble() ?? 0.0);
  } catch (_) {}

  if (liveDebt <= 0.009) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
          content: Text(
            loc.tr('لا توجد عمولة مستحقة عليك حالياً ✓',
                'No commission due right now ✓'),
          ),
        ),
      );
    }
    return true;
  }

  if (!context.mounted) return false;

  final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      String selected = 'visa';
      bool processing = false;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> handlePay() async {
            if (processing) return;

            if (selected == 'apple_pay') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.navy,
                  content: Text(
                    loc.tr(
                      'Apple Pay جاهزة للربط فور تفعيل حساب مطوري Apple — يرجى الدفع حالياً ببطاقة Visa / Mastercard',
                      'Apple Pay will be active once Apple Developer Merchant ID is linked — please use Visa / Mastercard for now',
                    ),
                  ),
                ),
              );
              return;
            }

            if (selected == 'google_pay') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.navy,
                  content: Text(
                    loc.tr(
                      'Google Pay جاهزة للربط فور تفعيل بوابة التاجر — يرجى الدفع حالياً ببطاقة Visa / Mastercard',
                      'Google Pay will be active once Merchant Gateway is linked — please use Visa / Mastercard for now',
                    ),
                  ),
                ),
              );
              return;
            }

            setSheetState(() => processing = true);
            try {
              final ok = await PayTabsPaymentService().payWithCardRedirect(
                context: context,
                amount: liveDebt,
                title: loc.tr(
                  'سداد عمولة منصة غيارك',
                  'Ghiyarak Platform Commission Settlement',
                ),
                orderType: 'debt',
                referenceId: user.id,
                email: user.email,
              );

              if (!ok) {
                if (ctx.mounted) setSheetState(() => processing = false);
                return;
              }

              await db.rpc('settle_provider_commission_debt', params: {
                'p_payment_method': 'visa',
                'p_note': 'Paid via Visa/Mastercard',
              });

              if (!ctx.mounted) return;
              Navigator.pop(ctx, true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                  content: Text(
                    loc.tr(
                      'تم سداد العمولة المستحقة (${liveDebt.toStringAsFixed(2)} د.أ) بنجاح ✓',
                      'Commission (${liveDebt.toStringAsFixed(2)} JOD) paid successfully ✓',
                    ),
                  ),
                ),
              );
            } catch (e) {
              if (ctx.mounted) setSheetState(() => processing = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.red,
                    content: Text(
                      e.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              }
            }
          }

          Widget methodTile({
            required String id,
            required IconData icon,
            required String title,
            required String subtitle,
            Color? iconColor,
          }) {
            final isSel = selected == id;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: processing ? null : () => setSheetState(() => selected = id),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSel ? AppColors.orangeLight : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSel ? AppColors.orange : AppColors.border,
                    width: isSel ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: iconColor ?? (isSel ? AppColors.orange : AppColors.navy),
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSel
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSel ? AppColors.orange : AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.tr('سداد العمولة المستحقة', 'Pay Platform Commission'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          loc.tr('المبلغ المطلوب سداده:', 'Amount Due:'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        Text(
                          '${liveDebt.toStringAsFixed(2)} ${loc.tr('د.أ', 'JOD')}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  methodTile(
                    id: 'visa',
                    icon: Icons.credit_card,
                    title: 'Visa / Mastercard',
                    subtitle: loc.tr(
                      'دفع إلكتروني فوري وآمن — تُصفّر العمولة مباشرة',
                      'Instant secure card payment — clears debt immediately',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isIOS || !isAndroid)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: methodTile(
                        id: 'apple_pay',
                        icon: Icons.apple,
                        iconColor: Colors.black,
                        title: 'Apple Pay',
                        subtitle: loc.tr(
                          'دفع سريع عبر Apple Pay',
                          'Fast payment with Apple Pay',
                        ),
                      ),
                    ),
                  if (isAndroid || !isIOS)
                    methodTile(
                      id: 'google_pay',
                      icon: Icons.g_mobiledata_rounded,
                      iconColor: Colors.blue.shade700,
                      title: 'Google Pay',
                      subtitle: loc.tr(
                        'دفع سريع عبر Google Pay',
                        'Fast payment with Google Pay',
                      ),
                    ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: processing ? null : handlePay,
                    child: processing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            loc.tr(
                              'ادفع الآن (${liveDebt.toStringAsFixed(2)} د.أ)',
                              'Pay Now (${liveDebt.toStringAsFixed(2)} JOD)',
                            ),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  return result == true;
}