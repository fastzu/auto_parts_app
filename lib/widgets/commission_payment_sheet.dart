import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/db_models.dart';
import '../services/paytabs_payment_service.dart';
import '../theme/app_theme.dart';

class CommissionDebtCard extends StatelessWidget {
  final double debtAmount;
  final double walletBalance;
  final VoidCallback onPayTap;

  const CommissionDebtCard({
    super.key,
    required this.debtAmount,
    this.walletBalance = 0.0,
    required this.onPayTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDebt = debtAmount > 0.009;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasDebt
            ? const Color(0xFFFFF5F5)
            : AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasDebt
              ? Colors.red.withValues(alpha: 0.35)
              : AppColors.success.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: hasDebt
                      ? Colors.red.withValues(alpha: 0.12)
                      : AppColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasDebt
                      ? Icons.account_balance_outlined
                      : Icons.verified_rounded,
                  color: hasDebt ? Colors.red.shade700 : AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasDebt
                          ? 'عمولة مستحقة للتطبيق'
                          : 'لا توجد عمولات مستحقة عليك',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: hasDebt ? Colors.red.shade800 : AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDebt
                          ? 'عمولة الطلبات النقدية (كاش) المستحقة للمنصة'
                          : 'حسابك المالي مسوّى بالكامل ✓',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${debtAmount.toStringAsFixed(2)} د.أ',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: hasDebt ? Colors.red.shade700 : AppColors.success,
                ),
              ),
            ],
          ),
          if (hasDebt) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onPayTap,
                icon: const Icon(Icons.payment_rounded, size: 19),
                label: const Text(
                  'دفع العمولة المستحقة الآن',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool> showCommissionPaymentSheet({
  required BuildContext context,
  required CustomerProfile profile,
  required double debtAmount,
  double walletBalance = 0.0,
  VoidCallback? onSettled,
}) async {
  if (debtAmount <= 0) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _CommissionPaymentSheetBody(
      profile: profile,
      debtAmount: debtAmount,
      walletBalance: walletBalance,
    ),
  );

  if (result == true) {
    onSettled?.call();
    return true;
  }
  return false;
}

class _CommissionPaymentSheetBody extends StatefulWidget {
  final CustomerProfile profile;
  final double debtAmount;
  final double walletBalance;

  const _CommissionPaymentSheetBody({
    required this.profile,
    required this.debtAmount,
    required this.walletBalance,
  });

  @override
  State<_CommissionPaymentSheetBody> createState() =>
      _CommissionPaymentSheetBodyState();
}

