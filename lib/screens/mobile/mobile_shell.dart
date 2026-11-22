import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/notifications_service.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/status_labels.dart';
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
import 'role_shortcuts_home_screen.dart';

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
  final _db = Supabase.instance.client;
  int _index = 0;

  @override
  void didUpdateWidget(covariant LiveMobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // عند تسجيل الدخول أو تسجيل الخروج نعيد المؤشر بأمان للبداية
    final wasLoggedIn = oldWidget.profile != null;
    final isLoggedIn = widget.profile != null;
    if (wasLoggedIn != isLoggedIn) {
      _index = 0;
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

  void _openSupportScreen() =>
      Navigator.push(context, animatedRoute(const SupportScreen()));

  void _openWalletScreen() {
    if (widget.profile == null) return;
    Navigator.push(
      context,
      animatedRoute(
        Scaffold(
          appBar: AppBar(title: const Text('محفظة التاجر والعمولات')),
          body: _merchantWalletTab(),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmCtrl = TextEditingController();
    bool deleting = false;
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('حذف الحساب نهائياً',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تحذير: حذف الحساب إجراء نهائي لا يمكن التراجع عنه، وسيتم إزالة ملفك الشخصي ومنشوراتك وبياناتك الشخصية من التطبيق.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
              const Text(
                'للتأكيد، اكتب كلمة (حذف) في الحقل أدناه:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'اكتب: حذف',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: deleting ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: deleting
                  ? null
                  : () async {
                      if (confirmCtrl.text.trim() != 'حذف') {
                        setD(() => errorMsg =
                            'يرجى كتابة كلمة (حذف) بشكل صحيح للتأكيد.');
                        return;
                      }
                      setD(() {
                        deleting = true;
                        errorMsg = null;
                      });
                      try {
                        await _db.rpc('delete_my_account');
                        await _db.auth.signOut();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم حذف حسابك بنجاح.'),
                              backgroundColor: AppColors.navy,
                            ),
                          );
                        }
                        widget.onSignedOut();
                      } catch (e) {
                        setD(() {
                          deleting = false;
                          errorMsg = 'تعذر حذف الحساب حالياً: $e';
                        });
                      }
                    },
              child: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('تأكيد الحذف النهائي'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
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
        builder: (ctx, setD) {
          Future<void> submit() async {
            if (newPassCtrl.text.length < 6) {
              setD(() => alertMsg =
                  'كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل.');
              return;
            }
            if (newPassCtrl.text != confirmPassCtrl.text) {
              setD(() =>
                  alertMsg = 'كلمة المرور الجديدة وتأكيدها غير متطابقتين.');
              return;
            }
            setD(() {
              saving = true;
              alertMsg = null;
            });
            try {
              final email =
                  widget.profile?.email ?? _db.auth.currentUser?.email;
              if (email == null) {
                throw Exception('البريد غير متوفر');
              }
              await _db.auth.signInWithPassword(
                  email: email, password: currentPassCtrl.text);
              await _db.auth
                  .updateUser(UserAttributes(password: newPassCtrl.text));
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
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
                alertMsg = 'تنبيه أمني: كلمة المرور الحالية غير صحيحة!';
              });
            }
          }

          return AlertDialog(
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
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                TextField(
                  controller: currentPassCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور الحالية'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!saving) submit();
                  },
                  decoration: const InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة'),
                ),
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
                onPressed: saving ? null : submit,
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
          );
        },
      ),
    );
    currentPassCtrl.dispose();
    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.profile?.role ?? 'user';
    final isMerchant = role == 'merchant';
    final isProvider = isMerchant || role == 'mechanic' || role == 'towing';
    final isLoggedIn = widget.profile != null;

    // للمستخدم المسجل: الشاشة 0 هي صفحة الاختصارات حسب الرول، والشاشة 1 هي المتجر
    // للزائر: يبدأ مباشرة بمتجر القطع (Apple Guideline 5.1.1v)
    final pages = isLoggedIn
        ? [
            RoleShortcutsHomeScreen(
              profile: widget.profile!,
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              onSelectTab: (tabIdx) => setState(() => _index = tabIdx),
              onOpenWallet: _openWalletScreen,
              onOpenSupport: _openSupportScreen,
              onRefreshProfile: widget.onRefreshProfile,
              onSignedOut: widget.onSignedOut,
            ),
            LiveStoreHomeScreen(
              profile: widget.profile,
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            EmergencyScreen(profile: widget.profile!),
            CustomerAppointmentsScreen(
              customerProfile: widget.profile!,
              onRefreshProfile: widget.onRefreshProfile,
            ),
            _profileTab(isProvider),
          ]
        : [
            LiveStoreHomeScreen(
              profile: widget.profile,
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            _loginRequiredView('لطلب مساعدة طارئة يرجى تسجيل الدخول'),
            _loginRequiredView('لعرض وحجز مواعيد الورشة يرجى تسجيل الدخول'),
            _profileTab(false),
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
                key: ValueKey('${isLoggedIn}_$safeIndex'),
                child: pages[safeIndex]),
          ),

          // زر العودة السريع للاختصارات عند التواجد في شاشة فرعية (مثل المتجر أو الطوارئ)
          if (isLoggedIn && safeIndex != 0)
            Positioned(
              right: 14,
              bottom: 16,
              child: BounceTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _index = 0);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                        color: AppColors.navy.withValues(alpha: 0.25)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_view_rounded,
                          color: AppColors.navy, size: 18),
                      SizedBox(width: 5),
                      Text(
                        'الاختصارات',
                        style: TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // زر الـ AI العائم في الزاوية السفلية
          Positioned(
            left: 14,
            bottom: 16,
            child: BounceTap(
              onTap: () =>
                  showAiDiagnosticSheet(context, viewerProfile: widget.profile),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navy, Color(0xFF1F2D3D)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.orange, width: 1.4),
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
                    Icon(Icons.auto_awesome, color: AppColors.orange, size: 19),
                    SizedBox(width: 6),
                    Text(
                      'فحص AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isProvider && !isLoggedIn
          ? null
          : (isProvider
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
              : null),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: isProvider ? const CircularNotchedRectangle() : null,
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: isLoggedIn
              ? [
                  _navItem(0, Icons.grid_view_rounded, 'الرئيسية', safeIndex),
                  _navItem(1, Icons.storefront_outlined, 'المتجر', safeIndex),
                  if (isProvider) const SizedBox(width: 38),
                  _navItem(2, Icons.car_crash_outlined, 'طوارئ', safeIndex),
                  _navItem(3, Icons.event_note_outlined, 'المواعيد', safeIndex),
                  _navItem(4, Icons.person_outline, 'حسابي', safeIndex),
                ]
              : [
                  _navItem(0, Icons.storefront_outlined, 'المتجر', safeIndex),
                  _navItem(1, Icons.car_crash_outlined, 'طوارئ', safeIndex),
                  _navItem(2, Icons.event_note_outlined, 'المواعيد', safeIndex),
                  _navItem(3, Icons.person_outline, 'حسابي', safeIndex),
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
                          fontWeight: FontWeight.w900),
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
                      StatusLabels.role(isAdmin ? 'admin' : role),
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
          if (isLoggedIn)
            ListTile(
              leading:
                  const Icon(Icons.grid_view_rounded, color: AppColors.navy),
              title: const Text('الرئيسية (الاختصارات)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 0);
              },
            ),
          if (hasDashboard) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                tileColor: AppColors.orangeLight,
                leading: const Icon(Icons.dashboard, color: AppColors.orange),
                title: const Text('لوحة التحكم',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.orange)),
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
            leading: const Icon(Icons.storefront, color: AppColors.orange),
            title: const Text('متجر قطع الغيار'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = isLoggedIn ? 1 : 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.car_crash_outlined),
            title: const Text('طلب مساعدة طارئة'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = isLoggedIn ? 2 : 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('مواعيد الورشة'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = isLoggedIn ? 3 : 2);
            },
          ),
          if (role == 'merchant' || role == 'mechanic') ...[
            const Divider(),
            if (showPayments && role == 'merchant')
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.navy),
                title: const Text('محفظة التاجر والأرباح'),
                onTap: () {
                  Navigator.pop(context);
                  _openWalletScreen();
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
              },
            ),
          ],
          if (isLoggedIn) ...[
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.chat_bubble_outline, color: AppColors.navy),
              title: const Text('الدردشات'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, animatedRoute(const ChatsListScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('الإشعارات'),
              onTap: () {
                Navigator.pop(context);
                NotificationsService.instance.openNotificationsSheet(context);
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading:
                const Icon(Icons.privacy_tip_outlined, color: AppColors.navy),
            title: const Text('الشروط وسياسة الخصوصية'),
            onTap: () {
              Navigator.pop(context);
              showTermsAndPrivacySheet(context);
            },
          ),
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
                        LoginScreen(onAuthenticated: widget.onRefreshProfile)));
              },
            ),
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
              },
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                Navigator.pop(context);
                await _db.auth.signOut();
                widget.onSignedOut();
              },
            ),
        ],
      ),
    );
  }

  String _roleDashboardSubtitle(String role) => switch (role) {
        'admin' => 'إدارة النظام والإعلانات والتجار والمالية',
        'mechanic' => 'الورشة وطلبات الطوارئ وقطع الغيار',
        'towing' => 'طلبات الونش المباشرة',
        'merchant' => 'إدارة المنتجات والخصومات والإخفاء',
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
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15)),
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

  Widget _navItem(int idx, IconData icon, String label, int currentIndex) {
    final active = currentIndex == idx;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _index = idx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                  borderRadius: BorderRadius.circular(4)),
            ),
            AnimatedScale(
              scale: active ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(icon,
                  color: active ? AppColors.orange : AppColors.textSecondary,
                  size: 21),
            ),
            Text(
              label,
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

  Widget _merchantWalletTab() {
    final p = widget.profile!;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('wallet_transactions')
          .stream(primaryKey: ['id'])
          .eq('provider_id', p.id)
          .order('created_at', ascending: false)
          .limit(50),
      builder: (_, snap) {
        final txs = (snap.data ?? []).map(DbWalletTransaction.fromMap).toList();
        final gross = txs.fold(0.0, (s, t) => s + t.grossAmount);
        final comm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
        final net = txs.fold(0.0, (s, t) => s + t.netAmount);
        final pendingDebt = p.pendingCommissionDebt;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صافي محفظة التاجر (بعد العمولة)',
                      style: TextStyle(color: Colors.white70)),
                  Text(
                    '${net.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'إجمالي المبيعات: ${gross.toStringAsFixed(2)} د.أ  |  عمولة المنصة: ${comm.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (pendingDebt > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet,
                            color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'عمولات مستحقة للدفع: ${pendingDebt.toStringAsFixed(2)} د.أ',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'يمكنك تسديد العمولات المستحقة إلكترونياً مباشرة من داخل التطبيق لتفادي تقييد الحساب.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.payment),
                        label: const Text('تسديد العمولة الآن عبر التطبيق'),
                        onPressed: () async {
                          final ok =
                              await PayTabsPaymentService().startPaymentFlow(
                            context: context,
                            baseAmount: pendingDebt,
                            title: 'تسديد عمولات مستحقة — غيارك',
                            orderType: 'debt',
                            referenceId: p.id,
                            email: p.email,
                            phone: p.phone,
                            name: p.fullName,
                          );
                          if (ok && mounted) {
                            widget.onRefreshProfile();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('تم استلام طلب تسديد العمولة بنجاح'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text('آخر الحركات المالية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (txs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('لا توجد حركات مالية مسجلة حتى الآن',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ...txs.map(
              (t) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.orangeLight,
                    child: Icon(Icons.receipt_long,
                        color: AppColors.orange, size: 20),
                  ),
                  title: Text(
                    _txTypeArabic(t.transactionType),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} · عمولة: -${t.commissionAmount.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '+${t.netAmount.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _txTypeArabic(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => 'بيع قطعة غيار',
        'workshop' || 'appointment' => 'خدمة ورشة',
        'emergency' || 'winch' => 'طلب طوارئ / ونش',
        'subscription' || 'sub' => 'اشتراك باقة',
        _ => raw,
      };

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
                leading: const Icon(Icons.privacy_tip_outlined,
                    color: AppColors.navy),
                title: const Text('الشروط والأحكام وسياسة الخصوصية'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => showTermsAndPrivacySheet(context),
              ),
            ),
            const SizedBox(height: 10),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.navy,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(widget.profile!.fullName ?? 'المستخدم',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  '@${widget.profile!.username ?? ""} · ${widget.profile!.phone ?? ""}'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.badge_outlined, color: AppColors.orange),
              title: const Text('البروفايل (معلوماتي الشخصية)'),
              subtitle: const Text('عرض وتعديل الاسم، الهاتف، ومعلومات النشاط'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(
                context,
                animatedRoute(UserProfileScreen(
                    profile: widget.profile!,
                    onSaved: widget.onRefreshProfile)),
              ),
            ),
          ),
          if (showPayments) ...[
            const SizedBox(height: 10),
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
                            currentPlanCode: widget.profile!.subscriptionPlan,
                            onSubscribed: widget.onRefreshProfile,
                          )
                        : CustomerSubscriptionsScreen(
                            currentPlanCode: widget.profile!.subscriptionPlan,
                            onSubscribed: widget.onRefreshProfile,
                          ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset, color: AppColors.navy),
              title: const Text('تغيير كلمة المرور'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showChangePasswordDialog,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.privacy_tip_outlined, color: AppColors.navy),
              title: const Text('الشروط والأحكام وسياسة الخصوصية'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => showTermsAndPrivacySheet(context),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent, color: AppColors.orange),
              title: const Text('الدعم الفني والمساعدة'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _openSupportScreen,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                await _db.auth.signOut();
                widget.onSignedOut();
              },
            ),
          ),
          const SizedBox(height: 10),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
            ),
            child: ListTile(
              leading:
                  const Icon(Icons.delete_forever_outlined, color: Colors.red),
              title: const Text('حذف الحساب نهائياً',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text('إزالة الحساب والبيانات الشخصية بالكامل',
                  style: TextStyle(fontSize: 12)),
              onTap: _showDeleteAccountDialog,
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
            child: const Column(
              children: [
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
              onTap: () =>
                  launchUrl(Uri.parse('tel:${EnvConfig.supportPhone}')),
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
              onTap: () => launchUrl(Uri.parse(
                  'mailto:${EnvConfig.supportEmail}?subject=دعم فني تطبيق غيارك')),
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
    FocusScope.of(context).unfocus();
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
          SnackBar(
              content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red),
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
    final isMechanic = p.role == 'mechanic';
    return Scaffold(
      appBar: AppBar(title: const Text('ملفي الشخصي (البروفايل)')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName ?? 'المستخدم',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('اسم المستخدم: @${p.username ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('البريد الإلكتروني: ${p.email ?? "-"}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Text(
                  'نوع الحساب: ${StatusLabels.role(p.isAdmin ? "admin" : p.role)}',
                  style: const TextStyle(
                      color: AppColors.orange, fontWeight: FontWeight.bold),
                ),
                if (_country != null || _age != null)
                  Text(
                    'الدولة: ${_country ?? "-"}  |  العمر: ${_age ?? "-"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
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
            textInputAction:
                isMechanic ? TextInputAction.next : TextInputAction.done,
            onSubmitted: (_) {
              if (!isMechanic && !_saving) _saveProfile();
            },
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              filled: true,
              fillColor: AppColors.surface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (isMechanic) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _saveProfile();
              },
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
