import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/app_locale_service.dart';
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
  final _loc = AppLocaleService.instance;
  final _db = Supabase.instance.client;

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
      'mechanic' => _loc.tr('محفظة الورشة والعمولات', 'Workshop Wallet'),
      'towing' => _loc.tr('محفظة الونش والعمولات', 'Winch Wallet'),
      _ => _loc.tr('محفظة التاجر والعمولات', 'Merchant Wallet'),
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
              _loc.tr(
                'وصلت للحد الأقصى ($usedCount / $maxLimit منشور)',
                'Post Limit Reached ($usedCount / $maxLimit)',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _loc.tr(
                'اشترك بإحدى باقات المزودين لزيادة عدد منشوراتك، وتقليل العمولة، وتصدر نتائج البحث في المتجر.',
                'Upgrade your provider plan to get more listings, lower commission, and higher search visibility.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
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
                label: Text(
                  _loc.tr('استعراض الباقات والاشتراك الآن', 'View Plans'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_loc.tr('لاحقاً', 'Later')),
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
          title: Text(_loc.tr('تغيير كلمة المرور', 'Change Password')),
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
                decoration: InputDecoration(
                  labelText:
                      _loc.tr('كلمة المرور الحالية', 'Current Password'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _loc.tr('كلمة المرور الجديدة', 'New Password'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _loc.tr(
                      'تأكيد كلمة المرور الجديدة', 'Confirm New Password'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_loc.tr('إلغاء', 'Cancel')),
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
                        setD(() => alertMsg = _loc.tr(
                              'كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل.',
                              'Password must be at least 6 characters.',
                            ));
                        return;
                      }
                      if (newPassCtrl.text != confirmPassCtrl.text) {
                        setD(() => alertMsg = _loc.tr(
                              'كلمة المرور الجديدة وتأكيدها غير متطابقتين.',
                              'Passwords do not match.',
                            ));
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
                          throw Exception('Email unavailable');
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
                            title: _loc.tr(
                                'تم تحديث كلمة المرور', 'Password Updated'),
                            message: _loc.tr(
                              'تم حفظ كلمة المرور الجديدة بنجاح.',
                              'Your new password has been saved.',
                            ),
                          );
                        }
                      } catch (_) {
                        setD(() {
                          saving = false;
                          alertMsg = _loc.tr(
                            'تنبيه أمني: كلمة المرور الحالية غير صحيحة!',
                            'Current password is incorrect!',
                          );
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
                  : Text(_loc.tr('حفظ كلمة المرور', 'Save Password')),
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
    return ValueListenableBuilder<String>(
      valueListenable: _loc.langCode,
      builder: (_, __, ___) {
        final p = widget.profile;
        final role = p?.role ?? 'user';
        final isAdmin = p != null && (p.isAdmin || role == 'admin');
        final isMerchant = role == 'merchant';
        final isProvider =
            isMerchant || role == 'mechanic' || role == 'towing';
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
              : _loginRequiredView(_loc.tr(
                  'لطلب مساعدة طارئة يرجى تسجيل الدخول',
                  'Please sign in to request roadside emergency help',
                )),
          isLoggedIn
              ? CustomerAppointmentsScreen(
                  customerProfile: p,
                  onRefreshProfile: widget.onRefreshProfile,
                )
              : _loginRequiredView(_loc.tr(
                  'لعرض وحجز مواعيد الورشة يرجى تسجيل الدخول',
                  'Please sign in to view or book workshop appointments',
                )),
          _profileTab(isProvider, isAdmin),
        ];

        final safeIndex = _index.clamp(0, pages.length - 1);
        final bool isEmergencyTab = safeIndex == 2;
        final bool showAddFab = canPublish && !isEmergencyTab;

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

              // إخفاء زر فحص AI العائم في شاشة الطوارئ لمنع تغطية أزرار القبول/الرفض/الفاتورة
              if (!isEmergencyTab)
                Positioned(
                  left: 14,
                  bottom: 20,
                  child: BounceTap(
                    onTap: () => showAiDiagnosticSheet(context,
                        viewerProfile: widget.profile),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: AppColors.orange, size: 19),
                          const SizedBox(width: 6),
                          Text(
                            _loc.tr('فحص AI', 'AI Check'),
                            style: const TextStyle(
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
          floatingActionButton: showAddFab
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
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: BottomAppBar(
            color: AppColors.surface,
            elevation: 10,
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            shape: showAddFab ? const CircularNotchedRectangle() : null,
            notchMargin: 7,
            child: showAddFab
                ? Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _navItem(0, Icons.grid_view_rounded,
                                _loc.tr('الرئيسية', 'Home')),
                            _navItem(1, Icons.storefront_outlined,
                                _loc.tr('المتجر', 'Store')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 68),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _navItem(2, Icons.car_crash_outlined,
                                _loc.tr('طوارئ', 'SOS')),
                            _navItem(3, Icons.event_note_outlined,
                                _loc.tr('المواعيد', 'Bookings')),
                            _navItem(4, Icons.person_outline,
                                _loc.tr('حسابي', 'Account')),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(0, Icons.grid_view_rounded,
                          _loc.tr('الرئيسية', 'Home')),
                      _navItem(1, Icons.storefront_outlined,
                          _loc.tr('المتجر', 'Store')),
                      _navItem(2, Icons.car_crash_outlined,
                          _loc.tr('طوارئ', 'SOS')),
                      _navItem(3, Icons.event_note_outlined,
                          _loc.tr('المواعيد', 'Bookings')),
                      _navItem(4, Icons.person_outline,
                          _loc.tr('حسابي', 'Account')),
                    ],
                  ),
          ),
        );
      },
    );
  }

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
            : (p.fullName?.isNotEmpty == true
                ? p.fullName!
                : _loc.tr('مستخدم غيارك', 'Ghiyarak User')))
        : _loc.tr('زائر غيارك', 'Guest');

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GhiyarakLogo(size: 32),
            const SizedBox(width: 8),
            Text(
              _loc.tr('غيارك', 'Ghiyarak'),
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        actions: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              _loc.toggleLanguage();
              _showTopStatusBanner(
                title: _loc.tr('تم تغيير اللغة', 'Language Changed'),
                message: _loc.tr(
                  'تم التبديل إلى اللغة العربية',
                  'Switched to English',
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.navy.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, color: AppColors.navy, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _loc.isEnglish ? 'عربي' : 'EN',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: _loc.tr('الدردشات', 'Chats'),
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
          if (isLoggedIn)
            const NotificationBellButton(iconColor: AppColors.navy)
          else
            IconButton(
              tooltip: _loc.tr('الإشعارات', 'Notifications'),
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
                            _loc.tr(
                              'أهلاً بك، $displayName',
                              'Welcome, $displayName',
                            ),
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
                                  _roleDisplayName(isAdmin
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified,
                                          color: Color(0xFF38BDF8), size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        _loc.tr('حساب موثق', 'Verified'),
                                        style: const TextStyle(
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
                                      color:
                                          Colors.amber.withValues(alpha: 0.5),
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
                                            : _loc.tr('جديد', 'New'),
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
            const SizedBox(height: 12),
            const HomeAdBanner(),
            if (isLoggedIn) ...[
              const SizedBox(height: 12),
              HomeLiveProgressBanner(viewerProfile: p),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.grid_view_rounded,
                    color: AppColors.orange, size: 22),
                const SizedBox(width: 8),
                Text(
                  _loc.tr('اختصارات الوصول السريع', 'Quick Shortcuts'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
          title: _loc.tr('لوحة السوبر أدمن', 'Admin Panel'),
          subtitle: _loc.tr(
            'التسعيرات، الحسابات، الإعلانات والمالية',
            'Pricing, accounts, ads & finance',
          ),
          icon: Icons.admin_panel_settings_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: _loc.tr('قطع الغيار والمخزون', 'Parts & Inventory'),
          subtitle: _loc.tr(
              'إدارة القطع، الإخفاء والخصومات', 'Manage listings & discounts'),
          icon: Icons.inventory_2_outlined,
          iconColor: const Color(0xFF334155),
          iconBg: const Color(0xFFE2E8F0),
          onTap: () => Navigator.push(
              context, animatedRoute(const MerchantProductsDashboard())),
        ),
        _ShortcutItem(
          title: _loc.tr('إضافة قطعة غيار', 'Add Spare Part'),
          subtitle: _loc.tr('نشر قطعة جديدة في المتجر', 'Publish a new part'),
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: _loc.tr('متجر قطع الغيار', 'Parts Store'),
          subtitle: _loc.tr('تصفح جميع القطع والمنشورات', 'Browse all parts'),
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: _loc.tr('الطوارئ والونش', 'Emergency & Tow'),
          subtitle: _loc.tr('طلب ونش أو ميكانيكي طوارئ', 'Roadside assistance'),
          icon: Icons.car_crash_outlined,
          iconColor: const Color(0xFFB45309),
          iconBg: const Color(0xFFFEF3C7),
          onTap: () => setState(() => _index = 2),
        ),
        _ShortcutItem(
          title: _loc.tr('الدردشات', 'Chats'),
          subtitle:
              _loc.tr('التواصل المباشر مع المستخدمين', 'Direct messaging'),
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
          title: _loc.tr('لوحة الورشة والطوارئ', 'Workshop Dashboard'),
          subtitle: _loc.tr(
              'استقبال المواعيد وطلبات الإنقاذ', 'Manage bookings & SOS'),
          icon: Icons.build_circle_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: _loc.tr('المحفظة والعمولات', 'Wallet & Payouts'),
          subtitle: _loc.tr('سحب الأرباح ودفع عمولة التطبيق',
              'Withdraw earnings & settle fees'),
          icon: Icons.account_balance_wallet_outlined,
          iconColor: const Color(0xFF0F766E),
          iconBg: const Color(0xFFCCFBF1),
          onTap: () => _openProviderWallet(p),
        ),
        _ShortcutItem(
          title: _loc.tr('قطع الغيار والمخزون', 'Parts & Inventory'),
          subtitle: _loc.tr(
              'إدارة القطع، الإخفاء والخصومات', 'Manage parts & offers'),
          icon: Icons.inventory_2_outlined,
          iconColor: const Color(0xFF334155),
          iconBg: const Color(0xFFE2E8F0),
          onTap: () => Navigator.push(
              context, animatedRoute(const MerchantProductsDashboard())),
        ),
        _ShortcutItem(
          title: _loc.tr('إضافة قطعة غيار', 'Add Spare Part'),
          subtitle: _loc.tr('نشر قطعة من مخزون الورشة', 'Post from inventory'),
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: showPayments
              ? _loc.tr('الباقات والاشتراكات', 'Subscription Plans')
              : _loc.tr('متجر قطع الغيار', 'Parts Store'),
          subtitle: showPayments
              ? _loc.tr('تصدر نتائج البحث وعمولة أقل', 'Lower commission')
              : _loc.tr('شراء قطع لسيارات الزبائن', 'Browse parts'),
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
          title: _loc.tr('الدردشات', 'Chats'),
          subtitle:
              _loc.tr('التواصل المباشر مع الزبائن', 'Chat with customers'),
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
          title: _loc.tr('قطع الغيار والمخزون', 'My Inventory'),
          subtitle: _loc.tr(
              'إدارة القطع، الإخفاء والخصومات', 'Manage parts & discounts'),
          icon: Icons.inventory_2_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: _loc.tr('محفظة التاجر والعمولات', 'Merchant Wallet'),
          subtitle: _loc.tr('سحب الأرباح ودفع عمولة التطبيق',
              'Withdraw earnings & settle fees'),
          icon: Icons.account_balance_wallet_outlined,
          iconColor: const Color(0xFF0F766E),
          iconBg: const Color(0xFFCCFBF1),
          onTap: () => _openProviderWallet(p),
        ),
        _ShortcutItem(
          title: _loc.tr('إضافة قطعة غيار', 'Add Spare Part'),
          subtitle: _loc.tr('نشر قطعة جديدة في المتجر', 'List a new part'),
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: _loc.tr('متجر قطع الغيار', 'Parts Store'),
          subtitle: _loc.tr('تصفح جميع القطع والعروض', 'Browse all listings'),
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: showPayments
              ? _loc.tr('الباقات والاشتراكات', 'Subscription Plans')
              : _loc.tr('مواعيد الورش', 'Workshop Bookings'),
          subtitle: showPayments
              ? _loc.tr('زيادة حد المنشورات وتصدر البحث', 'Boost visibility')
              : _loc.tr('حجوزات ومواعيد الصيانة', 'Maintenance bookings'),
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
          title: _loc.tr('الدردشات', 'Chats'),
          subtitle: _loc.tr('التواصل المباشر مع الزبائن', 'Chat with buyers'),
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
          title: _loc.tr('لوحة الونش والإنقاذ', 'Towing Dashboard'),
          subtitle:
              _loc.tr('استقبال طلبات السحب المباشرة', 'Live towing requests'),
          icon: Icons.local_shipping_outlined,
          iconColor: AppColors.orange,
          iconBg: AppColors.orange.withValues(alpha: 0.16),
          highlighted: true,
          onTap: () => _openDashboardForRole(p),
        ),
        _ShortcutItem(
          title: _loc.tr('المحفظة والعمولات', 'Wallet & Payouts'),
          subtitle: _loc.tr('سحب الأرباح ودفع عمولة التطبيق',
              'Withdraw earnings & settle fees'),
          icon: Icons.account_balance_wallet_outlined,
          iconColor: const Color(0xFF0F766E),
          iconBg: const Color(0xFFCCFBF1),
          onTap: () => _openProviderWallet(p),
        ),
        _ShortcutItem(
          title: _loc.tr('إضافة قطعة غيار', 'Add Spare Part'),
          subtitle: _loc.tr('نشر قطعة للبيع في المتجر', 'List a part'),
          icon: Icons.add_box_outlined,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          onTap: _handleAddProductTap,
        ),
        _ShortcutItem(
          title: _loc.tr('متجر قطع الغيار', 'Parts Store'),
          subtitle: _loc.tr('تصفح جميع القطع والمنشورات', 'Browse parts'),
          icon: Icons.storefront_outlined,
          iconColor: const Color(0xFF4338CA),
          iconBg: const Color(0xFFE0E7FF),
          onTap: () => setState(() => _index = 1),
        ),
        _ShortcutItem(
          title: showPayments
              ? _loc.tr('الباقات والاشتراكات', 'Plans')
              : _loc.tr('الدعم الفني', 'Support'),
          subtitle: showPayments
              ? _loc.tr('عمولة أقل وظهور مميز', 'Lower fees & boost')
              : _loc.tr('المساعدة على مدار الساعة', '24/7 help'),
          icon: showPayments
              ? Icons.workspace_premium_outlined
              : Icons.support_agent,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
          onTap: showPayments ? openProviderPlans : _openSupportScreen,
        ),
        _ShortcutItem(
          title: _loc.tr('الدردشات', 'Chats'),
          subtitle:
              _loc.tr('التواصل المباشر مع الزبائن', 'Chat with customers'),
          icon: Icons.chat_bubble_outline,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFE0F2FE),
          badgeCount: _unreadMessagesCount,
          onTap: openChats,
        ),
      ];
    }

    return [
      _ShortcutItem(
        title: _loc.tr('متجر قطع الغيار', 'Parts Store'),
        subtitle: _loc.tr(
            'ابحث وتواصل مباشرة مع التجار', 'Search & contact merchants'),
        icon: Icons.storefront_outlined,
        iconColor: AppColors.orange,
        iconBg: AppColors.orange.withValues(alpha: 0.16),
        highlighted: true,
        onTap: () => setState(() => _index = 1),
      ),
      _ShortcutItem(
        title: showWinch
            ? _loc.tr('طوارئ / ونش وميكانيكي', 'Emergency & Tow')
            : _loc.tr('ميكانيكي طوارئ', 'Emergency Mechanic'),
        subtitle: _loc.tr('مساعدة فورية على الطريق', 'Instant roadside rescue'),
        icon: Icons.car_crash_outlined,
        iconColor: const Color(0xFFDC2626),
        iconBg: const Color(0xFFFEE2E2),
        onTap: () => setState(() => _index = 2),
      ),
      _ShortcutItem(
        title: _loc.tr('حجز موعد ورشة', 'Book Workshop'),
        subtitle:
            _loc.tr('احجز صيانة في ورشة معتمدة', 'Schedule certified service'),
        icon: Icons.event_available_outlined,
        iconColor: const Color(0xFF15803D),
        iconBg: const Color(0xFFDCFCE7),
        onTap: () => setState(() => _index = 3),
      ),
      _ShortcutItem(
        title: _loc.tr('المدفوعات وسجل الدفعات', 'Payment History'),
        subtitle:
            _loc.tr('مراجعة فواتيرك وجميع مدفوعاتك', 'Review all invoices'),
        icon: Icons.receipt_long_outlined,
        iconColor: const Color(0xFF0F766E),
        iconBg: const Color(0xFFCCFBF1),
        onTap: () => _openCustomerPayments(p),
      ),
      _ShortcutItem(
        title: _loc.tr('فحص الأعطال بالـ AI', 'AI Diagnostics'),
        subtitle:
            _loc.tr('شخّص عطل سيارتك فوراً', 'Diagnose car issues instantly'),
        icon: Icons.auto_awesome,
        iconColor: const Color(0xFF4338CA),
        iconBg: const Color(0xFFE0E7FF),
        onTap: () =>
            showAiDiagnosticSheet(context, viewerProfile: widget.profile),
      ),
      _ShortcutItem(
        title: showPayments
            ? _loc.tr('الباقات والاشتراكات', 'Membership Plans')
            : _loc.tr('الدعم الفني', 'Support'),
        subtitle: showPayments
            ? _loc.tr('مزايا وخصومات حصرية', 'Exclusive perks & 0% fee')
            : _loc.tr('فريق الدعم جاهز لمساعدتك', 'We are here to help'),
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
        title: _loc.tr('الدردشات', 'Chats'),
        subtitle: _loc.tr(
            'محادثاتك مع التجار والورش', 'Messages with shops & mechanics'),
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
                Row(
                  children: [
                    const GhiyarakLogo(size: 42),
                    const SizedBox(width: 10),
                    Text(
                      _loc.tr('غيارك', 'Ghiyarak'),
                      style: const TextStyle(
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
                      : _loc.tr('مرحباً بك في غيارك (تصفح كزائر)',
                          'Welcome to Ghiyarak (Guest)'),
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
                          _roleDisplayName(isAdmin ? 'admin' : role),
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
                title: Text(
                  _loc.tr('لوحة التحكم', 'Dashboard'),
                  style: const TextStyle(
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
            title: Text(_loc.tr('الرئيسية (الاختصارات)', 'Home')),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.storefront, color: AppColors.navy),
            title: Text(_loc.tr('متجر قطع الغيار', 'Parts Store')),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.car_crash_outlined),
            title: Text(_loc.tr('طلب مساعدة طارئة', 'Emergency Help')),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: Text(_loc.tr('مواعيد الورشة', 'Workshop Bookings')),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = 3);
            },
          ),
          if (isLoggedIn && isProvider) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xFF0F766E)),
              title: Text(
                _loc.tr('المحفظة المالية وسحب الأرباح', 'Wallet & Payouts'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _loc.tr('الأرباح، سحب للبنك، وتسوية العمولة',
                    'Withdraw to bank & settle fees'),
                style: const TextStyle(fontSize: 11),
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
              title: Text(_loc.tr('إضافة منشور قطعة غيار', 'Add Spare Part')),
              onTap: () {
                Navigator.pop(context);
                _handleAddProductTap();
              },
            ),
          ],
          if (isLoggedIn && !isProvider && !isAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined,
                  color: Color(0xFF0F766E)),
              title: Text(
                _loc.tr('المدفوعات وسجل الدفعات', 'Payment History'),
                style: const TextStyle(fontWeight: FontWeight.w700),
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
              title: Text(_loc.tr('الدردشات', 'Chats')),
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
              title: Text(_loc.tr('الإشعارات', 'Notifications')),
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
            leading: const Icon(Icons.language, color: AppColors.navy),
            title: Text(_loc.tr('تغيير اللغة (English)', 'Language (العربية)')),
            onTap: () {
              Navigator.pop(context);
              _loc.toggleLanguage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent, color: AppColors.orange),
            title: Text(_loc.tr('الدعم الفني والمساعدة', 'Support & Help')),
            onTap: () {
              Navigator.pop(context);
              _openSupportScreen();
            },
          ),
          const Divider(),
          if (!isLoggedIn) ...[
            ListTile(
              leading: const Icon(Icons.login, color: AppColors.orange),
              title: Text(
                _loc.tr('تسجيل الدخول', 'Sign In'),
                style: const TextStyle(fontWeight: FontWeight.bold),
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
              title: Text(_loc.tr('إنشاء حساب جديد', 'Create Account')),
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
              title: Text(_loc.tr('تسجيل الخروج', 'Sign Out')),
              onTap: () async {
                Navigator.pop(context);
                await _signOut();
              },
            ),
        ],
      ),
    );
  }

  String _roleDisplayName(String role) => switch (role) {
        'admin' => _loc.tr('مدير النظام (Admin)', 'Admin'),
        'mechanic' => _loc.tr('ميكانيكي / ورشة', 'Mechanic / Workshop'),
        'towing' => _loc.tr('صاحب ونش طوارئ', 'Tow Driver'),
        'merchant' => _loc.tr('تاجر قطع غيار', 'Parts Merchant'),
        'guest' => _loc.tr('زائر', 'Guest'),
        _ => _loc.tr('مستخدم عادي', 'Customer'),
      };

  String _roleDashboardSubtitle(String role) => switch (role) {
        'admin' => _loc.tr('إدارة النظام والإعلانات والتجار', 'System & Finance'),
        'mechanic' => _loc.tr('الورشة وطلبات الطوارئ', 'Workshop & SOS'),
        'towing' => _loc.tr('طلبات الونش المباشرة', 'Live Tow Requests'),
        'merchant' => _loc.tr('إدارة المنتجات والمبيعات', 'Manage Products'),
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
              child: Text(
                  _loc.tr('تسجيل الدخول / إنشاء حساب', 'Sign In / Sign Up')),
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
            _loginRequiredView(
                _loc.tr('سجل دخولك لإدارة حسابك', 'Sign in to manage account')),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.support_agent, color: AppColors.orange),
                title: Text(_loc.tr('الدعم الفني والمساعدة', 'Support & Help')),
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
                p.fullName ?? _loc.tr('المستخدم', 'User'),
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
                          _loc.tr(
                            'التقييم: ${p.ratingAvg.toStringAsFixed(1)} من 5 (${p.ratingCount} تقييم)',
                            'Rating: ${p.ratingAvg.toStringAsFixed(1)} / 5 (${p.ratingCount})',
                          ),
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
              title: Text(_loc.tr('البروفايل (معلوماتي الشخصية)', 'My Profile')),
              subtitle: Text(_loc.tr(
                'عرض وتعديل الاسم، الهاتف، ومعلومات النشاط',
                'View & edit name, phone and workshop info',
              )),
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
                title: Text(_loc.tr(
                  'المحفظة المالية وسحب الأرباح للبنك',
                  'Wallet & Bank Withdrawals',
                )),
                subtitle: Text(_loc.tr(
                  'الأرباح، سحب للبنك (IBAN)، وتسوية العمولة',
                  'Earnings, IBAN payouts & commissions',
                )),
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
                title: Text(
                    _loc.tr('المدفوعات وسجل الدفعات', 'Payment History')),
                subtitle: Text(_loc.tr(
                  'مراجعة جميع الفواتير والدفعات السابقة',
                  'Review all invoices & receipts',
                )),
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
                    ? _loc.tr('باقات واشتراكات المزودين', 'Provider Plans')
                    : _loc.tr('اشتراك المستخدم العادي (البرو)', 'Pro Plan')),
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
              leading: const Icon(Icons.language, color: AppColors.navy),
              title: Text(_loc.tr('اللغة (التبديل إلى English)',
                  'Language (Switch to العربية)')),
              trailing: const Icon(Icons.swap_horiz, color: AppColors.orange),
              onTap: () => _loc.toggleLanguage(),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset, color: AppColors.navy),
              title: Text(_loc.tr('تغيير كلمة المرور', 'Change Password')),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showChangePasswordDialog,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent, color: AppColors.orange),
              title: Text(_loc.tr('الدعم الفني والمساعدة', 'Support & Help')),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _openSupportScreen,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(_loc.tr('تسجيل الخروج', 'Sign Out')),
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