class _CommissionPaymentSheetBodyState
    extends State<_CommissionPaymentSheetBody> {
  final _db = Supabase.instance.client;
  late final TextEditingController _amountCtrl;
  String _method = 'visa';
  bool _processing = false;

  bool get _canUseWallet => widget.walletBalance >= 0.5;
  bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.debtAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
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

  Future<void> _settleDebtInDb(double amount, String method, String note) async {
    try {
      await _db.rpc('settle_provider_commission_debt', params: {
        'p_amount': amount,
        'p_payment_method': method,
        'p_note': note,
      });
    } catch (_) {
      // احتياطي في حال لم تُنشأ دالة RPC بعد
      final newDebt =
          (widget.debtAmount - amount).clamp(0.0, double.infinity);
      final updates = <String, dynamic>{
        'pending_commission_debt': double.parse(newDebt.toStringAsFixed(2)),
      };
      if (method == 'wallet') {
        final newBal =
            (widget.walletBalance - amount).clamp(0.0, double.infinity);
        updates['wallet_balance'] = double.parse(newBal.toStringAsFixed(2));
      }
      await _db.from('customers').update(updates).eq('id', widget.profile.id);
      await _db.from('wallet_transactions').insert({
        'provider_id': widget.profile.id,
        'customer_id': widget.profile.id,
        'transaction_type': 'commission_settlement',
        'payment_method': method,
        'gross_amount': amount,
        'commission_rate': 0,
        'commission_amount': amount,
        'net_amount': method == 'wallet' ? -amount : 0,
        'status': method == 'cash_admin' ? 'pending_verification' : 'completed',
      });
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0 || amount > widget.debtAmount + 0.01) {
      _showTopToast(
        'مبلغ غير صالح',
        'أدخل مبلغاً بين 0.50 و ${widget.debtAmount.toStringAsFixed(2)} د.أ',
        isError: true,
      );
      return;
    }

    if (_method == 'wallet' && amount > widget.walletBalance) {
      _showTopToast(
        'رصيد المحفظة غير كافٍ',
        'رصيدك المتاح هو ${widget.walletBalance.toStringAsFixed(2)} د.أ',
        isError: true,
      );
      return;
    }

    if (_method == 'apple_pay' || _method == 'google_pay') {
      _showTopToast(
        _method == 'apple_pay' ? 'Apple Pay جاهز للربط' : 'Google Pay جاهز للربط',
        'سيعمل تلقائياً فور تفعيل حساب المطورين وإضافة معرف التاجر، يمكنك الدفع حالياً ببطاقة Visa/Mastercard.',
        isError: true,
      );
      return;
    }

    setState(() => _processing = true);
    try {
      if (_method == 'visa') {
        final paid = await PayTabsPaymentService().payWithCardRedirect(
          context: context,
          amount: amount,
          title: 'سداد عمولة غيارك المستحقة',
          orderType: 'debt',
          referenceId: widget.profile.id,
          email: widget.profile.email,
          phone: widget.profile.phone,
          name: widget.profile.fullName,
        );
        if (!paid) return;
      }

      await _settleDebtInDb(
        amount,
        _method,
        'سداد عمولة عبر $_method',
      );

      if (!mounted) return;
      _showTopToast(
        'تم سداد العمولة بنجاح',
        _method == 'cash_admin'
            ? 'تم تسجيل طلب التسوية النقدية مع الإدارة (${amount.toStringAsFixed(2)} د.أ).'
            : 'تم خصم ${amount.toStringAsFixed(2)} د.أ من العمولات المستحقة.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      _showTopToast('تعذر إتمام السداد', '$e', isError: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Widget _methodTile({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final selected = _method == value;
    return GestureDetector(
      onTap: enabled ? () => setState(() => _method = value) : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.orangeLight : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.orange : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppColors.orange : AppColors.navy,
                  size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppColors.navy,
                      ),
                    ),
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
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.orange : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'دفع العمولة المستحقة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'إجمالي العمولة المستحقة: ${widget.debtAmount.toStringAsFixed(2)} د.أ',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ المراد دفعه (د.أ)',
                prefixIcon: const Icon(Icons.payments_outlined),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'اختر وسيلة الدفع:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            _methodTile(
              value: 'visa',
              icon: Icons.credit_card,
              title: 'Visa / Mastercard',
              subtitle: 'الدفع الإلكتروني الآمن عبر MEPS',
            ),
            if (_isIos || kIsWeb)
              _methodTile(
                value: 'apple_pay',
                icon: Icons.apple,
                title: 'Apple Pay',
                subtitle: 'جاهز للربط بحساب مطوري Apple',
              ),
            if (_isAndroid || kIsWeb)
              _methodTile(
                value: 'google_pay',
                icon: Icons.g_mobiledata_rounded,
                title: 'Google Pay',
                subtitle: 'جاهز للربط بحساب مطوري Google',
              ),
            _methodTile(
              value: 'wallet',
              icon: Icons.account_balance_wallet_outlined,
              title: 'خصم من رصيد المحفظة',
              subtitle:
                  'الرصيد المتاح: ${widget.walletBalance.toStringAsFixed(2)} د.أ',
              enabled: _canUseWallet,
            ),
            _methodTile(
              value: 'cash_admin',
              icon: Icons.handshake_outlined,
              title: 'تسوية نقدية مع إدارة غيارك',
              subtitle: 'تسجيل طلب سداد كاش وتأكيده من الإدارة',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _processing ? null : _submit,
                child: _processing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'تأكيد دفع العمولة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}