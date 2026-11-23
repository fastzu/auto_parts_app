class PlanDetails {
  final String code;
  final String title;
  final double priceJod;
  final int durationDays;
  final double commissionRate;
  final bool trustedBadge;
  final bool boostedVisibility;
  final int maxPostsLimit; // -1 تعني منشورات لا نهائية
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

  bool get isUnlimitedPosts => maxPostsLimit < 0;

  String get postsLimitLabel =>
      isUnlimitedPosts ? 'منشورات لا نهائية' : 'حتى $maxPostsLimit منشور';
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
        'عمولة 2% عند دفع خدمات الورش والطوارئ',
      ],
    ),
    PlanDetails(
      code: 'customer_pro',
      title: 'عضوية البرو (لمدة شهر)',
      priceJod: 1.95,
      durationDays: 30,
      commissionRate: 0.0,
      features: [
        'معفى من العمولة (0%) على جميع الورش والخدمات',
        'خصومات حصرية على الخدمات والورش',
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
      maxPostsLimit: 15,
      features: [
        'حتى 15 منشور قطع غيار',
        'عمولة مخفضة (10%)',
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
      maxPostsLimit: 30,
      features: [
        'حتى 30 منشور قطع غيار',
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
      maxPostsLimit: 45,
      features: [
        'حتى 45 منشور قطع غيار',
        'عمولة مميزة (2.5%)',
        'علامة تاجر موثوق',
        'ظهور أكثر في نتائج البحث والرئيسية',
      ],
    ),
    PlanDetails(
      code: 'provider_12m',
      title: 'اشتراك 12 شهر (سنوي)',
      priceJod: 24.95,
      durationDays: 365,
      commissionRate: 0.0,
      trustedBadge: true,
      boostedVisibility: true,
      maxPostsLimit: -1, // لا نهائي
      monthlyFreeAds: 1,
      features: [
        'منشورات لا نهائية (بدون حد أقصى)',
        'بدون عمولة (0%)',
        'علامة تاجر موثوق',
        'ظهور أولوية في البحث والرئيسية',
        'إعلان مجاني في الصفحة الرئيسية كل شهر',
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