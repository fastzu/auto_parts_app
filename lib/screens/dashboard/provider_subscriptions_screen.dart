import 'package:material_ui/material_ui.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class ProviderSubscriptionsScreen extends StatelessWidget {
  final String currentPlanCode;
  final VoidCallback onSubscribed;

  const ProviderSubscriptionsScreen({
    super.key,
    required this.currentPlanCode,
    required this.onSubscribed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('باقات التاجر والورشة والونش')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(AppSubscriptionCatalog.providerPlans.length, (i) {
          final plan = AppSubscriptionCatalog.providerPlans[i];
          final isCurrent = currentPlanCode == plan.code;
          final isZeroComm = plan.commissionRate == 0.0;

          return FadeSlideIn(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isCurrent
                      ? AppColors.orange
                      : (isZeroComm ? AppColors.navy : AppColors.border),
                  width: (isCurrent || isZeroComm) ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.title,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          if (plan.trustedBadge) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, color: Colors.blue, size: 18),
                          ],
                        ],
                      ),
                      Text(
                        plan.priceJod == 0 ? 'مجاني' : '${plan.priceJod} د.أ',
                        style: const TextStyle(
                          fontSize: 17,
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
                          Icon(
                            isZeroComm ? Icons.star : Icons.check_circle,
                            size: 17,
                            color: isZeroComm ? AppColors.orange : AppColors.success,
                          ),
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