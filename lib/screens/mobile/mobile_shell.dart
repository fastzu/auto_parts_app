import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
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

  const LiveMobileShell(
      {super.key,
      required this.profile,
      required this.onRefreshProfile,
      required this.onSignedOut});

  @override
  State<LiveMobileShell> createState() => _LiveMobileShellState();
}

class _LiveMobileShellState extends State<LiveMobileShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _notifs = NotificationsService.instance;
  final _db = Supabase.instance.client;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.profile != null) {
        _notifs.startGlobalListener(context);
      }
    });
  }

  @override
  void didUpdateWidget(covariant LiveMobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.id != widget.profile?.id) {
      if (widget.profile != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _notifs.startGlobalListener(context);
          }
        });
      } else {
        _notifs.stopGlobalListener();
      }
    }
  }

  void _openDashboardForRole(CustomerProfile p) {
    final isAdmin = p.isAdmin || p.role == 'admin';
    Widget target;
    if (isAdmin) {
      target = SuperAdminDashboardScreen(
          profile: p, onSignedOut: widget.onSignedOut);
    } else if (p.role == 'mechanic') {
      target = WorkshopEmergencyDashboard(
          profile: p,
          onRefreshProfile: widget.onRefreshProfile,
          onSignedOut: widget.onSignedOut);
    } else if (p.role == 'towing' && EnvConfig.winchEnabled.value) {
      target = TowingDashboardScreen(
          profile: p,
          onRefreshProfile: widget.onRefreshProfile,
          onSignedOut: widget.onSignedOut);
    } else {
      target = const MerchantProductsDashboard();
    }
    Navigator.push(context, animatedRoute(target));
  }

  void _openSupportScreen() =>
      Navigator.push(context, animatedRoute(const SupportScreen()));

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
                      border: Border.all(color: Colors.red)),
                  child: Text(alertMsg!,
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              TextField(
                  controller: currentPassCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور الحالية')),
              const SizedBox(height: 10),
              TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور الجديدة')),
              const SizedBox(height: 10),
              TextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white),
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
                            email: email, password: currentPassCtrl.text);
                        await _db.auth.updateUser(
                            UserAttributes(password: newPassCtrl.text));
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم تحديث كلمة المرور بنجاح!'),
                                  backgroundColor: AppColors.success));
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
                          color: Colors.white, strokeWidth: 2))
                  : const Text('حفظ كلمة المرور'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.profile?.role ?? 'user';
    final isMerchant = role == 'merchant';
    final isProvider = isMerchant || role == 'mechanic' || role == 'towing';
    final isLoggedIn = widget.profile != null;

    final pages = [
      LiveStoreHomeScreen(
          profile: widget.profile,
          onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer()),
      isLoggedIn
          ? EmergencyScreen(profile: widget.profile!)
          : _loginRequiredView('لطلب مساعدة طارئة يرجى تسجيل الدخول'),
      isLoggedIn
          ? CustomerAppointmentsScreen(
              customerProfile: widget.profile!,
              onRefreshProfile: widget.onRefreshProfile)
          : _loginRequiredView('لعرض وحجز مواعيد الورشة يرجى تسجيل الدخول'),
      _profileTab(isProvider),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildRoleBasedDrawer(),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
          ),

          // زر الـ AI العائم في الزاوية السفلية (يفتح نافذة الفحص المنبثقة فوق أي صفحة)
          Positioned(
            left: 16,
            bottom: 16,
            child: BounceTap(
              onTap: () =>
                  showAiDiagnosticSheet(context, viewerProfile: widget.profile),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                      color: AppColors.navy.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: AppColors.orange, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'فحص AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isProvider
          ? BounceTap(
              onTap: () => Navigator.push(
                  context, animatedRoute(const AddProductScreen())),
              child: FloatingActionButton(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                onPressed: () => Navigator.push(
                    context, animatedRoute(const AddProductScreen())),
                child: const Icon(Icons.add, size: 28),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: isProvider ? const CircularNotchedRectangle() : null,
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.storefront_outlined, 'المتجر'),
            _navItem(1, Icons.car_crash_outlined, 'طوارئ'),
            if (isProvider) const SizedBox(width: 42),
            _navItem(2, Icons.event_note_outlined, 'المواعيد'),
            _navItem(3, Icons.person_outline, 'حسابي'),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBasedDrawer() {
    final p = widget.profile;
    final isLoggedIn = p != null;
    final role = p?.role ?? 'guest';
    final isAdmin = p != null && (p.isAdmin || role == 'admin');
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;
    final hasDashboard = isLoggedIn &&
        (isAdmin ||
            role == 'mechanic' ||
            role == 'merchant' ||
            (role == 'towing' && showWinch));

    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
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
                          color: AppColors.navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isLoggedIn
                      ? '${p.fullName ?? ""} · @${p.username ?? ""}'
                      : 'مرحباً بك في غيارك (تصفح كزائر)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                if (isLoggedIn) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      _roleArabicName(isAdmin ? 'admin' : role),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
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
                    borderRadius: BorderRadius.circular(14)),
                tileColor: AppColors.orangeLight,
                leading: const Icon(Icons.dashboard, color: AppColors.orange),
                title: const Text('لوحة التحكم',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.orange)),
                subtitle: Text(_roleDashboardSubtitle(isAdmin ? 'admin' : role),
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.navy)),
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
              leading: const Icon(Icons.storefront, color: AppColors.orange),
              title: const Text('الرئيسية (المتجر)'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 0);
              }),
          ListTile(
              leading: const Icon(Icons.car_crash_outlined),
              title: const Text('طلب مساعدة طارئة'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 1);
              }),
          ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('مواعيد الورشة'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 2);
              }),
          if (role == 'merchant') ...[
            const Divider(),
            if (showPayments)
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.navy),
                title: const Text('محفظة التاجر والأرباح'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    animatedRoute(
                      Scaffold(
                        appBar:
                            AppBar(title: const Text('محفظة التاجر والأرباح')),
                        body: _MerchantWalletView(providerId: p!.id),
                      ),
                    ),
                  );
                },
              ),
            ListTile(
                leading:
                    const Icon(Icons.add_box_outlined, color: AppColors.orange),
                title: const Text('إضافة منشور قطعة غيار'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context, animatedRoute(const AddProductScreen()));
                }),
          ],
          if (isLoggedIn) ...[
            const Divider(),
            ListTile(
                leading: const Icon(Icons.chat_bubble_outline,
                    color: AppColors.navy),
                title: const Text('الدردشات'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context, animatedRoute(const ChatsListScreen()));
                }),
            ListTile(
                leading: const Icon(Icons.notifications_none),
                title: const Text('الإشعارات'),
                onTap: () {
                  Navigator.pop(context);
                  _notifs.openNotificationsSheet(context);
                }),
          ],
          const Divider(),
          ListTile(
              leading: const Icon(Icons.support_agent, color: AppColors.orange),
              title: const Text('الدعم الفني والمساعدة'),
              onTap: () {
                Navigator.pop(context);
                _openSupportScreen();
              }),
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
                      animatedRoute(LoginScreen(
                          onAuthenticated: widget.onRefreshProfile)));
                }),
            ListTile(
                leading:
                    const Icon(Icons.person_add_alt_1, color: AppColors.navy),
                title: const Text('إنشاء حساب جديد'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      animatedRoute(SignUpScreen(
                          onAuthenticated: widget.onRefreshProfile)));
                }),
          ] else
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                Navigator.pop(context);
                _notifs.stopGlobalListener();
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
        _ => 'مستخدم عادي'
      };
  String _roleDashboardSubtitle(String role) => switch (role) {
        'admin' => 'إدارة النظام والإعلانات والتجار',
        'mechanic' => 'الورشة وطلبات الطوارئ',
        'towing' => 'طلبات الونش المباشرة',
        'merchant' => 'إدارة المنتجات والمشاهدات والنقرات',
        _ => ''
      };

  Widget _loginRequiredView(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 52, color: AppColors.navy),
          const SizedBox(height: 12),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 16),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
              onPressed: () => Navigator.push(
                  context,
                  animatedRoute(
                      LoginScreen(onAuthenticated: widget.onRefreshProfile))),
              child: const Text('تسجيل الدخول / إنشاء حساب'))
        ]),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: 3,
                width: active ? 22 : 0,
                margin: const EdgeInsets.only(bottom: 3),
                decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(4))),
            AnimatedScale(
                scale: active ? 1.18 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Icon(icon,
                    color: active ? AppColors.orange : AppColors.textSecondary,
                    size: 22)),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color:
                        active ? AppColors.orange : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _profileTab(bool isProvider) {
    if (widget.profile == null) {
      return SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        _loginRequiredView('سجل دخولك لإدارة حسابك'),
        const SizedBox(height: 16),
        Card(
            child: ListTile(
                leading:
                    const Icon(Icons.support_agent, color: AppColors.orange),
                title: const Text('الدعم الفني والمساعدة'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _openSupportScreen))
      ]));
    }
    final showPayments = EnvConfig.paymentsEnabled.value;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
              child: ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: AppColors.navy,
                      child: Icon(Icons.person, color: Colors.white)),
                  title: Text(widget.profile!.fullName ?? 'المستخدم',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '@${widget.profile!.username ?? ""} · ${widget.profile!.phone ?? ""}'))),
          const SizedBox(height: 12),
          Card(
              child: ListTile(
                  leading:
                      const Icon(Icons.badge_outlined, color: AppColors.orange),
                  title: const Text('البروفايل (معلوماتي الشخصية)'),
                  subtitle:
                      const Text('عرض وتعديل الاسم، الهاتف، ومعلومات النشاط'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(
                      context,
                      animatedRoute(UserProfileScreen(
                          profile: widget.profile!,
                          onSaved: widget.onRefreshProfile))))),
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
                        animatedRoute(isProvider
                            ? ProviderSubscriptionsScreen(
                                currentPlanCode:
                                    widget.profile!.subscriptionPlan,
                                onSubscribed: widget.onRefreshProfile)
                            : CustomerSubscriptionsScreen(
                                currentPlanCode:
                                    widget.profile!.subscriptionPlan,
                                onSubscribed: widget.onRefreshProfile))))),
          ],
          const SizedBox(height: 12),
          Card(
              child: ListTile(
                  leading: const Icon(Icons.lock_reset, color: AppColors.navy),
                  title: const Text('تغيير كلمة المرور'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangePasswordDialog)),
          const SizedBox(height: 12),
          Card(
              child: ListTile(
                  leading:
                      const Icon(Icons.support_agent, color: AppColors.orange),
                  title: const Text('الدعم الفني والمساعدة'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _openSupportScreen)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                _notifs.stopGlobalListener();
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

class _MerchantWalletView extends StatefulWidget {
  final String providerId;
  const _MerchantWalletView({required this.providerId});

  @override
  State<_MerchantWalletView> createState() => _MerchantWalletViewState();
}

class _MerchantWalletViewState extends State<_MerchantWalletView> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;

  @override
  Widget build(BuildContext context) {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('wallet_transactions')
          .stream(primaryKey: ['id'])
          .eq('provider_id', widget.providerId)
          .order('created_at', ascending: false),
      builder: (_, snap) {
        final allTxs =
            (snap.data ?? []).map(DbWalletTransaction.fromMap).toList();
        final txs = allTxs.where((t) {
          return !t.createdAt.isBefore(range.start) &&
              !t.createdAt.isAfter(range.end.add(const Duration(days: 1)));
        }).toList();

        final gross = txs.fold(0.0, (s, t) => s + t.grossAmount);
        final comm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
        final net = txs.fold(0.0, (s, t) => s + t.netAmount);

        return ListView(
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صافي محفظة التاجر (بعد العمولة)',
                      style: TextStyle(color: Colors.white70)),
                  Text(
                    '${net.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'قبل العمولة: ${gross.toStringAsFixed(2)} د.أ  |  العمولة: ${comm.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _miniStat('قبل العمولة', gross, AppColors.navy)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _miniStat('العمولة المقتطعة', comm, AppColors.orange)),
                const SizedBox(width: 8),
                Expanded(child: _miniStat('الصافي', net, AppColors.success)),
              ],
            ),
            const SizedBox(height: 14),
            InteractiveAnimatedChart(
              title: 'التحليل المالي لأرباح التاجر',
              unit: 'د.أ',
              data: [
                (label: 'قبل العمولة', value: gross),
                (label: 'العمولة', value: comm),
                (label: 'الصافي', value: net),
              ],
            ),
            const SizedBox(height: 14),
            const Text('سجل الحركات المالية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (txs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('لا توجد حركات مالية ضمن هذه الفترة',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              )
            else
              ...txs.map(
                (t) => Card(
                  child: ListTile(
                    title: Text(t.transactionType),
                    subtitle: Text(
                        'قبل العمولة: ${t.grossAmount} · عمولة: -${t.commissionAmount}'),
                    trailing: Text(
                      '+${t.netAmount.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _miniStat(String title, double val, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${val.toStringAsFixed(1)} د.أ',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
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
                color: AppColors.navy, borderRadius: BorderRadius.circular(18)),
            child: const Column(children: [
              GhiyarakLogo(size: 62),
              SizedBox(height: 12),
              Text('فريق دعم غيارك',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                  'نحن هنا لمساعدتك في أي استفسار أو مشكلة تقنية على مدار الساعة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12))
            ]),
          ),
          const SizedBox(height: 18),
          Card(
              child: ListTile(
                  leading: const Icon(Icons.phone, color: AppColors.orange),
                  title: const Text('الاتصال الهاتفي',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(EnvConfig.supportPhone),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () =>
                      launchUrl(Uri.parse('tel:${EnvConfig.supportPhone}')))),
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
                      mode: LaunchMode.externalApplication))),
          const SizedBox(height: 10),
          Card(
              child: ListTile(
                  leading:
                      const Icon(Icons.email_outlined, color: AppColors.navy),
                  title: const Text('البريد الإلكتروني',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(EnvConfig.supportEmail),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () => launchUrl(Uri.parse(
                      'mailto:${EnvConfig.supportEmail}?subject=دعم فني تطبيق غيارك')))),
        ],
      ),
    );
  }
}

class UserProfileScreen extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onSaved;
  const UserProfileScreen(
      {super.key, required this.profile, required this.onSaved});

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
          'workshop_address': _addressCtrl.text.trim()
      }).eq('id', widget.profile.id);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تحديث معلومات البروفايل بنجاح!'),
            backgroundColor: AppColors.success));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red));
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
                color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.fullName ?? 'المستخدم',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('اسم المستخدم: @${p.username ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('البريد الإلكتروني: ${p.email ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('نوع الحساب: ${p.role}',
                    style: const TextStyle(
                        color: AppColors.orange, fontWeight: FontWeight.bold)),
                if (_country != null || _age != null)
                  Text('الدولة: ${_country ?? "-"}  |  العمر: ${_age ?? "-"}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)))),
          const SizedBox(height: 12),
          TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: 'رقم الهاتف',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)))),
          if (p.role == 'mechanic') ...[
            const SizedBox(height: 12),
            TextField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                    labelText: 'عنوان الورشة',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)))),
            const SizedBox(height: 8),
            Text(
                'ساعات الدوام: ${p.openingHours} · السعة: ${p.maxCarCapacity} سيارة/يوم',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 22),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
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
