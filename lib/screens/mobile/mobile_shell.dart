import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/home_ad_banner.dart';
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
import 'wallet_and_payments_screens.dart';

export 'wallet_and_payments_screens.dart';

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

  StreamSubscription<List<Map<String, dynamic>>>? _unreadMsgSub;
  StreamSubscription<List<Map<String, dynamic>>>? _unreadNotifSub;
  int _unreadMessagesCount = 0;
  int _unreadNotifsCount = 0;
  String? _boundUserId;

  @override
  void initState() {
    super.initState();
    _syncUserStreams();
  }

  @override
  void didUpdateWidget(covariant LiveMobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.id != widget.profile?.id) {
      _syncUserStreams();
    }
  }

  @override
  void dispose() {
    _unreadMsgSub?.cancel();
    _unreadNotifSub?.cancel();
    super.dispose();
  }

  void _syncUserStreams() {
    final uid = widget.profile?.id;
    if (_boundUserId == uid) return;
    _boundUserId = uid;

    _unreadMsgSub?.cancel();
    _unreadNotifSub?.cancel();
    _unreadMsgSub = null;
    _unreadNotifSub = null;

    if (uid == null || uid.isEmpty) {
      _notifs.stopRealtimeListener();
      if (mounted) {
        setState(() {
          _unreadMessagesCount = 0;
          _unreadNotifsCount = 0;
        });
      }
      return;
    }

    _notifs.startRealtimeListener(uid);

    _unreadMsgSub = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', uid)
        .listen(
          (rows) {
            final unread = rows.where((m) => m['is_read'] != true).length;
            if (mounted && unread != _unreadMessagesCount) {
              setState(() => _unreadMessagesCount = unread);
            }
          },
          onError: (_) {},
        );

    _unreadNotifSub = _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .listen(
          (rows) {
            final unread = rows.where((n) => n['is_read'] != true).length;
            if (mounted && unread != _unreadNotifsCount) {
              setState(() => _unreadNotifsCount = unread);
            }
          },
          onError: (_) {},
        );
  }

  void _showTopStatusBanner({
    required String title,
    required String message,
    bool isError = false,
  }) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ShellTopToast(
        title: title,
        message: message,
        isError: isError,
        onDismissed: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
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
      'mechanic' => 'محفظة الورشة والعمولات',
      'towing' => 'محفظة الونش والعمولات',
      _ => 'محفظة التاجر والعمولات',
    };
    Navigator.push(
      context,
      animatedRoute(
        Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ProviderWalletView(
            profile: p,
            onRefreshProfile: widget.onRefreshProfile,
          ),
        ),
      ),
    );
  }

  void _openCustomerPayments(CustomerProfile? p) {
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

  void _openUserProfile(CustomerProfile? p) {
    if (p == null) {
      Navigator.push(
        context,
        animatedRoute(LoginScreen(onAuthenticated: widget.onRefreshProfile)),
      );
      return;
    }
    Navigator.push(
      context,
      animatedRoute(
        UserProfileScreen(
          profile: p,
          onSaved: widget.onRefreshProfile,
        ),
      ),
    );
  }

  void _openSupportScreen() =>
      Navigator.push(context, animatedRoute(const SupportScreen()));

  Future<void> _signOut() async {
    await _notifs.stopRealtimeListener();
    await _db.auth.signOut();
    widget.onSignedOut();
  }

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
              decoration: const BoxDecoration(
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
                  Text(
                    '• الباقة السنوية: منشورات لا نهائية + 0% عمولة',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.orange,
                    ),
                  ),
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
                          _showTopStatusBanner(
                            title: 'تم تحديث كلمة المرور',
                            message: 'تم حفظ كلمة المرور الجديدة بنجاح.',
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
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
      _profileTab(isProvider, isAdmin),
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

  /// شاشة الرئيسية (الإعلانات + التتبع المباشر + اختصارات الوصول السريع)
  Widget _shortcutsHomeTab() {
    final p = widget.profile;
    final isLoggedIn = p != null;
    final role = p?.role ?? 'user';
    final isAdmin = p != null && (p.isAdmin || role == 'admin');
    final isProvider =
        role == 'merchant' || role == 'mechanic' || role == 'towing';
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
          // زر البروفايل السريع في الأعلى
          IconButton(
            tooltip: 'البروفايل',
            icon: const Icon(Icons.account_circle_outlined,
                color: AppColors.navy, size: 25),
            onPressed: () => _openUserProfile(p),
          ),
          // زر الدردشات مع شارة عدد الرسائل غير المقروءة
          IconButton(
            tooltip: 'الدردشات',
            icon: Badge(
              isLabelVisible: isLoggedIn && _unreadMessagesCount > 0,
              backgroundColor: Colors.red,
              label: Text(
                _unreadMessagesCount > 99 ? '99+' : '$_unreadMessagesCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  color: AppColors.navy, size: 23),
            ),
            onPressed: () {
              if (!isLoggedIn) {
                Navigator.push(
                  context,
                  animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile),
                  ),
                );
                return;
              }
              Navigator.push(context, animatedRoute(const ChatsListScreen()));
            },
          ),
          // زر الإشعارات مع شارة العداد المباشر
          if (isLoggedIn)
            const NotificationBellButton(iconColor: AppColors.navy)
          else
            IconButton(
              tooltip: 'الإشعارات',
              icon: const Icon(Icons.notifications_none,
                  color: AppColors.navy, size: 25),
              onPressed: () {
                Navigator.push(
                  context,
                  animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile),
                  ),
                );
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          widget.onRefreshProfile();
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          children: [
            // بطاقة الترحيب العلوية الداكنة (قابلة للنقر لفتح البروفايل + تعرض التقييم)
            BounceTap(
              onTap: () => _openUserProfile(p),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
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
                              if (isLoggedIn && isProvider)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.amber.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          color: Colors.amber, size: 14),
                                      const SizedBox(width: 3),
                                      Text(
                                        p.ratingCount > 0
                                            ? '${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})'
                                            : 'تقييم جديد',
                                        style: const TextStyle(
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
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            // بانر الإعلانات المتعددة القابل للتمرير الأفقي في الصفحة الرئيسية
            const SizedBox(height: 12),
            const HomeAdBanner(),

            // بانر التتبع المباشر المتعدد للورش والطوارئ مع التمرير الأفقي
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
                            if (item.badgeCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.badgeCount > 99
                                      ? '99+'
                                      : '${item.badgeCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
          subtitle: 'التسعيرات، الحسابات، الإعلانات والمالية',
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
          badgeCount: _unreadMessagesCount,
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
          title: 'المحفظة والعمولات',
          subtitle: 'الأرباح المستحقة ودفع عمولة التطبيق',
          icon: Icons.account_balance_wallet_outlined,
          iconColor: const Color(0xFF0F766E),
          iconBg: const Color(0xFFCCFBF1),
          onTap: () => _openProviderWallet(p),
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
          subtitle: 'نشر قطعة من مخزون الورشة',
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: showPayments ? 'الباقات والاشتراكات' : 'متجر قطع الغيار',
          subtitle: showPayments
              ? 'تصدر نتائج البحث وعمولة أقل'
              : 'شراء قطع لسيارات الزبائن',
          icon: showPayments
              ? Icons.workspace_premium_outlined
              : Icons.storefront_outlined,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
          onTap: showPayments
              ? openProviderPlans
              : () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: 'الدردشات',
          subtitle: 'التواصل المباشر مع الزبائن',
          icon: Icons.chat_bubble_outline,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFE0F2FE),
          badgeCount: _unreadMessagesCount,
          onTap: openChats,
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
          title: 'محفظة التاجر والعمولات',
          subtitle: 'الأرباح المستحقة ودفع عمولة التطبيق',
          icon: Icons.account_balance_wallet_outlined,
          iconColor: const Color(0xFF0F766E),
          iconBg: const Color(0xFFCCFBF1),
          onTap: () => _openProviderWallet(p),
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
          badgeCount: _unreadMessagesCount,
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
        _ShortcutItem(
          title: 'المحفظة والعمولات',
          subtitle: 'الأرباح المستحقة ودفع عمولة التطبيق',
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
          badgeCount: _unreadMessagesCount,
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
        subtitle: 'مراجعة فواتيرك وجميع مدفوعاتك',
        icon: Icons.receipt_long_outlined,
        iconColor: const Color(0xFF0F766E),
        iconBg: const Color(0xFFCCFBF1),
        onTap: () => _openCustomerPayments(p),
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
        title: showPayments ? 'الباقات والاشتراكات' : 'الدعم الفني',
        subtitle: showPayments
            ? 'مزايا وخصومات حصرية'
            : 'فريق الدعم جاهز لمساعدتك',
        icon: showPayments
            ? Icons.workspace_premium_outlined
            : Icons.support_agent,
        iconColor: const Color(0xFFD97706),
        iconBg: const Color(0xFFFEF3C7),
        onTap: () {
          if (!showPayments) {
            _openSupportScreen();
            return;
          }
          if (p == null) {
            Navigator.push(
              context,
              animatedRoute(
                LoginScreen(onAuthenticated: widget.onRefreshProfile),
              ),
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
      _ShortcutItem(
        title: 'الدردشات',
        subtitle: 'محادثاتك مع التجار والورش',
        icon: Icons.chat_bubble_outline,
        iconColor: const Color(0xFF0284C7),
        iconBg: const Color(0xFFE0F2FE),
        badgeCount: _unreadMessagesCount,
        onTap: openChats,
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
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
                      if (isProvider && p.ratingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 13),
                              const SizedBox(width: 3),
                              Text(
                                '${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})',
                                style: const TextStyle(
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

          // زر المحفظة ودفع العمولات للتاجر والميكانيكي وصاحب الونش
          if (isLoggedIn && isProvider) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xFF0F766E)),
              title: const Text(
                'المحفظة المالية ودفع العمولات',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'الأرباح، سجل الحركات، وتسوية العمولة',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
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

          // خيار المدفوعات وسجل الدفعات للمستخدم العادي
          if (isLoggedIn && !isProvider && !isAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined,
                  color: Color(0xFF0F766E)),
              title: const Text(
                'المدفوعات وسجل الدفعات',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'مراجعة جميع الفواتير والمدفوعات السابقة',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () {
                Navigator.pop(context);
                _openCustomerPayments(p);
              },
            ),
          ],

          if (isLoggedIn) ...[
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.chat_bubble_outline, color: AppColors.navy),
              title: const Text('الدردشات'),
              trailing: _unreadMessagesCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _unreadMessagesCount > 99
                            ? '99+'
                            : '$_unreadMessagesCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, animatedRoute(const ChatsListScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('الإشعارات'),
              trailing: _unreadNotifsCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _unreadNotifsCount > 99
                            ? '99+'
                            : '$_unreadNotifsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
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
              title: const Text(
                'تسجيل الدخول',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  animatedRoute(
                    LoginScreen(onAuthenticated: widget.onRefreshProfile),
                  ),
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
                    SignUpScreen(onAuthenticated: widget.onRefreshProfile),
                  ),
                );
              },
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                Navigator.pop(context);
                await _signOut();
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
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
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
                  LoginScreen(onAuthenticated: widget.onRefreshProfile),
                ),
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

  Widget _profileTab(bool isProvider, bool isAdmin) {
    final p = widget.profile;
    if (p == null) {
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
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${p.username ?? ""} · ${p.phone ?? ""}'),
                  if (isProvider && p.ratingCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'التقييم: ${p.ratingAvg.toStringAsFixed(1)} من 5 (${p.ratingCount} تقييم)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.badge_outlined, color: AppColors.orange),
              title: const Text('البروفايل (معلوماتي الشخصية)'),
              subtitle: const Text('عرض وتعديل الاسم، الهاتف، ومعلومات النشاط'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _openUserProfile(p),
            ),
          ),
          if (isProvider) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFF0F766E)),
                title: const Text('المحفظة المالية ودفع العمولات'),
                subtitle: const Text('عرض الأرباح، الحركات، وتسوية العمولة'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openProviderWallet(p),
              ),
            ),
          ] else if (!isAdmin) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined,
                    color: Color(0xFF0F766E)),
                title: const Text('المدفوعات وسجل الدفعات'),
                subtitle: const Text('مراجعة جميع الفواتير والدفعات السابقة'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _openCustomerPayments(p),
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
              onTap: _signOut,
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
  final int badgeCount;
  final VoidCallback onTap;

  const _ShortcutItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.highlighted = false,
    this.badgeCount = 0,
    required this.onTap,
  });
}

class _ShellTopToast extends StatefulWidget {
  final String title;
  final String message;
  final bool isError;
  final VoidCallback onDismissed;

  const _ShellTopToast({
    required this.title,
    required this.message,
    required this.isError,
    required this.onDismissed,
  });

  @override
  State<_ShellTopToast> createState() => _ShellTopToastState();
}

class _ShellTopToastState extends State<_ShellTopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _ctrl.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isError ? const Color(0xFFDC2626) : AppColors.success;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: const ValueKey('shell_top_toast'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismissed(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: bg.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: _dismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}