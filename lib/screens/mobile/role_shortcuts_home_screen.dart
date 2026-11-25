import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/status_labels.dart';
import '../../widgets/animations.dart';
import '../../widgets/home_live_progress_banner.dart';
import '../dashboard/merchant_products_dashboard.dart';
import '../dashboard/provider_subscriptions_screen.dart';
import '../dashboard/super_admin_dashboard_screen.dart';
import '../dashboard/towing_dashboard_screen.dart';
import '../dashboard/workshop_emergency_dashboard.dart';
import 'add_product_screen.dart';
import 'ai_diagnostic_screen.dart';
import 'book_workshop_screen.dart';
import 'chat_screen.dart';
import 'customer_subscriptions_screen.dart';

class RoleShortcutsHomeScreen extends StatelessWidget {
  final CustomerProfile profile;
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSelectTab; // 0=Shortcuts, 1=Store, 2=Emergency, 3=Appointments, 4=Profile
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenSupport;
  final VoidCallback onRefreshProfile;
  final VoidCallback onSignedOut;

  const RoleShortcutsHomeScreen({
    super.key,
    required this.profile,
    required this.onOpenDrawer,
    required this.onSelectTab,
    required this.onOpenWallet,
    required this.onOpenSupport,
    required this.onRefreshProfile,
    required this.onSignedOut,
  });

