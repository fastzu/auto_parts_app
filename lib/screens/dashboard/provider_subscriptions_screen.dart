import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class ProviderSubscriptionsScreen extends StatefulWidget {
  final String currentPlanCode;
  final VoidCallback onSubscribed;

  const ProviderSubscriptionsScreen({
    super.key,
    required this.currentPlanCode,
    required this.onSubscribed,
  });

  @override
  State<ProviderSubscriptionsScreen> createState() =>
      _ProviderSubscriptionsScreenState();
}

class _ProviderSubscriptionsScreenState
    extends State<ProviderSubscriptionsScreen> {
  final _db = Supabase.instance.client;
  late String _activePlanCode = widget.currentPlanCode;
  bool _cancelling = false;

  Future<void> _cancelProviderMembership() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إلغاء اشتراك المزود',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل أنت متأكد من إلغاء عضويتك الحالية؟\n\nسيعود حسابك إلى الباقة المجانية (عمولة 15% وحد أقصى 5 منشورات).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء العضوية'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await _db.from('customers').update({
        'subscription_plan': 'free',
        'subscription_expires_at': null,
        'commission_rate': 0.15,
        'max_posts_limit': 5,
        'is_trusted_merchant': false,
      }).eq('id', uid);

      setState(() => _activePlanCode = 'free');
      widget.onSubscribed();

      if (mounted) {
        _showTopNotice(
          title: 'تم إلغاء العضوية',
          message: 'تم إرجاع حسابك إلى الباقة المجانية بنجاح.',
        );
      }
    } catch (e) {
      if (mounted) {
        _showTopNotice(
          title: 'تعذر إلغاء العضوية',
          message: '$e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _showTopNotice({
    required String title,
    required String message,
    bool isError = false,
  }) {
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

  @override
  Widget build(BuildContext context) {
    final hasPaidPlan = _activePlanCode != 'free';

    return Scaffold(
      appBar: AppBar(title: const Text('باقات التاجر والورشة والونش')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...List.generate(AppSubscriptionCatalog.providerPlans.length, (i) {
            final plan = AppSubscriptionCatalog.providerPlans[i];
            final isCurrent = _activePlanCode == plan.code;
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
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            if (plan.trustedBadge) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified,
                                  color: Colors.blue, size: 18),
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
                              color: isZeroComm
                                  ? AppColors.orange
                                  : AppColors.success,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(f,
                                    style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isCurrent ? AppColors.navy : AppColors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: (isCurrent || plan.priceJod == 0)
                            ? null
                            : () async {
                                final ok = await PayTabsPaymentService()
                                    .startPaymentFlow(
                                  context: context,
                                  baseAmount: plan.priceJod,
                                  title: plan.title,
                                  orderType: 'sub',
                                  referenceId: plan.code,
                                );
                                if (ok && mounted) {
                                  widget.onSubscribed();
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

          if (hasPaidPlan) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'إلغاء الاشتراك الحالي',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'عند إلغاء العضوية سيعود الحساب للباقة المجانية (عمولة 15% وحد 5 منشورات).',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed:
                          _cancelling ? null : _cancelProviderMembership,
                      icon: _cancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.red,
                              ),
                            )
                          : const Icon(Icons.person_off_outlined),
                      label: const Text(
                        'إلغاء العضوية',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}