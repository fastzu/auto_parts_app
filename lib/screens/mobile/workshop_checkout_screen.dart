import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/customer_subscriptions_screen.dart';

class WorkshopCheckoutScreen extends StatefulWidget {
  final DbWorkshopAppointment appointment;
  final CustomerProfile customerProfile;
  final VoidCallback onPaymentCompleted;

  const WorkshopCheckoutScreen({
    super.key,
    required this.appointment,
    required this.customerProfile,
    required this.onPaymentCompleted,
  });

  @override
  State<WorkshopCheckoutScreen> createState() => _WorkshopCheckoutScreenState();
}

class _WorkshopCheckoutScreenState extends State<WorkshopCheckoutScreen> {
  final _db = Supabase.instance.client;
  final _payService = PayTabsPaymentService();
  final _promoCtrl = TextEditingController();

  bool _checkingPromo = false;
  bool _paying = false;
  String? _appliedCode;
  double _appliedPercent = 0.0;
  double _discountAmount = 0.0;
  String? _promoError;

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyDiscountCode() async {
    FocusScope.of(context).unfocus();
    final raw = _promoCtrl.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _checkingPromo = true;
      _promoError = null;
    });

    try {
      final res = await _payService.validateDiscountCode(
        rawCode: raw,
        baseAmount: widget.appointment.totalAmount,
        userRole: widget.customerProfile.role,
      );
      if (!mounted) return;
      setState(() {
        _appliedCode = res.code;
        _appliedPercent = res.percent;
        _discountAmount = res.discountAmount;
        _checkingPromo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تطبيق خصم ${res.code} (-${res.percent.toInt()}%) بقيمة ${res.discountAmount.toStringAsFixed(2)} د.أ',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingPromo = false;
        _promoError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _startCheckout(
    double discountedBase,
    double customerFee,
  ) async {
    if (_paying) return;
    setState(() => _paying = true);

    try {
      // حفظ كود الخصم على موعد الورشة قبل الدفع
      if (_appliedCode != null && _discountAmount > 0) {
        try {
          await _db.from('workshop_appointments').update({
            'discount_code': _appliedCode,
            'discount_amount': _discountAmount,
          }).eq('id', widget.appointment.id);
        } catch (_) {}
      }

      if (!mounted) return;
      final shortId = widget.appointment.id.length >= 6
          ? widget.appointment.id.substring(0, 6)
          : widget.appointment.id;

      final ok = await _payService.startPaymentFlow(
        context: context,
        baseAmount: discountedBase,
        feeAmount: customerFee,
        title: 'دفع فاتورة ورشة #$shortId',
        orderType: 'wrk',
        referenceId: widget.appointment.id,
        email: widget.customerProfile.email,
        phone: widget.customerProfile.phone,
        name: widget.customerProfile.fullName,
        discountCode: _appliedCode,
        discountAmount: _discountAmount,
        userRole: widget.customerProfile.role,
      );

      if (ok && mounted) {
        widget.onPaymentCompleted();
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double mechanicAmount = widget.appointment.totalAmount;
    final double discountedBase = double.parse(
      (mechanicAmount - _discountAmount)
          .clamp(0.0, double.infinity)
          .toStringAsFixed(2),
    );
    final double feeRate = AppSubscriptionCatalog.customerFeeRate(
      widget.customerProfile.subscriptionPlan,
    );
    final double customerFee =
        double.parse((discountedBase * feeRate).toStringAsFixed(2));
    final double totalToPay =
        double.parse((discountedBase + customerFee).toStringAsFixed(2));
    final bool isPro = feeRate == 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('إتمام دفع الورشة')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تفاصيل الفاتورة',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.appointment.serviceDescription ?? 'صيانة مركبة',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const Divider(height: 24),
                    _row(
                      'تكلفة الصيانة (قبل العمولة)',
                      '${mechanicAmount.toStringAsFixed(2)} د.أ',
                    ),
                    if (_discountAmount > 0) ...[
                      const SizedBox(height: 10),
                      _row(
                        'خصم الكود (${_appliedCode ?? ''} - ${_appliedPercent.toInt()}%)',
                        '-${_discountAmount.toStringAsFixed(2)} د.أ',
                        valueColor: AppColors.success,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _row(
                      isPro
                          ? 'عمولة التطبيق (عضوية برو)'
                          : 'عمولة الخدمة (2% - المجانية)',
                      isPro
                          ? '0.00 د.أ (معفى)'
                          : '${customerFee.toStringAsFixed(2)} د.أ',
                      valueColor: isPro ? AppColors.success : AppColors.orange,
                    ),
                    const Divider(height: 24),
                    _row(
                      'الإجمالي المطلوب للدفع',
                      '${totalToPay.toStringAsFixed(2)} د.أ',
                      isBold: true,
                      valueColor: AppColors.navy,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // قسم كود الخصم
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'استخدام كود خصم',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promoCtrl,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _applyDiscountCode(),
                          decoration: InputDecoration(
                            hintText: 'أدخل كود الخصم',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                        ),
                        onPressed: _checkingPromo ? null : _applyDiscountCode,
                        child: _checkingPromo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('تطبيق'),
                      ),
                    ],
                  ),
                  if (_promoError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _promoError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  if (_appliedCode != null && _discountAmount > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'الكود $_appliedCode مفعّل (-${_discountAmount.toStringAsFixed(2)} د.أ)',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _appliedCode = null;
                              _appliedPercent = 0;
                              _discountAmount = 0;
                              _promoCtrl.clear();
                            });
                          },
                          child: const Text('إزالة',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),
            if (!isPro)
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    animatedRoute(CustomerSubscriptionsScreen(
                      currentPlanCode: widget.customerProfile.subscriptionPlan,
                      onSubscribed: widget.onPaymentCompleted,
                    )),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.workspace_premium, color: AppColors.orange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'اشترك بباقة البرو بـ 1.95 د.أ/شهر وألغِ عمولة الـ 2% مع خصومات على القطع!',
                          style: TextStyle(
                              color: AppColors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios,
                          size: 14, color: AppColors.orange),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            BounceTap(
              onTap: _paying
                  ? () {}
                  : () => _startCheckout(discountedBase, customerFee),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _paying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'متابعة الدفع (${totalToPay.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String val,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500),
          ),
        ),
        Text(
          val,
          style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.bold,
              fontSize: isBold ? 17 : 14,
              color: valueColor),
        ),
      ],
    );
  }
}