  void _showTermsAndPrivacySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
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
                const Text(
                  'الشروط والأحكام وسياسة الخصوصية',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '• يلتزم التجار والورش وسائقو الونش بتقديم معلومات دقيقة وأسعار واضحة.\n'
                  '• تُستخدم بيانات الموقع الجغرافي فقط لتتبع طلبات الطوارئ والورش النشطة وتحديد أقرب مزود خدمة.\n'
                  '• المدفوعات الإلكترونية والعمولات والسحوبات البنكية تُدار بشفافية وتُسجل في سجل المحفظة.\n'
                  '• يحق لإدارة غيارك تعليق أي حساب مخالف للشروط أو متأخر عن سداد العمولات المستحقة.\n'
                  '• لأي استفسار أو طلب حذف بيانات، يمكنك التواصل معنا مباشرة عبر قسم الدعم الفني.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.65,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('فهمت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_ShortcutItem> _buildShortcuts(BuildContext context) {
    final isAdmin = profile.isAdmin || profile.role == 'admin';
    final role = isAdmin ? 'admin' : profile.role;
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showSubs = EnvConfig.subscriptionsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;

    if (role == 'admin') {
      return [
        _ShortcutItem(
          title: 'لوحة السوبر أدمن',
          subtitle: 'إدارة التطبيق والطلبات والمالية',
          icon: Icons.admin_panel_settings,
          color: AppColors.orange,
          highlight: true,
          onTap: () => Navigator.push(
            context,
            animatedRoute(SuperAdminDashboardScreen(
                profile: profile, onSignedOut: onSignedOut)),
          ),
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'تصفح القطع والعروض والبحث',
          icon: Icons.storefront,
          color: AppColors.navy,
          onTap: () => onSelectTab(1),
        ),
        _ShortcutItem(
          title: 'طلبات الطوارئ',
          subtitle: 'متابعة طلبات الونش والطوارئ',
          icon: Icons.car_crash_outlined,
          color: Colors.redAccent,
          onTap: () => onSelectTab(2),
        ),
        _ShortcutItem(
          title: 'مواعيد الورش',
          subtitle: 'متابعة حجوزات الورش',
          icon: Icons.event_note_outlined,
          color: Colors.teal,
          onTap: () => onSelectTab(3),
        ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر منتج جديد في المتجر',
          icon: Icons.add_box_outlined,
          color: Colors.indigo,
          onTap: () =>
              Navigator.push(context, animatedRoute(const AddProductScreen())),
        ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'المحادثات مع التجار والزبائن',
          icon: Icons.chat_bubble_outline,
          color: Colors.blue,
          onTap: () =>
              Navigator.push(context, animatedRoute(const ChatsListScreen())),
        ),
        _ShortcutItem(
          title: 'الإشعارات',
          subtitle: 'عرض التنبيهات والرسائل',
          icon: Icons.notifications_active_outlined,
          color: Colors.deepPurple,
          onTap: () =>
              NotificationsService.instance.openNotificationsSheet(context),
        ),
        _ShortcutItem(
          title: 'فحص الأعطال AI',
          subtitle: 'تشخيص فوري لمشاكل السيارات',
          icon: Icons.auto_awesome,
          color: AppColors.navy,
          onTap: () => showAiDiagnosticSheet(context, viewerProfile: profile),
        ),
      ];
    }

    if (role == 'merchant') {
      return [
        _ShortcutItem(
          title: 'لوحة منتجاتي',
          subtitle: 'إخفاء/إظهار، خصومات وتعديل الأسعار',
          icon: Icons.inventory_2_outlined,
          color: AppColors.orange,
          highlight: true,
          onTap: () => Navigator.push(
              context, animatedRoute(const MerchantProductsDashboard())),
        ),
        _ShortcutItem(
          title: 'إضافة قطعة جديدة',
          subtitle: 'انشر قطعة غيار خلال ثوانٍ',
          icon: Icons.add_circle_outline,
          color: AppColors.success,
          onTap: () =>
              Navigator.push(context, animatedRoute(const AddProductScreen())),
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'تصفح السوق والقطع المنشورة',
          icon: Icons.storefront,
          color: AppColors.navy,
          onTap: () => onSelectTab(1),
        ),
        if (showPayments)
          _ShortcutItem(
            title: 'محفظة التاجر',
            subtitle: 'الأرباح والعمولات والتسديد',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.teal,
            onTap: onOpenWallet,
          ),
        if (showSubs)
          _ShortcutItem(
            title: 'الباقات والاشتراكات',
            subtitle: 'رفع عدد المنشورات وتقليل العمولة',
            icon: Icons.workspace_premium_outlined,
            color: Colors.amber.shade800,
            onTap: () => Navigator.push(
              context,
              animatedRoute(
                ProviderSubscriptionsScreen(
                  currentPlanCode: profile.subscriptionPlan,
                  onSubscribed: onRefreshProfile,
                ),
              ),
            ),
          ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'الرد على استفسارات الزبائن',
          icon: Icons.chat_bubble_outline,
          color: Colors.blue,
          onTap: () =>
              Navigator.push(context, animatedRoute(const ChatsListScreen())),
        ),
        _ShortcutItem(
          title: 'فحص الأعطال AI',
          subtitle: 'تحديد القطع المطلوبة للعميل',
          icon: Icons.auto_awesome,
          color: AppColors.navy,
          onTap: () => showAiDiagnosticSheet(context, viewerProfile: profile),
        ),
        _ShortcutItem(
          title: 'حسابي وإعداداتي',
          subtitle: 'تعديل الملف الشخصي والدعم',
          icon: Icons.person_outline,
          color: Colors.blueGrey,
          onTap: () => onSelectTab(4),
        ),
      ];
    }

    if (role == 'mechanic') {
      return [
        _ShortcutItem(
          title: 'لوحة الورشة والطوارئ',
          subtitle: 'استقبال المواعيد وطلبات الإنقاذ',
          icon: Icons.build_circle_outlined,
          color: AppColors.orange,
          highlight: true,
          onTap: () => Navigator.push(
            context,
            animatedRoute(
              WorkshopEmergencyDashboard(
                profile: profile,
                onRefreshProfile: onRefreshProfile,
                onSignedOut: onSignedOut,
              ),
            ),
          ),
        ),
        _ShortcutItem(
          title: 'قطع الغيار والمخزون',
          subtitle: 'إدارة القطع، الإخفاء والخصومات',
          icon: Icons.inventory_2_outlined,
          color: AppColors.navy,
          onTap: () => Navigator.push(
              context, animatedRoute(const MerchantProductsDashboard())),
        ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر قطعة من مخزون الورشة',
          icon: Icons.add_box_outlined,
          color: AppColors.success,
          onTap: () =>
              Navigator.push(context, animatedRoute(const AddProductScreen())),
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'شراء قطع لسيارات الزبائن',
          icon: Icons.storefront,
          color: Colors.indigo,
          onTap: () => onSelectTab(1),
        ),
        if (showPayments)
          _ShortcutItem(
            title: 'محفظة الورشة',
            subtitle: 'الأرباح والعمولات وسحب للبنك',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.teal,
            onTap: onOpenWallet,
          ),
        if (showSubs)
          _ShortcutItem(
            title: 'الباقات والاشتراكات',
            subtitle: 'تصدر نتائج البحث وعمولة أقل',
            icon: Icons.workspace_premium_outlined,
            color: Colors.amber.shade800,
            onTap: () => Navigator.push(
              context,
              animatedRoute(
                ProviderSubscriptionsScreen(
                  currentPlanCode: profile.subscriptionPlan,
                  onSubscribed: onRefreshProfile,
                ),
              ),
            ),
          ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل المباشر مع الزبائن',
          icon: Icons.chat_bubble_outline,
          color: Colors.blue,
          onTap: () =>
              Navigator.push(context, animatedRoute(const ChatsListScreen())),
        ),
        _ShortcutItem(
          title: 'فحص الأعطال AI',
          subtitle: 'مساعد تشخيص ذكي للأعطال',
          icon: Icons.auto_awesome,
          color: AppColors.navy,
          onTap: () => showAiDiagnosticSheet(context, viewerProfile: profile),
        ),
        _ShortcutItem(
          title: 'حسابي وإعداداتي',
          subtitle: 'معلومات الورشة وكلمة المرور',
          icon: Icons.person_outline,
          color: Colors.blueGrey,
          onTap: () => onSelectTab(4),
        ),
      ];
    }

    if (role == 'towing') {
      return [
        if (showWinch)
          _ShortcutItem(
            title: 'لوحة الونش المباشرة',
            subtitle: 'استقبال طلبات السحب وتتبع GPS',
            icon: Icons.local_shipping_outlined,
            color: AppColors.orange,
            highlight: true,
            onTap: () => Navigator.push(
              context,
              animatedRoute(
                TowingDashboardScreen(
                  profile: profile,
                  onRefreshProfile: onRefreshProfile,
                  onSignedOut: onSignedOut,
                ),
              ),
            ),
          ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'تصفح قطع الغيار والأسعار',
          icon: Icons.storefront,
          color: AppColors.navy,
          onTap: () => onSelectTab(1),
        ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر قطعة غيار للبيع',
          icon: Icons.add_box_outlined,
          color: AppColors.success,
          onTap: () =>
              Navigator.push(context, animatedRoute(const AddProductScreen())),
        ),
        if (showPayments)
          _ShortcutItem(
            title: 'محفظة الونش',
            subtitle: 'الأرباح والعمولات وسحب للبنك',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.teal,
            onTap: onOpenWallet,
          ),
        if (showSubs)
          _ShortcutItem(
            title: 'باقات المزودين',
            subtitle: 'أولوية الطلبات وعمولة أقل',
            icon: Icons.workspace_premium_outlined,
            color: Colors.amber.shade800,
            onTap: () => Navigator.push(
              context,
              animatedRoute(
                ProviderSubscriptionsScreen(
                  currentPlanCode: profile.subscriptionPlan,
                  onSubscribed: onRefreshProfile,
                ),
              ),
            ),
          ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل مع الزبائن والورش',
          icon: Icons.chat_bubble_outline,
          color: Colors.blue,
          onTap: () =>
              Navigator.push(context, animatedRoute(const ChatsListScreen())),
        ),
        _ShortcutItem(
          title: 'حسابي وإعداداتي',
          subtitle: 'بيانات الحساب والونش',
          icon: Icons.person_outline,
          color: Colors.blueGrey,
          onTap: () => onSelectTab(4),
        ),
      ];
    }

    return [
      _ShortcutItem(
        title: 'متجر قطع الغيار',
        subtitle: 'ابحث عن قطع سيارتك بأفضل سعر',
        icon: Icons.storefront,
        color: AppColors.orange,
        highlight: true,
        onTap: () => onSelectTab(1),
      ),
      _ShortcutItem(
        title: 'طلب مساعدة طارئة',
        subtitle: showWinch ? 'ونش سحب أو ميكانيكي فوري' : 'ميكانيكي طوارئ لموقعك',
        icon: Icons.car_crash_outlined,
        color: Colors.redAccent,
        onTap: () => onSelectTab(2),
      ),
      _ShortcutItem(
        title: 'حجز موعد ورشة',
        subtitle: 'اختر أقرب ورشة معتمدة لسيارتك',
        icon: Icons.build_outlined,
        color: AppColors.navy,
        onTap: () => Navigator.push(
          context,
          animatedRoute(SelectWorkshopScreen(viewerProfile: profile)),
        ),
      ),
      _ShortcutItem(
        title: 'مواعيدي وطلباتي',
        subtitle: 'متابعة حالة الصيانة والطوارئ',
        icon: Icons.event_note_outlined,
        color: Colors.teal,
        onTap: () => onSelectTab(3),
      ),
      _ShortcutItem(
        title: 'فحص الأعطال بالـ AI',
        subtitle: 'اشرح العطل واحصل على التشخيص',
        icon: Icons.auto_awesome,
        color: Colors.deepPurple,
        onTap: () => showAiDiagnosticSheet(context, viewerProfile: profile),
      ),
      _ShortcutItem(
        title: 'الدردشات',
        subtitle: 'تواصلك المباشر مع التجار والورش',
        icon: Icons.chat_bubble_outline,
        color: Colors.blue,
        onTap: () =>
            Navigator.push(context, animatedRoute(const ChatsListScreen())),
      ),
      if (showSubs)
        _ShortcutItem(
          title: 'باقة البرو (Pro)',
          subtitle: 'خصومات حصرية وأولوية خدمة',
          icon: Icons.workspace_premium_outlined,
          color: Colors.amber.shade800,
          onTap: () => Navigator.push(
            context,
            animatedRoute(
              CustomerSubscriptionsScreen(
                currentPlanCode: profile.subscriptionPlan,
                onSubscribed: onRefreshProfile,
              ),
            ),
          ),
        ),
      _ShortcutItem(
        title: 'حسابي وإعداداتي',
        subtitle: 'بياناتك، كلمة المرور والدعم',
        icon: Icons.person_outline,
        color: Colors.blueGrey,
        onTap: () => onSelectTab(4),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = profile.isAdmin || profile.role == 'admin';
    final roleLabel = StatusLabels.role(isAdmin ? 'admin' : profile.role);
    final items = _buildShortcuts(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'القائمة الجانبية',
          onPressed: onOpenDrawer,
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GhiyarakLogo(size: 30),
            SizedBox(width: 8),
            Text('غيارك', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'الدردشات',
            onPressed: () =>
                Navigator.push(context, animatedRoute(const ChatsListScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: 'الإشعارات',
            onPressed: () =>
                NotificationsService.instance.openNotificationsSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, Color(0xFF1F2D3D)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.orange,
                    child: Icon(Icons.person, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أهلاً بك، ${profile.fullName ?? profile.username ?? "صديق غيارك"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.orange,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                roleLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (profile.isTrustedMerchant)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified,
                                        color: Colors.lightBlueAccent,
                                        size: 13),
                                    SizedBox(width: 4),
                                    Text(
                                      'حساب موثّق',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: HomeLiveProgressBanner(viewerProfile: profile),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.grid_view_rounded,
                    color: AppColors.orange, size: 20),
                SizedBox(width: 6),
                Text(
                  'اختصارات الوصول السريع',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.18,
              ),
              itemBuilder: (ctx, i) {
                final item = items[i];
                return FadeSlideIn(
                  index: i,
                  child: BounceTap(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      item.onTap();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            item.highlight ? AppColors.orangeLight : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: item.highlight
                              ? AppColors.orange.withValues(alpha: 0.7)
                              : AppColors.border,
                          width: item.highlight ? 1.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child:
                                Icon(item.icon, color: item.color, size: 24),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.25,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onOpenSupport,
                      icon: const Icon(Icons.support_agent,
                          color: AppColors.orange, size: 18),
                      label: const Text('الدعم الفني',
                          style: TextStyle(color: AppColors.navy)),
                    ),
                  ),
                  Container(width: 1, height: 22, color: AppColors.border),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _showTermsAndPrivacySheet(context),
                      icon: const Icon(Icons.privacy_tip_outlined,
                          color: AppColors.navy, size: 18),
                      label: const Text('الشروط والخصوصية',
                          style: TextStyle(color: AppColors.navy)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool highlight;
  final VoidCallback onTap;

  const _ShortcutItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.highlight = false,
    required this.onTap,
  });
}