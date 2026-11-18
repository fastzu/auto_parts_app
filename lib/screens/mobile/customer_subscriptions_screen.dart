import 'package:material_ui/material_ui.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class CustomerSubscriptionsScreen extends StatelessWidget {
  final String currentPlanCode;
  final VoidCallback onSubscribed;

  const CustomerSubscriptionsScreen({
    super.key,
    required this.currentPlanCode,
    required this.onSubscribed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عضوية المستخدم')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(AppSubscriptionCatalog.customerPlans.length, (i) {
          final plan = AppSubscriptionCatalog.customerPlans[i];
          final isCurrent = currentPlanCode == plan.code;

          return FadeSlideIn(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isCurrent ? AppColors.orange : AppColors.border,
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        plan.title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        plan.priceJod == 0 ? 'مجاني' : '${plan.priceJod} د.أ / شهر',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...plan.features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 17, color: AppColors.success),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrent ? AppColors.navy : AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: (isCurrent || plan.priceJod == 0)
                          ? null
                          : () async {
                              final ok = await PayTabsPaymentService().startPaymentFlow(
                                context: context,
                                baseAmount: plan.priceJod,
                                title: plan.title,
                                orderType: 'sub',
                                referenceId: plan.code,
                              );
                              if (ok && context.mounted) {
                                onSubscribed();
                                Navigator.pop(context);
                              }
                            },
                      child: Text(isCurrent ? 'باقتك الحالية' : 'اشترك الآن'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}