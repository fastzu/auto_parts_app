import 'package:material_ui/material_ui.dart';
import '../../models/subscription_plans.dart';
import '../../services/app_locale_service.dart';
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
    final loc = AppLocaleService.instance;
    return ValueListenableBuilder<String>(
      valueListenable: loc.langCode,
      builder: (_, __, ___) {
        return Scaffold(
          appBar: AppBar(
            title: Text(loc.tr(
              'باقات التاجر والورشة والونش',
              'Merchant, Workshop & Towing Plans',
            )),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(
              AppSubscriptionCatalog.providerPlans.length,
              (i) {
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
                            Flexible(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      plan.title,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (plan.trustedBadge) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.verified,
                                      color: Colors.blue,
                                      size: 18,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              plan.priceJod == 0
                                  ? loc.tr('مجاني', 'Free')
                                  : '${plan.priceJod} ${loc.tr("د.أ", "JOD")}',
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
                                  color: isZeroComm
                                      ? AppColors.orange
                                      : AppColors.success,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCurrent
                                  ? AppColors.navy
                                  : AppColors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: (isCurrent || plan.priceJod == 0)
                                ? null
                                : () async {
                                    final navigator = Navigator.of(context);
                                    final ok = await PayTabsPaymentService()
                                        .startPaymentFlow(
                                      context: context,
                                      baseAmount: plan.priceJod,
                                      title: plan.title,
                                      orderType: 'sub',
                                      referenceId: plan.code,
                                    );
                                    if (!ok) return;
                                    onSubscribed();
                                    if (navigator.canPop()) navigator.pop();
                                  },
                            child: Text(
                              isCurrent
                                  ? loc.tr('باقتك الحالية', 'Current Plan')
                                  : loc.tr('اشترك الآن (الدفع)',
                                      'Subscribe & Checkout'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        if (plan.priceJod > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.history_toggle_off_rounded,
                                  size: 16,
                                  color: AppColors.navy,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    loc.tr(
                                      'يمكنك طلب استرداد قيمة الباقة (Refund) خلال 24 ساعة فقط من تاريخ الاشتراك وفق الشروط والأحكام.',
                                      'You may request a subscription refund within 24 hours of purchase only, subject to Terms & Conditions.',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}