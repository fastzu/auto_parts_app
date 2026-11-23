import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/home_live_progress_banner.dart';
import '../auth/auth_screens.dart';
import '../dashboard/merchant_products_dashboard.dart';
import '../dashboard/provider_subscriptions_screen.dart';
import '../dashboard/super_admin_dashboard_screen.dart';
import '../dashboard/towing_dashboard_screen.dart';
import '../dashboard/workshop_emergency_dashboard.dart';
import 'add_product_screen.dart';
import 'ai_diagnostic_screen.dart';
import 'chat_screen.dart';
import 'customer_appointments_screen.dart';
import 'customer_subscriptions_screen.dart';
import 'emergency_screen.dart';
import 'live_store_home_screen.dart';

class LiveMobileShell extends StatefulWidget {
  final CustomerProfile? profile;
  final VoidCallback onRefreshProfile;
  final VoidCallback onSignedOut;

  const LiveMobileShell({
    super.key,
    required this.profile,
    required this.onRefreshProfile,
    required this.onSignedOut,
  });

  @override
  State<LiveMobileShell> createState() => _LiveMobileShellState();
}

class _LiveMobileShellState extends State<LiveMobileShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _notifs = NotificationsService.instance;
  final _db = Supabase.instance.client;

  // 0 = الرئيسية (الاختصارات) | 1 = المتجر | 2 = طوارئ | 3 = المواعيد | 4 = حسابي
  int _index = 0;
  bool _checkingQuota = false;

  @override
  void initState() {
    super.initState();
    final uid = widget.profile?.id ?? _db.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) {
      _notifs.startRealtimeListener(uid);
    }
  }

  @override
  void didUpdateWidget(covariant LiveMobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.profile?.id;
    final newId = widget.profile?.id;
    if (oldId != newId) {
      if (newId != null && newId.isNotEmpty) {
        _notifs.startRealtimeListener(newId);
      } else {
        _notifs.stopRealtimeListener();
      }
    }
  }

  void _openDashboardForRole(CustomerProfile p) {
    final isAdmin = p.isAdmin || p.role == 'admin';
    Widget target;
    if (isAdmin) {
      target = SuperAdminDashboardScreen(
        profile: p,
        onSignedOut: widget.onSignedOut,
      );
    } else if (p.role == 'mechanic') {
      target = WorkshopEmergencyDashboard(
        profile: p,
        onRefreshProfile: widget.onRefreshProfile,
        onSignedOut: widget.onSignedOut,
      );
    } else if (p.role == 'towing' && EnvConfig.winchEnabled.value) {
      target = TowingDashboardScreen(
        profile: p,
        onRefreshProfile: widget.onRefreshProfile,
        onSignedOut: widget.onSignedOut,
      );
    } else {
      target = const MerchantProductsDashboard();
    }
    Navigator.push(context, animatedRoute(target));
  }

  void _openProviderWallet(CustomerProfile p) {
    final title = switch (p.role) {
      'mechanic' => 'محفظة الورشة والميكانيكي',
      'towing' => 'محفظة الونش',
      _ => 'محفظة التاجر',
    };
    Navigator.push(
      context,
      animatedRoute(
        Scaffold(
          appBar: AppBar(title: Text(title)),
          body: _ProviderWalletView(profile: p, headerLabel: 'صافي $title (بعد العمولة)'),
        ),
      ),
    );
  }

  void _openCustomerPaymentsHistory(CustomerProfile? p) {
    if (p == null) {
      Navigator.push(
        context,
        animatedRoute(LoginScreen(onAuthenticated: widget.onRefreshProfile)),
      );
      return;
    }
    Navigator.push(
      context,
      animatedRoute(CustomerPaymentsHistoryScreen(profile: p)),
    );
  }

  void _openSupportScreen() =>
      Navigator.push(context, animatedRoute(const SupportScreen()));

  Future<void> _handleAddProductTap() async {
    final p = widget.profile;
    if (p == null) {
      Navigator.push(
        context,
        animatedRoute(LoginScreen(onAuthenticated: widget.onRefreshProfile)),
      );
      return;
    }
    if (_checkingQuota) return;

    final isAdmin = p.isAdmin || p.role == 'admin';
    if (isAdmin) {
      Navigator.push(context, animatedRoute(const AddProductScreen()));
      return;
    }

    setState(() => _checkingQuota = true);
    try {
      final settings = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', ['enable_post_limits', 'default_max_posts']);
      final sMap = {
        for (final r in settings) r['key'] as String: r['value'] as String
      };
      final limitsEnabled = sMap['enable_post_limits'] != 'false';

      if (limitsEnabled) {
        final cust = await _db
            .from('customers')
            .select('subscription_plan, max_posts_limit')
            .eq('id', p.id)
            .maybeSingle();

        final planCode =
            (cust?['subscription_plan'] as String?) ?? p.subscriptionPlan;
        final plan = AppSubscriptionCatalog.getProviderPlan(planCode);
        final dbLimit = cust?['max_posts_limit'] as int?;
        final int effectiveLimit = dbLimit ?? plan.maxPostsLimit;
        final isUnlimited = planCode == 'provider_12m' ||
            effectiveLimit < 0 ||
            effectiveLimit >= 9999;

        if (!isUnlimited) {
          final rows =
              await _db.from('products').select('id').eq('user_id', p.id);
          final used = rows.length;
          if (used >= effectiveLimit) {
            if (!mounted) return;
            await _showUpgradePlanPrompt(
              usedCount: used,
              maxLimit: effectiveLimit,
              currentPlanCode: planCode,
            );
            return;
          }
        }
      }

      if (!mounted) return;
      Navigator.push(context, animatedRoute(const AddProductScreen()));
    } catch (_) {
      if (!mounted) return;
      Navigator.push(context, animatedRoute(const AddProductScreen()));
    } finally {
      if (mounted) setState(() => _checkingQuota = false);
    }
  }

  Future<void> _showUpgradePlanPrompt({
    required int usedCount,
    required int maxLimit,
    required String currentPlanCode,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: AppColors.orange,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'وصلت للحد الأقصى ($usedCount / $maxLimit منشور)',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اشترك بإحدى باقات المزودين لزيادة عدد منشوراتك، وتقليل العمولة، وتصدر نتائج البحث في المتجر:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• باقة شهر: 15 منشور + شارة موثوق',
                      style: TextStyle(fontSize: 12.5)),
                  SizedBox(height: 4),
                  Text('• باقة 3 شهور: 30 منشور + عمولة أقل',
                      style: TextStyle(fontSize: 12.5)),
                  SizedBox(height: 4),
                  Text('• باقة 6 شهور: 45 منشور + تصدر بحث',
                      style: TextStyle(fontSize: 12.5)),
                  SizedBox(height: 4),
                  Text('• الباقة السنوية: منشورات لا نهائية + 0% عمولة',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.orange)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    animatedRoute(
                      ProviderSubscriptionsScreen(
                        currentPlanCode: currentPlanCode,
                        onSubscribed: widget.onRefreshProfile,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.rocket_launch),
                label: const Text(
                  'استعراض الباقات والاشتراك الآن',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لاحقاً'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    String? alertMsg;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('تغيير كلمة المرور'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (alertMsg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    alertMsg!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              TextField(
                controller: currentPassCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'كلمة المرور الحالية'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'كلمة المرور الجديدة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور الجديدة'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (newPassCtrl.text.length < 6) {
                        setD(() => alertMsg =
                            'كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل.');
                        return;
                      }
                      if (newPassCtrl.text != confirmPassCtrl.text) {
                        setD(() => alertMsg =
                            'كلمة المرور الجديدة وتأكيدها غير متطابقتين.');
                        return;
                      }
                      setD(() {
                        saving = true;
                        alertMsg = null;
                      });
                      try {
                        final email = widget.profile?.email ??
                            _db.auth.currentUser?.email;
                        if (email == null) {
                          throw Exception('البريد غير متوفر');
                        }
                        await _db.auth.signInWithPassword(
                          email: email,
                          password: currentPassCtrl.text,
                        );
                        await _db.auth.updateUser(
                          UserAttributes(password: newPassCtrl.text),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تحديث كلمة المرور بنجاح!'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (_) {
                        setD(() {
                          saving = false;
                          alertMsg =
                              'تنبيه أمني: كلمة المرور الحالية غير صحيحة!';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('حفظ كلمة المرور'),
            ),
          ],
        ),
      ),
    );
    currentPassCtrl.dispose();
    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final role = p?.role ?? 'user';
    final isAdmin = p != null && (p.isAdmin || role == 'admin');
    final isMerchant = role == 'merchant';
    final isProvider = isMerchant || role == 'mechanic' || role == 'towing';
    final canPublish = isProvider || isAdmin;
    final isLoggedIn = p != null;

    final pages = [
      _shortcutsHomeTab(),
      LiveStoreHomeScreen(
        profile: p,
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      isLoggedIn
          ? EmergencyScreen(profile: p)
          : _loginRequiredView('لطلب مساعدة طارئة يرجى تسجيل الدخول'),
      isLoggedIn
          ? CustomerAppointmentsScreen(
              customerProfile: p,
              onRefreshProfile: widget.onRefreshProfile,
            )
          : _loginRequiredView('لعرض وحجز مواعيد الورشة يرجى تسجيل الدخول'),
      _profileTab(isProvider),
    ];

    final safeIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildRoleBasedDrawer(),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: ValueKey(safeIndex),
              child: pages[safeIndex],
            ),
          ),

          // زر فحص AI العائم في الزاوية السفلية اليسرى
          Positioned(
            left: 14,
            bottom: 20,
            child: BounceTap(
              onTap: () =>
                  showAiDiagnosticSheet(context, viewerProfile: widget.profile),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navy, Color(0xFF1F2D3D)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.orange, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: AppColors.orange, size: 19),
                    SizedBox(width: 6),
                    Text(
                      'فحص AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? SizedBox(
              width: 54,
              height: 54,
              child: BounceTap(
                onTap: _handleAddProductTap,
                child: FloatingActionButton(
                  heroTag: 'center_add_post_fab',
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: const CircleBorder(),
                  onPressed: _handleAddProductTap,
                  child: _checkingQuota
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Icon(Icons.add, size: 28),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        elevation: 10,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        shape: canPublish ? const CircularNotchedRectangle() : null,
        notchMargin: 7,
        child: canPublish
            ? Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navItem(0, Icons.grid_view_rounded, 'الرئيسية'),
                        _navItem(1, Icons.storefront_outlined, 'المتجر'),
                      ],
                    ),
                  ),
                  // فراغ مركزي دقيق لزر (+) يمنع أي تداخل مع طوارئ أو المتجر
                  const SizedBox(width: 68),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navItem(2, Icons.car_crash_outlined, 'طوارئ'),
                        _navItem(3, Icons.event_note_outlined, 'المواعيد'),
                        _navItem(4, Icons.person_outline, 'حسابي'),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.grid_view_rounded, 'الرئيسية'),
                  _navItem(1, Icons.storefront_outlined, 'المتجر'),
                  _navItem(2, Icons.car_crash_outlined, 'طوارئ'),
                  _navItem(3, Icons.event_note_outlined, 'المواعيد'),
                  _navItem(4, Icons.person_outline, 'حسابي'),
                ],
              ),
      ),
    );
  }

  /// شاشة الرئيسية (اختصارات الوصول السريع)
  Widget _shortcutsHomeTab() {
    final p = widget.profile;
    final isLoggedIn = p != null;
    final role = p?.role ?? 'user';
    final isAdmin = p != null && (p.isAdmin || role == 'admin');
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;

    final displayName = isLoggedIn
        ? (p.username?.isNotEmpty == true
            ? p.username!
            : (p.fullName?.isNotEmpty == true ? p.fullName! : 'مستخدم غيارك'))
        : 'زائر غيارك';

    final shortcuts = _buildShortcutsForRole(
      p: p,
      isAdmin: isAdmin,
      role: role,
      showPayments: showPayments,
      showWinch: showWinch,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.navy, size: 26),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GhiyarakLogo(size: 32),
            SizedBox(width: 8),
            Text(
              'غيارك',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        actions: [
          if (isLoggedIn)
            ChatBadgeButton(
              iconColor: AppColors.navy,
              onPressed: () =>
                  Navigator.push(context, animatedRoute(const ChatsListScreen())),
            )
          else
            IconButton(
              tooltip: 'الدردشات',
              icon: const Icon(Icons.chat_bubble_outline,
                  color: AppColors.navy, size: 23),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile)),
              ),
            ),
          if (isLoggedIn)
            const NotificationBellButton(iconColor: AppColors.navy)
          else
            IconButton(
              tooltip: 'الإشعارات',
              icon: const Icon(Icons.notifications_none,
                  color: AppColors.navy, size: 25),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile)),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          widget.onRefreshProfile();
          await _notifs.refreshUnreadCounts();
          if (mounted) setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          children: [
            // بطاقة الترحيب العلوية الداكنة
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أهلاً بك، $displayName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.orange,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _roleArabicName(isAdmin
                                    ? 'admin'
                                    : (isLoggedIn ? role : 'guest')),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isLoggedIn &&
                                (p.isTrustedMerchant || isAdmin))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F3B5C),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified,
                                        color: Color(0xFF38BDF8), size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'حساب موثق',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
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

            // بانر التتبع المباشر للورش والطوارئ مع زر دفع الفاتورة
            if (isLoggedIn) ...[
              const SizedBox(height: 12),
              HomeLiveProgressBanner(viewerProfile: p),
            ],

            const SizedBox(height: 20),

            // عنوان قسم الاختصارات
            const Row(
              children: [
                Icon(Icons.grid_view_rounded,
                    color: AppColors.orange, size: 22),
                SizedBox(width: 8),
                Text(
                  'اختصارات الوصول السريع',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // شبكة بطاقات الاختصارات
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shortcuts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.06,
              ),
              itemBuilder: (_, i) {
                final item = shortcuts[i];
                return BounceTap(
                  onTap: item.onTap,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: item.highlighted
                          ? const Color(0xFFFFF4EC)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: item.highlighted
                            ? AppColors.orange.withValues(alpha: 0.65)
                            : const Color(0xFFE9ECF2),
                        width: item.highlighted ? 1.3 : 1,
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
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: item.iconBg,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                item.icon,
                                color: item.iconColor,
                                size: 24,
                              ),
                            ),
                            if (item.showChatBadge)
                              ValueListenableBuilder<int>(
                                valueListenable: _notifs.unreadMessagesCount,
                                builder: (_, count, __) {
                                  if (count <= 0) return const SizedBox.shrink();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_ShortcutItem> _buildShortcutsForRole({
    required CustomerProfile? p,
    required bool isAdmin,
    required String role,
    required bool showPayments,
    required bool showWinch,
  }) {
    void openChats() {
      if (p == null) {
        Navigator.push(
          context,
          animatedRoute(LoginScreen(onAuthenticated: widget.onRefreshProfile)),
        );
        return;
      }
      Navigator.push(context, animatedRoute(const ChatsListScreen()));
    }

    void openProviderPlans() {
      if (p == null) return;
      Navigator.push(
        context,
        animatedRoute(
          ProviderSubscriptionsScreen(
            currentPlanCode: p.subscriptionPlan,
            onSubscribed: widget.onRefreshProfile,
          ),
        ),
      );
    }

    if (isAdmin && p != null) {
      return [
        _ShortcutItem(
          title: 'لوحة السوبر أدمن',
          subtitle: 'التسعيرات، الحسابات، الخصومات والمالية',
          icon: Icons.admin_panel_settings_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: 'قطع الغيار والمخزون',
          subtitle: 'إدارة القطع، الإخفاء والخصومات',
          icon: Icons.inventory_2_outlined,
          iconColor: const Color(0xFF334155),
          iconBg: const Color(0xFFE2E8F0),
          onTap: () => Navigator.push(
              context, animatedRoute(const MerchantProductsDashboard())),
        ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر قطعة جديدة في المتجر',
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'تصفح جميع القطع والمنشورات',
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: 'الطوارئ والونش',
          subtitle: 'طلب ونش أو ميكانيكي طوارئ',
          icon: Icons.car_crash_outlined,
          iconColor: const Color(0xFFB45309),
          iconBg: const Color(0xFFFEF3C7),
          onTap: () => setState(() => _index = 2),
        ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل المباشر مع المستخدمين',
          icon: Icons.chat_bubble_outline,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFE0F2FE),
          showChatBadge: true,
          onTap: openChats,
        ),
      ];
    }

    if (role == 'mechanic' && p != null) {
      return [
        _ShortcutItem(
          title: 'لوحة الورشة والطوارئ',
          subtitle: 'استقبال المواعيد وطلبات الإنقاذ',
          icon: Icons.build_circle_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: 'قطع الغيار والمخزون',
          subtitle: 'إدارة القطع، الإخفاء والخصومات',
          icon: Icons.inventory_2_outlined,
          iconColor: const Color(0xFF334155),
          iconBg: const Color(0xFFE2E8F0),
          onTap: () => Navigator.push(
              context, animatedRoute(const MerchantProductsDashboard())),
        ),
        if (showPayments)
          _ShortcutItem(
            title: 'المحفظة المالية',
            subtitle: 'متابعة أرباح الورشة والعمولات',
            icon: Icons.account_balance_wallet_outlined,
            iconColor: const Color(0xFF0F766E),
            iconBg: const Color(0xFFCCFBF1),
            onTap: () => _openProviderWallet(p),
          ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر قطعة من مخزون الورشة',
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'شراء قطع لسيارات الزبائن',
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: showPayments ? 'الباقات والاشتراكات' : 'مواعيد الورش',
          subtitle: showPayments
              ? 'تصدر نتائج البحث وعمولة أقل'
              : 'متابعة حجوزات الصيانة',
          icon: showPayments
              ? Icons.workspace_premium_outlined
              : Icons.event_note_outlined,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
          onTap: showPayments
              ? openProviderPlans
              : () => setState(() => _index = 3),
        ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل المباشر مع الزبائن',
          icon: Icons.chat_bubble_outline,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFE0F2FE),
          showChatBadge: true,
          onTap: openChats,
        ),
        if (showPayments)
          _ShortcutItem(
            title: 'الدعم الفني',
            subtitle: 'المساعدة والدعم المباشر',
            icon: Icons.support_agent,
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFEDE9FE),
            onTap: _openSupportScreen,
          ),
      ];
    }

    if (role == 'merchant' && p != null) {
      return [
        _ShortcutItem(
          title: 'قطع الغيار والمخزون',
          subtitle: 'إدارة القطع، الإخفاء والخصومات',
          icon: Icons.inventory_2_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر قطعة جديدة في المتجر',
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'تصفح جميع القطع والعروض',
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: showPayments ? 'محفظة التاجر' : 'الدعم الفني',
          subtitle: showPayments
              ? 'متابعة الأرباح والعمولات'
              : 'المساعدة والدعم المباشر',
          icon: showPayments
              ? Icons.account_balance_wallet_outlined
              : Icons.support_agent,
          iconColor: const Color(0xFF0F766E),
          iconBg: const Color(0xFFCCFBF1),
          onTap: showPayments
              ? () => _openProviderWallet(p)
              : _openSupportScreen,
        ),
        _ShortcutItem(
          title: showPayments ? 'الباقات والاشتراكات' : 'مواعيد الورش',
          subtitle: showPayments
              ? 'زيادة حد المنشورات وتصدر البحث'
              : 'حجوزات ومواعيد الصيانة',
          icon: showPayments
              ? Icons.workspace_premium_outlined
              : Icons.event_note_outlined,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
          onTap: showPayments
              ? openProviderPlans
              : () => setState(() => _index = 3),
        ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل المباشر مع الزبائن',
          icon: Icons.chat_bubble_outline,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFE0F2FE),
          showChatBadge: true,
          onTap: openChats,
        ),
      ];
    }

    if (role == 'towing' && p != null) {
      return [
        _ShortcutItem(
          title: 'لوحة الونش والإنقاذ',
          subtitle: 'استقبال طلبات السحب المباشرة',
          icon: Icons.local_shipping_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        if (showPayments)
          _ShortcutItem(
            title: 'محفظة الونش',
            subtitle: 'متابعة الأرباح والعمولات',
            icon: Icons.account_balance_wallet_outlined,
            iconColor: const Color(0xFF0F766E),
            iconBg: const Color(0xFFCCFBF1),
            onTap: () => _openProviderWallet(p),
          ),
        _ShortcutItem(
          title: 'إضافة قطعة غيار',
          subtitle: 'نشر قطعة للبيع في المتجر',
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: 'متجر قطع الغيار',
          subtitle: 'تصفح جميع القطع والمنشورات',
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: showPayments ? 'الباقات والاشتراكات' : 'الدعم الفني',
          subtitle: showPayments
              ? 'عمولة أقل وظهور مميز'
              : 'المساعدة على مدار الساعة',
          icon: showPayments
              ? Icons.workspace_premium_outlined
              : Icons.support_agent,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
          onTap: showPayments ? openProviderPlans : _openSupportScreen,
        ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل المباشر مع الزبائن',
          icon: Icons.chat_bubble_outline,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFE0F2FE),
          showChatBadge: true,
          onTap: openChats,
        ),
      ];
    }

    // المستخدم العادي والزائر
    return [
      _ShortcutItem(
        title: 'متجر قطع الغيار',
        subtitle: 'ابحث وتواصل مباشرة مع التجار',
        icon: Icons.storefront_outlined,
        iconColor: AppColors.orange,
        iconBg: AppColors.orange.withValues(alpha: 0.16),
        highlighted: true,
        onTap: () => setState(() => _index = 1),
      ),
      _ShortcutItem(
        title: showWinch ? 'طوارئ / ونش وميكانيكي' : 'ميكانيكي طوارئ',
        subtitle: 'مساعدة فورية على الطريق',
        icon: Icons.car_crash_outlined,
        iconColor: const Color(0xFFDC2626),
        iconBg: const Color(0xFFFEE2E2),
        onTap: () => setState(() => _index = 2),
      ),
      _ShortcutItem(
        title: 'حجز موعد ورشة',
        subtitle: 'احجز صيانة في ورشة معتمدة',
        icon: Icons.event_available_outlined,
        iconColor: const Color(0xFF15803D),
        iconBg: const Color(0xFFDCFCE7),
        onTap: () => setState(() => _index = 3),
      ),
      _ShortcutItem(
        title: 'المدفوعات وسجل الدفعات',
        subtitle: 'راجع جميع فواتيرك ودفعاتك السابقة',
        icon: Icons.receipt_long_outlined,
        iconColor: const Color(0xFF0F766E),
        iconBg: const Color(0xFFCCFBF1),
        onTap: () => _openCustomerPaymentsHistory(p),
      ),
      _ShortcutItem(
        title: 'فحص الأعطال بالـ AI',
        subtitle: 'شخّص عطل سيارتك فوراً',
        icon: Icons.auto_awesome,
        iconColor: const Color(0xFF4338CA),
        iconBg: const Color(0xFFE0E7FF),
        onTap: () =>
            showAiDiagnosticSheet(context, viewerProfile: widget.profile),
      ),
      _ShortcutItem(
        title: 'الدردشات',
        subtitle: 'محادثاتك مع التجار والورش',
        icon: Icons.chat_bubble_outline,
        iconColor: const Color(0xFF0284C7),
        iconBg: const Color(0xFFE0F2FE),
        showChatBadge: true,
        onTap: openChats,
      ),
      if (showPayments)
        _ShortcutItem(
          title: 'الباقات والاشتراكات',
          subtitle: 'مزايا وخصومات حصرية',
          icon: Icons.workspace_premium_outlined,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
          onTap: () {
            if (p == null) {
              Navigator.push(
                context,
                animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile)),
              );
              return;
            }
            Navigator.push(
              context,
              animatedRoute(
                CustomerSubscriptionsScreen(
                  currentPlanCode: p.subscriptionPlan,
                  onSubscribed: widget.onRefreshProfile,
                ),
              ),
            );
          },
        ),
      if (showPayments)
        _ShortcutItem(
          title: 'الدعم الفني',
          subtitle: 'فريق الدعم جاهز لمساعدتك',
          icon: Icons.support_agent,
          iconColor: const Color(0xFF7C3AED),
          iconBg: const Color(0xFFEDE9FE),
          onTap: _openSupportScreen,
        ),
    ];
  }

  Widget _buildRoleBasedDrawer() {
    final p = widget.profile;
    final isLoggedIn = p != null;
    final role = p?.role ?? 'guest';
    final isAdmin = p != null && (p.isAdmin || role == 'admin');
    final isProvider =
        role == 'merchant' || role == 'mechanic' || role == 'towing';
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;
    final hasDashboard = isLoggedIn &&
        (isAdmin ||
            role == 'mechanic' ||
            role == 'merchant' ||
            (role == 'towing' && showWinch));

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 22),
            color: AppColors.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    GhiyarakLogo(size: 42),
                    SizedBox(width: 10),
                    Text(
                      'غيارك',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isLoggedIn
                      ? '${p.fullName ?? ""} · @${p.username ?? ""}'
                      : 'مرحباً بك في غيارك (تصفح كزائر)',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (isLoggedIn) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _roleArabicName(isAdmin ? 'admin' : role),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasDashboard) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: AppColors.orangeLight,
                leading: const Icon(Icons.dashboard, color: AppColors.orange),
                title: const Text(
                  'لوحة التحكم',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.orange,
                  ),
                ),
                subtitle: Text(
                  _roleDashboardSubtitle(isAdmin ? 'admin' : role),
                  style: const TextStyle(fontSize: 11, color: AppColors.navy),
                ),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 15, color: AppColors.orange),
                onTap: () {
                  Navigator.pop(context);
                  _openDashboardForRole(p);
                },
              ),
            ),
            const Divider(),
          ],
          ListTile(
            leading:
                const Icon(Icons.grid_view_rounded, color: AppColors.orange),
            title: const Text('الرئيسية (الاختصارات)'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.storefront, color: AppColors.navy),
            title: const Text('متجر قطع الغيار'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.car_crash_outlined),
            title: const Text('طلب مساعدة طارئة'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('مواعيد الورشة'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 3);
            },
          ),

          // زر المحفظة المالية للتاجر والميكانيكي والونش في الـ Drawer
          if (isLoggedIn && isProvider) ...[
            const Divider(),
            if (showPayments)
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFF0F766E)),
                title: Text(
                  role == 'mechanic'
                      ? 'المحفظة المالية والأرباح'
                      : (role == 'towing'
                          ? 'محفظة الونش والأرباح'
                          : 'محفظة التاجر والأرباح'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openProviderWallet(p);
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.add_box_outlined, color: AppColors.orange),
              title: const Text('إضافة منشور قطعة غيار'),
              onTap: () {
                Navigator.pop(context);
                _handleAddProductTap();
              },
            ),
          ],

          // زر المدفوعات وسجل الدفعات للمستخدم العادي في الـ Drawer
          if (isLoggedIn && !isProvider && !isAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined,
                  color: Color(0xFF0F766E)),
              title: const Text(
                'المدفوعات وسجل الدفعات',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('مراجعة جميع فواتيرك السابقة',
                  style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _openCustomerPaymentsHistory(p);
              },
            ),
          ],

          if (isLoggedIn) ...[
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.chat_bubble_outline, color: AppColors.navy),
              title: const Text('الدردشات'),
              trailing: ValueListenableBuilder<int>(
                valueListenable: _notifs.unreadMessagesCount,
                builder: (_, count, __) {
                  if (count <= 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, animatedRoute(const ChatsListScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('الإشعارات'),
              trailing: ValueListenableBuilder<int>(
                valueListenable: _notifs.unreadNotificationsCount,
                builder: (_, count, __) {
                  if (count <= 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _notifs.openNotificationsSheet(context);
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.support_agent, color: AppColors.orange),
            title: const Text('الدعم الفني والمساعدة'),
            onTap: () {
              Navigator.pop(context);
              _openSupportScreen();
            },
          ),
          const Divider(),
          if (!isLoggedIn) ...[
            ListTile(
              leading: const Icon(Icons.login, color: AppColors.orange),
              title: const Text('تسجيل الدخول',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  animatedRoute(
                      LoginScreen(onAuthenticated: widget.onRefreshProfile)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1, color: AppColors.navy),
              title: const Text('إنشاء حساب جديد'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  animatedRoute(
                      SignUpScreen(onAuthenticated: widget.onRefreshProfile)),
                );
              },
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                Navigator.pop(context);
                await _notifs.stopRealtimeListener();
                await _db.auth.signOut();
                widget.onSignedOut();
              },
            ),
        ],
      ),
    );
  }

  String _roleArabicName(String role) => switch (role) {
        'admin' => 'مدير النظام (Admin)',
        'mechanic' => 'ميكانيكي / ورشة',
        'towing' => 'صاحب ونش طوارئ',
        'merchant' => 'تاجر قطع غيار',
        'guest' => 'زائر',
        _ => 'مستخدم عادي',
      };

  String _roleDashboardSubtitle(String role) => switch (role) {
        'admin' => 'إدارة النظام والإعلانات والتجار',
        'mechanic' => 'الورشة وطلبات الطوارئ',
        'towing' => 'طلبات الونش المباشرة',
        'merchant' => 'إدارة المنتجات والمشاهدات والنقرات',
        _ => '',
      };

  Widget _loginRequiredView(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 52, color: AppColors.navy),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile)),
              ),
              child: const Text('تسجيل الدخول / إنشاء حساب'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int idx, IconData icon, String label) {
    final active = _index == idx;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _index = idx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 3,
              width: active ? 20 : 0,
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            AnimatedScale(
              scale: active ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(
                icon,
                color: active ? AppColors.orange : AppColors.textSecondary,
                size: 21,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? AppColors.orange : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTab(bool isProvider) {
    if (widget.profile == null) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _loginRequiredView('سجل دخولك لإدارة حسابك'),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.support_agent, color: AppColors.orange),
                title: const Text('الدعم الفني والمساعدة'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _openSupportScreen,
              ),
            ),
          ],
        ),
      );
    }
    final showPayments = EnvConfig.paymentsEnabled.value;
    final p = widget.profile!;
    final isAdmin = p.isAdmin || p.role == 'admin';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.navy,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                p.fullName ?? 'المستخدم',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('@${p.username ?? ""} · ${p.phone ?? ""}'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, color: AppColors.orange),
              title: const Text('البروفايل (معلوماتي الشخصية)'),
              subtitle: const Text('عرض وتعديل الاسم، الهاتف، ومعلومات النشاط'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(
                context,
                animatedRoute(
                  UserProfileScreen(
                    profile: p,
                    onSaved: widget.onRefreshProfile,
                  ),
                ),
              ),
            ),
          ),
          if (showPayments && isProvider) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFF0F766E)),
                title: const Text('المحفظة المالية والأرباح'),
                subtitle: const Text('مراجعة صافي الرصيد والعمولات والحركات'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openProviderWallet(p),
              ),
            ),
          ],
          if (!isProvider && !isAdmin) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined,
                    color: Color(0xFF0F766E)),
                title: const Text('المدفوعات وسجل الدفعات'),
                subtitle: const Text('مراجعة جميع الفواتير والمبالغ التي دفعتها'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openCustomerPaymentsHistory(p),
              ),
            ),
          ],
          if (showPayments) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.workspace_premium,
                    color: AppColors.orange),
                title: Text(isProvider
                    ? 'باقات واشتراكات المزودين'
                    : 'اشتراك المستخدم العادي (البرو)'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  animatedRoute(
                    isProvider
                        ? ProviderSubscriptionsScreen(
                            currentPlanCode: p.subscriptionPlan,
                            onSubscribed: widget.onRefreshProfile,
                          )
                        : CustomerSubscriptionsScreen(
                            currentPlanCode: p.subscriptionPlan,
                            onSubscribed: widget.onRefreshProfile,
                          ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset, color: AppColors.navy),
              title: const Text('تغيير كلمة المرور'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showChangePasswordDialog,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent, color: AppColors.orange),
              title: const Text('الدعم الفني والمساعدة'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _openSupportScreen,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                await _notifs.stopRealtimeListener();
                await _db.auth.signOut();
                widget.onSignedOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// شاشة المدفوعات وسجل الدفعات للمستخدم العادي (لمراجعة كل ما تم دفعه)
class CustomerPaymentsHistoryScreen extends StatefulWidget {
  final CustomerProfile profile;
  const CustomerPaymentsHistoryScreen({super.key, required this.profile});

  @override
  State<CustomerPaymentsHistoryScreen> createState() =>
      _CustomerPaymentsHistoryScreenState();
}

class _CustomerPaymentsHistoryScreenState
    extends State<CustomerPaymentsHistoryScreen> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  bool _loading = true;
  List<_CustomerPaymentEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments({bool silent = false}) async {
    if (!silent && mounted && _entries.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final uid = widget.profile.id;
      final List<_CustomerPaymentEntry> collected = [];
      final Set<String> seenRefIds = {};
      final Set<String> providerIds = {};

      // 1) سجل wallet_transactions المباشر للمستخدم
      try {
        final txRows = await _db
            .from('wallet_transactions')
            .select()
            .eq('customer_id', uid)
            .order('created_at', ascending: false)
            .limit(200);
        for (final raw in txRows) {
          final m = Map<String, dynamic>.from(raw);
          final refId = (m['reference_id'] as String?) ?? (m['id'] as String);
          final provId = m['provider_id'] as String?;
          if (provId != null && provId.isNotEmpty) providerIds.add(provId);
          seenRefIds.add(refId);
          collected.add(
            _CustomerPaymentEntry(
              id: (m['id'] ?? refId).toString(),
              referenceId: refId,
              providerId: provId,
              type: (m['transaction_type'] as String?) ?? 'order',
              paymentMethod: (m['payment_method'] as String?) ?? 'visa',
              amount: ((m['gross_amount'] as num?) ?? 0).toDouble(),
              status: (m['status'] as String?) ?? 'completed',
              createdAt:
                  DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                      DateTime.now(),
            ),
          );
        }
      } catch (_) {}

      // 2) مواعيد الورش المدفوعة (احتياط لضمان عدم فقدان أي فاتورة)
      try {
        final apptRows = await _db
            .from('workshop_appointments')
            .select()
            .eq('user_id', uid)
            .eq('payment_status', 'paid')
            .order('created_at', ascending: false)
            .limit(100);
        for (final raw in apptRows) {
          final m = Map<String, dynamic>.from(raw);
          final id = (m['id'] ?? '').toString();
          if (id.isEmpty || seenRefIds.contains(id)) continue;
          final amt = ((m['total_amount'] as num?) ?? 0).toDouble();
          if (amt <= 0) continue;
          final provId = m['workshop_id'] as String?;
          if (provId != null && provId.isNotEmpty) providerIds.add(provId);
          seenRefIds.add(id);
          collected.add(
            _CustomerPaymentEntry(
              id: 'appt_$id',
              referenceId: id,
              providerId: provId,
              type: 'workshop',
              paymentMethod: (m['payment_method'] as String?) ?? 'cash',
              amount: amt,
              subtitleNote: (m['service_description'] as String?)?.trim(),
              status: 'completed',
              createdAt:
                  DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                      DateTime.now(),
            ),
          );
        }
      } catch (_) {}

      // 3) طلبات الطوارئ والونش المدفوعة
      try {
        final reqRows = await _db
            .from('mechanic_requests')
            .select()
            .eq('user_id', uid)
            .eq('payment_status', 'paid')
            .order('created_at', ascending: false)
            .limit(100);
        for (final raw in reqRows) {
          final m = Map<String, dynamic>.from(raw);
          final id = (m['id'] ?? '').toString();
          if (id.isEmpty || seenRefIds.contains(id)) continue;
          final amt = ((m['total_amount'] as num?) ?? 0).toDouble();
          if (amt <= 0) continue;
          final provId = m['mechanic_id'] as String?;
          if (provId != null && provId.isNotEmpty) providerIds.add(provId);
          seenRefIds.add(id);
          final svcType = (m['service_type'] as String?) == 'winch'
              ? 'winch_towing'
              : 'emergency';
          collected.add(
            _CustomerPaymentEntry(
              id: 'req_$id',
              referenceId: id,
              providerId: provId,
              type: svcType,
              paymentMethod: (m['payment_method'] as String?) ?? 'cash',
              amount: amt,
              subtitleNote: (m['car_details'] as String?)?.trim(),
              status: 'completed',
              createdAt:
                  DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                      DateTime.now(),
            ),
          );
        }
      } catch (_) {}

      // جلب أسماء الورش / التجار / السائقين لعرضها على كل فاتورة
      final Map<String, String> providerNames = {};
      if (providerIds.isNotEmpty) {
        try {
          final provRows = await _db
              .from('customers')
              .select('id, full_name, username')
              .inFilter('id', providerIds.toList());
          for (final p in provRows) {
            final pid = p['id'] as String?;
            if (pid == null) continue;
            final name = (p['full_name'] as String?)?.trim().isNotEmpty == true
                ? (p['full_name'] as String).trim()
                : ((p['username'] as String?) ?? 'مزود خدمة');
            providerNames[pid] = name;
          }
        } catch (_) {}
      }

      final resolved = collected
          .map(
            (e) => e.copyWith(
              providerName:
                  e.providerId != null ? providerNames[e.providerId!] : null,
            ),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _entries = resolved;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _inPeriod(DateTime dt) {
    final local = dt.toLocal();
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !local.isBefore(range.start) &&
        !local.isAfter(range.end.add(const Duration(days: 1)));
  }

  String _typeArabic(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => 'شراء قطعة غيار',
        'workshop' || 'appointment' => 'فاتورة صيانة ورشة',
        'winch_towing' || 'winch' => 'فاتورة ونش طوارئ',
        'emergency' => 'فاتورة ميكانيكي طوارئ',
        'subscription' => 'اشتراك باقة',
        _ => raw,
      };

  String _methodArabic(String raw) => switch (raw.toLowerCase()) {
        'cash' => 'نقداً (كاش)',
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'visa' || 'card' || 'meps' => 'فيزا / ماستركارد',
        _ => raw,
      };

  IconData _methodIcon(String raw) => switch (raw.toLowerCase()) {
        'cash' => Icons.payments_outlined,
        'apple_pay' => Icons.apple,
        'google_pay' => Icons.account_balance_wallet_outlined,
        _ => Icons.credit_card,
      };

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d · $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _entries.where((e) => _inPeriod(e.createdAt)).toList();
    final periodTotal = filtered.fold(0.0, (s, e) => s + e.amount);
    final allTimeTotal = _entries.fold(0.0, (s, e) => s + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المدفوعات وسجل الدفعات'),
        actions: [
          IconButton(
            tooltip: 'تحديث السجل',
            onPressed: () => _loadPayments(silent: false),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: () => _loadPayments(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            DateRangeFilterBar(
              period: _period,
              customRange: _customRange,
              onChanged: (p, r) => setState(() {
                _period = p;
                _customRange = r;
              }),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إجمالي مدفوعاتك خلال الفترة المختارة',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${periodTotal.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'عدد الدفعات في الفترة: ${filtered.length}  |  إجمالي الكل: ${allTimeTotal.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading && _entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 54, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    const Text(
                      'لا توجد دفعات مسجلة خلال هذه الفترة',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              ...filtered.map(
                (e) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.orangeLight,
                      child: Icon(
                        _methodIcon(e.paymentMethod),
                        color: AppColors.orange,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      _typeArabic(e.type),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (e.providerName != null &&
                            e.providerName!.isNotEmpty)
                          Text(
                            'الجهة: ${e.providerName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (e.subtitleNote != null &&
                            e.subtitleNote!.isNotEmpty)
                          Text(
                            e.subtitleNote!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          '${_methodArabic(e.paymentMethod)} · ${_formatDateTime(e.createdAt)}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${e.amount.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'مدفوع ✓',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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

class _CustomerPaymentEntry {
  final String id;
  final String referenceId;
  final String? providerId;
  final String? providerName;
  final String type;
  final String paymentMethod;
  final double amount;
  final String? subtitleNote;
  final String status;
  final DateTime createdAt;

  const _CustomerPaymentEntry({
    required this.id,
    required this.referenceId,
    this.providerId,
    this.providerName,
    required this.type,
    required this.paymentMethod,
    required this.amount,
    this.subtitleNote,
    required this.status,
    required this.createdAt,
  });

  _CustomerPaymentEntry copyWith({String? providerName}) =>
      _CustomerPaymentEntry(
        id: id,
        referenceId: referenceId,
        providerId: providerId,
        providerName: providerName ?? this.providerName,
        type: type,
        paymentMethod: paymentMethod,
        amount: amount,
        subtitleNote: subtitleNote,
        status: status,
        createdAt: createdAt,
      );
}

/// شاشة المحفظة المالية المستقرة للتاجر والميكانيكي والونش (لا يختفي الرصيد ولا يرجع إلى 0.00)
class _ProviderWalletView extends StatefulWidget {
  final CustomerProfile profile;
  final String headerLabel;
  const _ProviderWalletView({
    required this.profile,
    this.headerLabel = 'صافي المحفظة المالية (بعد العمولة)',
  });

  @override
  State<_ProviderWalletView> createState() => _ProviderWalletViewState();
}

class _ProviderWalletViewState extends State<_ProviderWalletView> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  List<DbWalletTransaction> _txs = [];
  late double _accountBalance = widget.profile.walletBalance;
  late double _pendingDebt = widget.profile.pendingCommissionDebt;
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _channel = _db
        .channel('provider_wallet_${widget.profile.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: widget.profile.id,
          ),
          callback: (_) => _loadWallet(silent: true),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) {
      try {
        _db.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
    super.dispose();
  }

  Future<void> _loadWallet({bool silent = false}) async {
    if (!silent && mounted && _txs.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final results = await Future.wait([
        _db
            .from('customers')
            .select('wallet_balance, pending_commission_debt')
            .eq('id', widget.profile.id)
            .maybeSingle(),
        _db
            .from('wallet_transactions')
            .select()
            .eq('provider_id', widget.profile.id)
            .order('created_at', ascending: false)
            .limit(200),
      ]);
      final row = results[0] as Map<String, dynamic>?;
      final txRows = List<Map<String, dynamic>>.from(results[1] as List);
      final parsed = txRows.map(DbWalletTransaction.fromMap).toList();
      if (!mounted) return;
      setState(() {
        if (row != null) {
          _accountBalance =
              ((row['wallet_balance'] as num?) ?? _accountBalance).toDouble();
          _pendingDebt =
              ((row['pending_commission_debt'] as num?) ?? _pendingDebt).toDouble();
        }
        _txs = parsed;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _inPeriodDate(DateTime dt) {
    final local = dt.toLocal();
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !local.isBefore(range.start) &&
        !local.isAfter(range.end.add(const Duration(days: 1)));
  }

  String _txArabicType(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => 'بيع قطعة غيار',
        'workshop' || 'appointment' => 'خدمة ورشة',
        'winch_towing' || 'winch' || 'emergency' => 'طلب طوارئ / ونش',
        _ => raw,
      };

  String _paymentMethodArabic(String raw) => switch (raw.toLowerCase()) {
        'cash' => 'نقداً (كاش)',
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'visa' || 'card' || 'meps' => 'فيزا / ماستركارد',
        _ => raw,
      };

  @override
  Widget build(BuildContext context) {
    final filtered = _txs.where((t) => _inPeriodDate(t.createdAt)).toList();
    final periodGross = filtered.fold(0.0, (s, t) => s + t.grossAmount);
    final periodComm = filtered.fold(0.0, (s, t) => s + t.commissionAmount);
    final periodNet = filtered.fold(0.0, (s, t) => s + t.netAmount);
    final allTimeNet = _txs.fold(0.0, (s, t) => s + t.netAmount);
    final effectiveBalance = _accountBalance > 0 ? _accountBalance : allTimeNet;

    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () => _loadWallet(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: DateRangeFilterBar(
                  period: _period,
                  customRange: _customRange,
                  onChanged: (p, r) => setState(() {
                    _period = p;
                    _customRange = r;
                  }),
                ),
              ),
              IconButton(
                tooltip: 'تحديث المحفظة',
                onPressed: () => _loadWallet(silent: false),
                icon: const Icon(Icons.refresh, color: AppColors.navy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.headerLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${effectiveBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'خلال الفترة المختارة — الصافي: ${periodNet.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: AppColors.orange,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'قبل العمولة: ${periodGross.toStringAsFixed(2)} د.أ | العمولة: ${periodComm.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_pendingDebt > 0) ...[
                  const Divider(color: Colors.white24, height: 18),
                  Text(
                    'عمولات الدفع النقدي (كاش) المستحقة للمنصة: ${_pendingDebt.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading && _txs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'لا توجد حركات مالية ضمن الفترة المختارة',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...filtered.map(
              (t) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(
                    '${_txArabicType(t.transactionType)} · ${_paymentMethodArabic(t.paymentMethod)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} د.أ · عمولة: -${t.commissionAmount.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '+${t.netAmount.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final bool highlighted;
  final bool showChatBadge;
  final VoidCallback onTap;

  const _ShortcutItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.highlighted = false,
    this.showChatBadge = false,
    required this.onTap,
  });
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدعم الفني — غيارك')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              children: [
                GhiyarakLogo(size: 62),
                SizedBox(height: 12),
                Text(
                  'فريق دعم غيارك',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'نحن هنا لمساعدتك في أي استفسار أو مشكلة تقنية على مدار الساعة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone, color: AppColors.orange),
              title: const Text('الاتصال الهاتفي',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(EnvConfig.supportPhone),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => launchUrl(Uri.parse('tel:${EnvConfig.supportPhone}')),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat, color: AppColors.success),
              title: const Text('واتساب الدعم الفني',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('+${EnvConfig.supportWhatsapp}'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => launchUrl(
                Uri.parse('https://wa.me/${EnvConfig.supportWhatsapp}'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.email_outlined, color: AppColors.navy),
              title: const Text('البريد الإلكتروني',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(EnvConfig.supportEmail),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => launchUrl(
                Uri.parse(
                    'mailto:${EnvConfig.supportEmail}?subject=دعم فني تطبيق غيارك'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserProfileScreen extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onSaved;
  const UserProfileScreen({
    super.key,
    required this.profile,
    required this.onSaved,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _db = Supabase.instance.client;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  String? _country;
  int? _age;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.fullName ?? '');
    _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
    _addressCtrl =
        TextEditingController(text: widget.profile.workshopAddress ?? '');
    _loadExtraFields();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExtraFields() async {
    final row = await _db
        .from('customers')
        .select('country, age')
        .eq('id', widget.profile.id)
        .maybeSingle();
    if (row != null && mounted) {
      setState(() {
        _country = row['country'] as String?;
        _age = row['age'] as int?;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await _db.from('customers').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (widget.profile.role == 'mechanic')
          'workshop_address': _addressCtrl.text.trim(),
      }).eq('id', widget.profile.id);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث معلومات البروفايل بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('ملفي الشخصي (البروفايل)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName ?? 'المستخدم',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('اسم المستخدم: @${p.username ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('البريد الإلكتروني: ${p.email ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text(
                  'نوع الحساب: ${p.role}',
                  style: const TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_country != null || _age != null)
                  Text(
                    'الدولة: ${_country ?? "-"}  |  العمر: ${_age ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل',
              filled: true,
              fillColor: AppColors.surface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              filled: true,
              fillColor: AppColors.surface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (p.role == 'mechanic') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                labelText: 'عنوان الورشة',
                filled: true,
                fillColor: AppColors.surface,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ساعات الدوام: ${p.openingHours} · السعة: ${p.maxCarCapacity} سيارة/يوم',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 22),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _saveProfile,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('حفظ التعديلات',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}