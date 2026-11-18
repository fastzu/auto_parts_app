class PlanDetails {
  final String code;
  final String title;
  final double priceJod;
  final int durationDays;
  final double commissionRate;
  final bool trustedBadge;
  final bool boostedVisibility;
  final int maxPostsLimit;
  final int monthlyFreeAds;
  final List<String> features;

  const PlanDetails({
    required this.code,
    required this.title,
    required this.priceJod,
    required this.durationDays,
    required this.commissionRate,
    this.trustedBadge = false,
    this.boostedVisibility = false,
    this.maxPostsLimit = 5,
    this.monthlyFreeAds = 0,
    required this.features,
  });
}

class AppSubscriptionCatalog {
  static const List<PlanDetails> customerPlans = [
    PlanDetails(
      code: 'free',
      title: 'العضوية المجانية',
      priceJod: 0.0,
      durationDays: 0,
      commissionRate: 0.02,
      features: [
        'عمولة 2% عند شراء القطع أو دفع خدمات الورشة',
      ],
    ),
    PlanDetails(
      code: 'customer_pro',
      title: 'عضوية البرو (لمدة شهر)',
      priceJod: 1.95,
      durationDays: 30,
      commissionRate: 0.0,
      features: [
        'معفى من العمولة (0%) على جميع القطع والخدمات',
        'خصومات على جميع القطع والخدمات',
      ],
    ),
  ];

  static const List<PlanDetails> providerPlans = [
    PlanDetails(
      code: 'free',
      title: 'الباقة المجانية',
      priceJod: 0.0,
      durationDays: 0,
      commissionRate: 0.15,
      maxPostsLimit: 5,
      features: [
        'عمولة المنصة 15%',
        'حد أقصى 5 منشورات',
      ],
    ),
    PlanDetails(
      code: 'provider_1m',
      title: 'اشتراك شهر',
      priceJod: 1.95,
      durationDays: 30,
      commissionRate: 0.10,
      trustedBadge: true,
      maxPostsLimit: 50,
      features: [
        'عمولة (10%)',
        'علامة تاجر موثوق',
      ],
    ),
    PlanDetails(
      code: 'provider_3m',
      title: 'اشتراك 3 أشهر',
      priceJod: 3.95,
      durationDays: 90,
      commissionRate: 0.065,
      trustedBadge: true,
      boostedVisibility: true,
      maxPostsLimit: 150,
      features: [
        'عمولة أقل (6.5%)',
        'علامة تاجر موثوق',
        'ظهور أكثر في نتائج البحث والرئيسية',
      ],
    ),
    PlanDetails(
      code: 'provider_6m',
      title: 'اشتراك 6 أشهر',
      priceJod: 9.95,
      durationDays: 180,
      commissionRate: 0.025,
      trustedBadge: true,
      boostedVisibility: true,
      maxPostsLimit: 500,
      features: [
        'العمولة (2.5%)',
        'علامة تاجر موثوق',
        'ظهور أكثر في نتائج البحث والرئيسية',
      ],
    ),
    PlanDetails(
      code: 'provider_12m',
      title: 'اشتراك 12 شهر',
      priceJod: 24.95,
      durationDays: 365,
      commissionRate: 0.0,
      trustedBadge: true,
      boostedVisibility: true,
      maxPostsLimit: 9999,
      monthlyFreeAds: 1,
      features: [
        'بدون عمولة (0%)',
        'علامة تاجر موثوق',
        'ظهور أكثر في نتائج البحث والرئيسية',
        'إعلان 1 في الصفحة الرئيسية كل شهر',
      ],
    ),
  ];

  static double customerFeeRate(String subscriptionPlan) {
    return subscriptionPlan == 'customer_pro' ? 0.0 : 0.02;
  }

  static PlanDetails getProviderPlan(String code) {
    return providerPlans.firstWhere(
      (p) => p.code == code,
      orElse: () => providerPlans.first,
    );
  }
}
