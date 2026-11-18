import 'package:material_ui/material_ui.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/customer_subscriptions_screen.dart';

class WorkshopCheckoutScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final double mechanicAmount = appointment.totalAmount;
    final double feeRate = AppSubscriptionCatalog.customerFeeRate(
      customerProfile.subscriptionPlan,
    );
    final double customerFee =
        double.parse((mechanicAmount * feeRate).toStringAsFixed(2));
    final double totalToPay =
        double.parse((mechanicAmount + customerFee).toStringAsFixed(2));
    final bool isPro = feeRate == 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('إتمام دفع الورشة (Checkout)')),
      body: Padding(
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
                    const Text('تفاصيل الفاتورة',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(appointment.serviceDescription ?? 'صيانة مركبة',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    const Divider(height: 24),
                    _row('تكلفة الصيانة (قبل العمولة)',
                        '${mechanicAmount.toStringAsFixed(2)} د.أ'),
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
            if (!isPro)
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    animatedRoute(CustomerSubscriptionsScreen(
                      currentPlanCode: customerProfile.subscriptionPlan,
                      onSubscribed: onPaymentCompleted,
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
            const Spacer(),
            BounceTap(
              onTap: () async {
                final ok = await PayTabsPaymentService().payWithCardRedirect(
                  context: context,
                  amount: totalToPay,
                  title: 'دفع فاتورة ورشة #${appointment.id.substring(0, 6)}',
                  orderType: 'wrk',
                  referenceId: appointment.id,
                  email: customerProfile.email,
                  phone: customerProfile.phone,
                  name: customerProfile.fullName,
                );
                if (ok && context.mounted) {
                  onPaymentCompleted();
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'الدفع الآن عبر MEPS (${totalToPay.toStringAsFixed(2)} د.أ)',
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
        Text(label,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
        Text(val,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.w800 : FontWeight.bold,
                fontSize: isBold ? 17 : 14,
                color: valueColor)),
      ],
    );
  }
}
