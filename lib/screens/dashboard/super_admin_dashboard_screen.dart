import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/status_labels.dart';
import '../../widgets/animations.dart';
import '../mobile/mobile_shell.dart';
import 'admin_ad_settings_view.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onSignedOut;
  final int initialTab;

  const SuperAdminDashboardScreen({
    super.key,
    required this.profile,
    required this.onSignedOut,
    this.initialTab = 0,
  });

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _db = Supabase.instance.client;
  late int _tab = widget.initialTab;
  String _roleFilter = 'all';
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;

  final _kmPriceCtrl = TextEditingController(text: '1.5');
  final _minWithdrawCtrl = TextEditingController(text: '1.0');
  final _cliqAliasCtrl = TextEditingController(text: 'AUTOPARTSJO');
  final _defaultCommCtrl = TextEditingController(text: '0.15');
  final _defaultMaxPostsCtrl = TextEditingController(text: '5');
  bool _postLimitsEnabled = true;
  bool _maintenance = false;
  bool _saving = false;

  // متحكمات الخصومات
  final _discTitleCtrl = TextEditingController();
  final _discCodeCtrl = TextEditingController();
  final _discPercentCtrl = TextEditingController(text: '10');
  final _discDaysCtrl = TextEditingController(text: '7');
  String _discTargetMode = 'role'; // 'role' | 'users' | 'new_users'
  String _discTargetRole = 'all';
  String _discTargetCategory = 'الكل';
  Set<String> _discSelectedUserIds = {};
  String _discNewUsersPreset = 'today'; // 'today' | '3d' | '7d' | 'custom'
  DateTimeRange? _discNewUsersCustomRange;
  bool _creatingDiscount = false;

  // متحكمات الإشعارات
  final _notifTitleCtrl = TextEditingController();
  final _notifBodyCtrl = TextEditingController();
  String _notifTargetMode = 'role'; // 'role' | 'users' | 'new_users'
  String _notifTargetRole = 'all';
  Set<String> _notifSelectedUserIds = {};
  String _notifNewUsersPreset = 'today'; // 'today' | '3d' | '7d' | 'custom'
  DateTimeRange? _notifNewUsersCustomRange;
  bool _sendingNotif = false;

  List<Map<String, dynamic>> _cachedUsers = [];
  List<Map<String, dynamic>> _discountsList = [];
  bool _loadingDiscounts = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUsersList();
    _loadDiscounts();
  }

  @override
  void dispose() {
    _kmPriceCtrl.dispose();
    _minWithdrawCtrl.dispose();
    _cliqAliasCtrl.dispose();
    _defaultCommCtrl.dispose();
    _defaultMaxPostsCtrl.dispose();
    _discTitleCtrl.dispose();
    _discCodeCtrl.dispose();
    _discPercentCtrl.dispose();
    _discDaysCtrl.dispose();
    _notifTitleCtrl.dispose();
    _notifBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsersList() async {
    try {
      final rows = await _db
          .from('customers')
          .select('id, full_name, username, phone, email, role, created_at')
          .order('created_at', ascending: false)
          .limit(500);
      if (mounted) {
        setState(() => _cachedUsers = List<Map<String, dynamic>>.from(rows));
      }
    } catch (_) {}
  }

  Future<void> _loadDiscounts() async {
    if (mounted) setState(() => _loadingDiscounts = true);
    try {
      final rows = await _db
          .from('discounts')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _discountsList = List<Map<String, dynamic>>.from(rows);
          _loadingDiscounts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDiscounts = false);
    }
  }

  List<Map<String, dynamic>> _filterNewUsers(
    String preset,
    DateTimeRange? customRange,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    late final DateTime start;
    late final DateTime end;

    switch (preset) {
      case 'today':
        start = todayStart;
        end = now.add(const Duration(minutes: 1));
        break;
      case '3d':
        start = todayStart.subtract(const Duration(days: 2));
        end = now.add(const Duration(minutes: 1));
        break;
      case '7d':
        start = todayStart.subtract(const Duration(days: 6));
        end = now.add(const Duration(minutes: 1));
        break;
      case 'custom':
        if (customRange == null) return [];
        start = DateTime(
          customRange.start.year,
          customRange.start.month,
          customRange.start.day,
        );
        end = DateTime(
          customRange.end.year,
          customRange.end.month,
          customRange.end.day,
          23,
          59,
          59,
        );
        break;
      default:
        start = todayStart;
        end = now.add(const Duration(minutes: 1));
    }

    return _cachedUsers.where((u) {
      final dt = DateTime.tryParse((u['created_at'] as String?) ?? '')?.toLocal();
      if (dt == null) return false;
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList();
  }

  String _formatShortDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _userDisplayById(String? uid) {
    if (uid == null || uid.isEmpty) return 'مستخدم محدد';
    final match = _cachedUsers.where((u) => u['id'] == uid);
    if (match.isEmpty) return 'مستخدم محدد';
    final u = match.first;
    final name = (u['full_name'] as String?)?.trim();
    final uname = (u['username'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return uname != null && uname.isNotEmpty ? '$name (@$uname)' : name;
    }
    return uname != null && uname.isNotEmpty ? '@$uname' : 'مستخدم محدد';
  }

  Future<Set<String>?> _openMultiUserPickerDialog({
    required Set<String> initialSelected,
    required String title,
    required bool showWinch,
  }) async {
    if (_cachedUsers.isEmpty) {
      await _loadUsersList();
    }
    if (!mounted) return null;

    final selected = Set<String>.from(initialSelected);
    String query = '';

    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final q = query.trim().toLowerCase();
          final visibleUsers = _cachedUsers.where((u) {
            if (!showWinch && u['role'] == 'towing') return false;
            if (q.isEmpty) return true;
            final name = (u['full_name'] as String? ?? '').toLowerCase();
            final uname = (u['username'] as String? ?? '').toLowerCase();
            final phone = (u['phone'] as String? ?? '').toLowerCase();
            final email = (u['email'] as String? ?? '').toLowerCase();
            return name.contains(q) ||
                uname.contains(q) ||
                phone.contains(q) ||
                email.contains(q);
          }).toList();

          return AlertDialog(
            title: Text(
              '$title (${selected.length} محدد)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 460,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم، اليوزرنيم، الهاتف أو الإيميل...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (v) => setD(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setD(() {
                          for (final u in visibleUsers) {
                            final id = u['id'] as String?;
                            if (id != null) selected.add(id);
                          }
                        }),
                        icon: const Icon(Icons.select_all, size: 17),
                        label: const Text('تحديد الكل الظاهر',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setD(selected.clear),
                        icon: const Icon(Icons.clear_all,
                            size: 17, color: Colors.red),
                        label: const Text('مسح التحديد',
                            style:
                                TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                  const Divider(height: 8),
                  Expanded(
                    child: visibleUsers.isEmpty
                        ? const Center(
                            child: Text('لا توجد حسابات مطابقة للبحث'),
                          )
                        : ListView.builder(
                            itemCount: visibleUsers.length,
                            itemBuilder: (_, i) {
                              final u = visibleUsers[i];
                              final id = u['id'] as String? ?? '';
                              final checked = selected.contains(id);
                              final roleStr =
                                  (u['role'] as String?) ?? 'user';
                              final roleLabel = (!showWinch &&
                                      roleStr == 'towing')
                                  ? 'مقدم خدمة'
                                  : StatusLabels.role(roleStr);
                              return CheckboxListTile(
                                dense: true,
                                value: checked,
                                activeColor: AppColors.orange,
                                title: Text(
                                  '${u['full_name'] ?? "بدون اسم"} (@${u['username'] ?? "-"})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  '${u['phone'] ?? "-"} · $roleLabel',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                onChanged: (v) => setD(() {
                                  if (v == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
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
                onPressed: () => Navigator.pop(ctx, selected),
                child: Text('تأكيد (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendNotificationToUserIds({
    required List<String> userIds,
    required String title,
    required String body,
    required String type,
  }) async {
    for (final uid in userIds) {
      await NotificationsService.instance.sendBroadcastNotification(
        title: title,
        body: body,
        targetRole: 'all',
        targetUserId: uid,
        type: type,
      );
    }
  }

  bool _inPeriod(String? createdAt) {
    final dt = DateTime.tryParse(createdAt ?? '');
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  void _goHome({bool closeDrawerFirst = false}) {
    if (closeDrawerFirst && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        animatedRoute(
          LiveMobileShell(
            profile: widget.profile,
            onRefreshProfile: widget.onSignedOut,
            onSignedOut: widget.onSignedOut,
          ),
        ),
      );
    }
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await _db.from('system_settings').select();
      final map = {
        for (final r in rows) r['key'] as String: r['value'] as String
      };
      if (!mounted) return;
      setState(() {
        _kmPriceCtrl.text = map['winch_price_per_km'] ?? '1.5';
        _minWithdrawCtrl.text = map['min_withdrawal_amount'] ?? '1.0';
        _cliqAliasCtrl.text = map['cliq_alias'] ?? 'AUTOPARTSJO';
        _defaultCommCtrl.text = map['default_parts_commission'] ?? '0.15';
        _defaultMaxPostsCtrl.text = map['default_max_posts'] ?? '5';
        _postLimitsEnabled = map['enable_post_limits'] != 'false';
        _maintenance = map['maintenance_mode'] == 'true';
        if (map['enable_payments'] != null) {
          EnvConfig.paymentsEnabled.value = map['enable_payments'] == 'true';
        }
        if (map['enable_winch'] != null) {
          EnvConfig.winchEnabled.value = map['enable_winch'] == 'true';
        }
        if (map['enable_ads'] != null) {
          EnvConfig.adsEnabled.value = map['enable_ads'] == 'true';
        }
      });
    } catch (_) {}
  }

  Future<void> _updateSingleSetting(String key, String value) async {
    try {
      await _db.from('system_settings').upsert({'key': key, 'value': value});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final newDefaultLimit =
          int.tryParse(_defaultMaxPostsCtrl.text.trim()) ?? 5;
      final kmRate = double.tryParse(_kmPriceCtrl.text.trim()) ?? 1.5;
      final updates = [
        {'key': 'winch_price_per_km', 'value': kmRate.toString()},
        {'key': 'min_withdrawal_amount', 'value': _minWithdrawCtrl.text.trim()},
        {'key': 'cliq_alias', 'value': _cliqAliasCtrl.text.trim()},
        {
          'key': 'default_parts_commission',
          'value': _defaultCommCtrl.text.trim()
        },
        {'key': 'enable_post_limits', 'value': _postLimitsEnabled.toString()},
        {'key': 'default_max_posts', 'value': '$newDefaultLimit'},
        {'key': 'maintenance_mode', 'value': _maintenance.toString()},
        {
          'key': 'enable_payments',
          'value': EnvConfig.paymentsEnabled.value.toString()
        },
        {
          'key': 'enable_winch',
          'value': EnvConfig.winchEnabled.value.toString()
        },
        {'key': 'enable_ads', 'value': EnvConfig.adsEnabled.value.toString()},
      ];
      await _db.from('system_settings').upsert(updates);
      await _db.from('customers').update(
          {'max_posts_limit': newDefaultLimit}).eq('subscription_plan', 'free');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ جميع إعدادات السوبر أدمن وتطبيقها! ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ أثناء الحفظ: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EnvConfig.paymentsEnabled,
        EnvConfig.winchEnabled,
        EnvConfig.adsEnabled,
      ]),
      builder: (context, _) {
        final showPayments = EnvConfig.paymentsEnabled.value;
        final showWinch = EnvConfig.winchEnabled.value;
        final showAds = EnvConfig.adsEnabled.value;
        final isWide = MediaQuery.of(context).size.width >= 850;
        final menu = <({int id, IconData icon, String title})>[
          (id: 0, icon: Icons.dashboard, title: 'نظرة عامة شاملة'),
          (id: 1, icon: Icons.campaign, title: 'إعلان الصفحة الرئيسية'),
          (id: 2, icon: Icons.people, title: 'الحسابات والتجار والورش'),
          (id: 3, icon: Icons.tune, title: 'إعدادات النظام والتحكم'),
          (id: 4, icon: Icons.inventory_2, title: 'جميع منشورات القطع'),
          (id: 5, icon: Icons.car_crash, title: 'مراقبة الطوارئ والمواعيد'),
          (id: 7, icon: Icons.local_offer, title: 'الخصومات والإشعارات'),
          if (showPayments)
            (id: 6, icon: Icons.account_balance, title: 'الاشتراكات والمالية'),
          (id: 8, icon: Icons.flag_outlined, title: 'بلاغات المستخدمين'),
        ];
        if (!showPayments && _tab == 6) {
          _tab = 0;
        }
        final currentTitle = menu
            .firstWhere((m) => m.id == _tab, orElse: () => menu.first)
            .title;

        return Scaffold(
          appBar: isWide
              ? null
              : AppBar(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  iconTheme: const IconThemeData(color: Colors.white),
                  actionsIconTheme: const IconThemeData(color: Colors.white),
                  leading: Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  title: Text(currentTitle,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                  actions: [
                    IconButton(
                      tooltip: 'العودة للرئيسية',
                      icon: const Icon(Icons.grid_view_rounded,
                          color: Colors.white),
                      onPressed: _goHome,
                    ),
                    IconButton(
                      tooltip: 'تسجيل الخروج',
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: () async {
                        await _db.auth.signOut();
                        if (context.mounted) {
                          Navigator.popUntil(context, (r) => r.isFirst);
                        }
                        widget.onSignedOut();
                      },
                    ),
                  ],
                ),
          drawer: isWide ? null : Drawer(child: _sidebar(menu, true)),
          body: Row(
            children: [
              if (isWide) SizedBox(width: 255, child: _sidebar(menu, false)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: KeyedSubtree(
                    key: ValueKey(
                        'tab_${_tab}_${showPayments}_${showWinch}_$showAds'),
                    child: switch (_tab) {
                      1 => const AdminAdSettingsView(),
                      2 => _accountsControlView(showPayments, showWinch),
                      3 => _settingsView(showPayments, showWinch, showAds),
                      4 => _allProductsControlView(),
                      5 => _operationsMonitorView(showWinch),
                      6 => _financeAndSubscriptionsView(showWinch),
                      7 => _discountsAndNotificationsView(showWinch),
                      8 => _reportsModerationView(),
                      _ => _overviewView(showPayments, showWinch, isWide),
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sidebar(
      List<({int id, IconData icon, String title})> menu, bool isDrawer) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  GhiyarakLogo(size: 32),
                  SizedBox(width: 8),
                  Text(
                    'لوحة غيارك',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                onPressed: () async {
                  await _db.auth.signOut();
                  if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
                  widget.onSignedOut();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.grid_view_rounded, color: Colors.white),
            title: const Text('العودة للرئيسية (الاختصارات)',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            onTap: () => _goHome(closeDrawerFirst: isDrawer),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: menu.length,
              itemBuilder: (_, i) {
                final item = menu[i];
                final active = _tab == item.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    tileColor: active ? AppColors.orange : Colors.transparent,
                    leading: Icon(item.icon,
                        color: active ? Colors.white : Colors.white70,
                        size: 20),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () {
                      setState(() => _tab = item.id);
                      if (item.id == 7) {
                        _loadDiscounts();
                        _loadUsersList();
                      }
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewView(bool showPayments, bool showWinch, bool isWide) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('products').stream(primaryKey: ['id']).limit(150),
      builder: (_, prodSnap) => StreamBuilder<List<Map<String, dynamic>>>(
        stream:
            _db.from('mechanic_requests').stream(primaryKey: ['id']).limit(150),
        builder: (_, reqSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('workshop_appointments')
              .stream(primaryKey: ['id']).limit(150),
          builder: (_, apptSnap) => StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db
                .from('wallet_transactions')
                .stream(primaryKey: ['id']).limit(150),
            builder: (_, txSnap) => FutureBuilder<List<Map<String, dynamic>>>(
              future: _db
                  .from('customers')
                  .select('id, role, created_at')
                  .limit(300),
              builder: (_, userSnap) {
                final users = (userSnap.data ?? [])
                    .where((u) => _inPeriod(u['created_at'] as String?))
                    .toList();
                final prods = (prodSnap.data ?? [])
                    .where((p) => _inPeriod(p['created_at'] as String?))
                    .toList();
                final reqs = (reqSnap.data ?? [])
                    .where((r) =>
                        (showWinch || r['service_type'] != 'winch') &&
                        _inPeriod(r['created_at'] as String?))
                    .toList();
                final appts = (apptSnap.data ?? [])
                    .where((a) => _inPeriod(a['created_at'] as String?))
                    .toList();
                final txs = (txSnap.data ?? [])
                    .where((t) => _inPeriod(t['created_at'] as String?))
                    .map(DbWalletTransaction.fromMap)
                    .toList();

                final totalViews = prods.fold<int>(
                    0, (s, p) => s + ((p['views_count'] as int?) ?? 0));
                final totalClicks = prods.fold<int>(
                    0, (s, p) => s + ((p['clicks_count'] as int?) ?? 0));
                final workshopsCount =
                    users.where((u) => u['role'] == 'mechanic').length;
                final merchantsCount =
                    users.where((u) => u['role'] == 'merchant').length;
                final totalGross = txs.fold(0.0, (s, t) => s + t.grossAmount);
                final totalComm =
                    txs.fold(0.0, (s, t) => s + t.commissionAmount);

                final cards = [
                  (
                    title: 'إجمالي الحسابات',
                    val: users.length,
                    icon: Icons.people
                  ),
                  (
                    title: 'الورش والميكانيكيين',
                    val: workshopsCount,
                    icon: Icons.build
                  ),
                  (
                    title: 'تجار قطع الغيار',
                    val: merchantsCount,
                    icon: Icons.storefront
                  ),
                  (
                    title: 'منشورات القطع',
                    val: prods.length,
                    icon: Icons.inventory_2
                  ),
                  (
                    title: 'إجمالي المشاهدات',
                    val: totalViews,
                    icon: Icons.visibility
                  ),
                  (
                    title: 'إجمالي النقرات',
                    val: totalClicks,
                    icon: Icons.touch_app
                  ),
                  (
                    title: 'طلبات الطوارئ',
                    val: reqs.length,
                    icon: Icons.car_crash
                  ),
                  (
                    title: 'مواعيد الورش',
                    val: appts.length,
                    icon: Icons.event_available
                  ),
                  if (showPayments) ...[
                    (
                      title: 'إجمالي المبيعات (د.أ)',
                      val: totalGross.toInt(),
                      icon: Icons.payments
                    ),
                    (
                      title: 'عمولات المنصة (د.أ)',
                      val: totalComm.toInt(),
                      icon: Icons.trending_up
                    ),
                  ],
                ];

                final chartData = [
                  (label: 'حسابات', value: users.length.toDouble()),
                  (label: 'ورش', value: workshopsCount.toDouble()),
                  (label: 'تجار', value: merchantsCount.toDouble()),
                  (label: 'منشورات', value: prods.length.toDouble()),
                  (label: 'طوارئ', value: reqs.length.toDouble()),
                  (label: 'مواعيد', value: appts.length.toDouble()),
                ];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('الرؤية الشاملة للمنصة',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DateRangeFilterBar(
                      period: _period,
                      customRange: _customRange,
                      onChanged: (p, r) => setState(() {
                        _period = p;
                        _customRange = r;
                      }),
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cards.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isWide ? 4 : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: isWide ? 1.45 : 1.15,
                      ),
                      itemBuilder: (_, i) => FadeSlideIn(
                        index: i,
                        child:
                            _kpi(cards[i].title, cards[i].val, cards[i].icon),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InteractiveAnimatedChart(
                        title: 'تحليل نشاط المنصة التفاعلي', data: chartData),
                    if (showPayments) ...[
                      const SizedBox(height: 16),
                      InteractiveAnimatedChart(
                        title: 'التحليل المالي للمنصة (د.أ)',
                        unit: 'د.أ',
                        data: [
                          (label: 'المبيعات', value: totalGross),
                          (label: 'العمولات', value: totalComm),
                          (
                            label: 'صافي المزودين',
                            value: (totalGross - totalComm).clamp(0, totalGross)
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountsControlView(bool showPayments, bool showWinch) {
    if (!showWinch && _roleFilter == 'towing') {
      _roleFilter = 'all';
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db
          .from('customers')
          .select()
          .order('created_at', ascending: false)
          .limit(150),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allUsers = snap.data!;
        final filtered = allUsers.where((u) {
          if (!showWinch && u['role'] == 'towing') return false;
          if (_roleFilter == 'all') return true;
          return u['role'] == _roleFilter;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('التحكم الكامل بالحسابات والمنشورات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterPill('الكل', 'all'),
                  _filterPill('مستخدمين', 'user'),
                  _filterPill('تجار', 'merchant'),
                  _filterPill('ورش / ميكانيكي', 'mechanic'),
                  if (showWinch) _filterPill('أصحاب ونش', 'towing'),
                  _filterPill('أدمن', 'admin'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...filtered.map((raw) {
              final m = CustomerProfile.fromMap(raw);
              final postsUsed = (raw['free_posts_count'] as int?) ?? 0;
              final postsLimit = (raw['max_posts_limit'] as int?) ?? 5;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${m.fullName ?? "بدون اسم"} (@${m.username ?? "-"})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          if (m.isTrustedMerchant)
                            const Icon(Icons.verified,
                                color: Colors.blue, size: 20),
                          const SizedBox(width: 6),
                          Chip(
                            label: Text(
                              (!showWinch && m.role == 'towing' && !m.isAdmin)
                                  ? 'مقدم خدمة'
                                  : StatusLabels.role(
                                      m.isAdmin ? 'admin' : m.role),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'الإيميل: ${m.email ?? "-"} | الهاتف: ${m.phone ?? "-"}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المنشورات المستخدمة: $postsUsed / الحد الأقصى: $postsLimit منشور · الباقة: ${m.subscriptionPlan}',
                        style: const TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                      const Divider(),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('تاجر موثوق:',
                                  style: TextStyle(fontSize: 12)),
                              Switch(
                                value: m.isTrustedMerchant,
                                activeTrackColor: AppColors.orange,
                                onChanged: (val) async {
                                  await _db
                                      .from('customers')
                                      .update({'is_trusted_merchant': val}).eq(
                                          'id', m.id);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _editAccountDialog(
                                raw, showPayments, showWinch),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('تعديل الدور والباقة والحد'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.orange),
                            onPressed: () {
                              setState(() {
                                _discTargetMode = 'users';
                                _discSelectedUserIds = {m.id};
                                _tab = 7;
                              });
                              _loadDiscounts();
                            },
                            icon: const Icon(Icons.local_offer_outlined,
                                size: 16),
                            label: const Text('إعطاء خصم خاص'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _filterPill(String label, String key) {
    final active = _roleFilter == key;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        selectedColor: AppColors.navy,
        labelStyle:
            TextStyle(color: active ? Colors.white : AppColors.textPrimary),
        onSelected: (_) => setState(() => _roleFilter = key),
      ),
    );
  }

  Future<void> _editAccountDialog(
      Map<String, dynamic> raw, bool showPayments, bool showWinch) async {
    String role = (raw['role'] as String?) ?? 'user';
    if (!showWinch && role == 'towing') role = 'user';
    String plan = (raw['subscription_plan'] as String?) ?? 'free';
    final limitCtrl =
        TextEditingController(text: '${raw['max_posts_limit'] ?? 5}');
    final commCtrl =
        TextEditingController(text: '${raw['commission_rate'] ?? 0.15}');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('تعديل حساب: ${raw['full_name'] ?? ""}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: [
                    const DropdownMenuItem(
                        value: 'user', child: Text('مستخدم عادي')),
                    const DropdownMenuItem(
                        value: 'merchant', child: Text('تاجر قطع غيار')),
                    const DropdownMenuItem(
                        value: 'mechanic', child: Text('ميكانيكي / ورشة')),
                    if (showWinch)
                      const DropdownMenuItem(
                          value: 'towing', child: Text('صاحب ونش')),
                    const DropdownMenuItem(
                        value: 'admin', child: Text('مدير نظام')),
                  ],
                  onChanged: (v) {
                    if (v != null) setD(() => role = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: [
                    'free',
                    'provider_3m',
                    'provider_6m',
                    'provider_12m',
                    'customer_pro'
                  ].contains(plan)
                      ? plan
                      : 'free',
                  decoration:
                      const InputDecoration(labelText: 'الباقة / الاشتراك'),
                  items: const [
                    DropdownMenuItem(
                        value: 'free', child: Text('مجاني (free)')),
                    DropdownMenuItem(
                        value: 'provider_3m',
                        child: Text('مزود 3 شهور (SEO +1)')),
                    DropdownMenuItem(
                        value: 'provider_6m',
                        child: Text('مزود 6 شهور (SEO +2)')),
                    DropdownMenuItem(
                        value: 'provider_12m',
                        child: Text('مزود سنوي 0% عمولة (SEO +3)')),
                    DropdownMenuItem(
                        value: 'customer_pro', child: Text('مستخدم برو (Pro)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setD(() => plan = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: limitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'عدد المنشورات المسموح لهذا الحساب'),
                ),
                if (showPayments) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: commCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'نسبة العمولة (مثال: 0.10 = 10%)'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final expiresAt = plan == 'free'
                    ? null
                    : DateTime.now()
                        .add(Duration(
                          days: plan == 'provider_12m'
                              ? 365
                              : plan == 'provider_6m'
                                  ? 180
                                  : 90,
                        ))
                        .toUtc()
                        .toIso8601String();
                await _db.from('customers').update({
                  'role': role,
                  'is_admin': role == 'admin',
                  'subscription_plan': plan,
                  'subscription_expires_at': expiresAt,
                  'max_posts_limit': int.tryParse(limitCtrl.text) ?? 5,
                  if (showPayments)
                    'commission_rate': double.tryParse(commCtrl.text) ?? 0.15,
                }).eq('id', raw['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تحديث الحساب بنجاح ✓'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        ),
      ),
    );
    limitCtrl.dispose();
    commCtrl.dispose();
  }

  Widget _settingsView(bool showPayments, bool showWinch, bool showAds) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('إعدادات السوبر أدمن والتحكم العام',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            title: const Text('تفعيل قيود عدد المنشورات',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                'عند التفعيل يلتزم التجار والورش بعدد المنشورات المحدد، وعند الإيقاف يكون النشر مفتوحاً'),
            value: _postLimitsEnabled,
            activeTrackColor: AppColors.orange,
            onChanged: (v) async {
              setState(() => _postLimitsEnabled = v);
              await _updateSingleSetting('enable_post_limits', v.toString());
            },
          ),
        ),
        if (_postLimitsEnabled) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _defaultMaxPostsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'عدد البوستات المسموح للحسابات المجانية (الافتراضي 5)',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            title: const Text('تفعيل خدمات الونش والسحب',
                style: TextStyle(fontWeight: FontWeight.bold)),
            value: showWinch,
            activeTrackColor: AppColors.orange,
            onChanged: (v) async {
              EnvConfig.winchEnabled.value = v;
              await _updateSingleSetting('enable_winch', v.toString());
            },
          ),
        ),
        if (showWinch) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _kmPriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText:
                  'تسعيرة الونش لكل كيلومتر (د.أ) — مطبّقة 100% على الطلبات',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.local_shipping, color: AppColors.orange),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            title: const Text('تفعيل المعاملات المالية والدفع والاشتراكات',
                style: TextStyle(fontWeight: FontWeight.bold)),
            value: showPayments,
            activeTrackColor: AppColors.orange,
            onChanged: (v) async {
              EnvConfig.paymentsEnabled.value = v;
              await _updateSingleSetting('enable_payments', v.toString());
            },
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            title: const Text('تفعيل إعلان Google AdMob المنظّم (المتجر)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                'يظهر بانر إعلاني واحد مرتب ومخصص للسيارات والمال داخل المتجر'),
            value: showAds,
            activeTrackColor: AppColors.orange,
            onChanged: (v) async {
              EnvConfig.adsEnabled.value = v;
              await _updateSingleSetting('enable_ads', v.toString());
            },
          ),
        ),
        if (showPayments) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _defaultCommCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'نسبة العمولة الافتراضية (0.15 = 15%)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cliqAliasCtrl,
            decoration: const InputDecoration(
              labelText: 'حساب CliQ الرسمي لتسديد الاشتراكات والعمولات',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('وضع الصيانة (إغلاق مؤقت للمستخدمين)'),
          value: _maintenance,
          activeTrackColor: Colors.red,
          onChanged: (v) => setState(() => _maintenance = v),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: _saving ? null : _saveSettings,
          child: _saving
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('حفظ جميع الإعدادات',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _allProductsControlView() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('products')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(150),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final prods = snap.data!
            .where((p) => _inPeriod(p['created_at'] as String?))
            .toList();
        if (prods.isEmpty) {
          return const Center(child: Text('لا توجد منشورات ضمن هذه الفترة'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: prods.length,
          itemBuilder: (_, i) {
            final p = prods[i];
            final isHidden = p['is_hidden'] == true;
            final discount = (p['discount_percent'] as int?) ?? 0;
            final imgs = List<String>.from(p['images'] ?? []);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: isHidden ? Colors.grey.shade100 : Colors.white,
              child: ListTile(
                leading: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.placeholder,
                    borderRadius: BorderRadius.circular(10),
                    image: imgs.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(imgs.first), fit: BoxFit.cover)
                        : null,
                  ),
                  child: imgs.isEmpty ? const Icon(Icons.settings) : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (p['title'] as String?) ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isHidden)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'مخفي',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (discount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-$discount%',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  '${p['car_name']} (${p['car_model']}) · ${p['price']} د.أ · ${p['main_category'] ?? ""} · مشاهدات: ${p['views_count'] ?? 0}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: isHidden ? 'إظهار المنشور' : 'إخفاء المنشور',
                      icon: Icon(
                        isHidden ? Icons.visibility_off : Icons.visibility,
                        color: isHidden ? Colors.deepOrange : AppColors.success,
                      ),
                      onPressed: () async {
                        try {
                          final updated = await _db
                              .from('products')
                              .update({'is_hidden': !isHidden})
                              .eq('id', p['id'])
                              .select('id, is_hidden');
                          if (updated.isEmpty) {
                            throw Exception(
                                'تحقق من صلاحيات الأدمن في قاعدة البيانات (SQL الدفعة 1)');
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  !isHidden
                                      ? 'تم إخفاء المنشور ✓'
                                      : 'تم إظهار المنشور ✓',
                                ),
                                backgroundColor: !isHidden
                                    ? AppColors.navy
                                    : AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('فشل التحديث: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'حذف المنشور',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('حذف المنشور'),
                            content:
                                Text('هل تريد حذف "${p['title']}" نهائياً؟'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('إلغاء')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        try {
                          await _db.from('products').delete().eq('id', p['id']);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم حذف المنشور ✓'),
                                backgroundColor: AppColors.navy,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('تعذر الحذف: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateEmergencyStatus(String id, String nextStatus) async {
    try {
      final nextStep = switch (nextStatus) {
        'accepted' => 'on_the_way',
        'completed' => 'completed',
        'cancelled' => 'cancelled',
        _ => 'pending',
      };
      final updated = await _db
          .from('mechanic_requests')
          .update({'status': nextStatus, 'progress_step': nextStep})
          .eq('id', id)
          .select('id, status');
      if (updated.isEmpty) {
        throw Exception('لم يتم تعديل السجل — تأكد من تنفيذ SQL الدفعة 1');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث الطلب إلى: ${StatusLabels.emergency(nextStatus, progressStep: nextStep)} ✓',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تغيير الحالة: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateAppointmentStatus(String id, String nextStatus) async {
    try {
      final nextStep = switch (nextStatus) {
        'accepted' => 'on_the_way',
        'completed' => 'completed',
        'cancelled' => 'cancelled',
        _ => 'pending',
      };
      final updated = await _db
          .from('workshop_appointments')
          .update({'status': nextStatus, 'progress_step': nextStep})
          .eq('id', id)
          .select('id, status');
      if (updated.isEmpty) {
        throw Exception('لم يتم تعديل الموعد — تأكد من تنفيذ SQL الدفعة 1');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم تحديث الموعد إلى: ${StatusLabels.appointment(nextStatus, progressStep: nextStep)} ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تغيير الحالة: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _operationsMonitorView(bool showWinch) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('مراقبة طلبات الطوارئ ومواعيد الورش (مباشر)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        DateRangeFilterBar(
          period: _period,
          customRange: _customRange,
          onChanged: (p, r) => setState(() {
            _period = p;
            _customRange = r;
          }),
        ),
        const SizedBox(height: 14),
        const Text('طلبات الطوارئ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('mechanic_requests')
              .stream(primaryKey: ['id'])
              .order('created_at', ascending: false)
              .limit(100),
          builder: (_, snap) {
            final reqs = (snap.data ?? [])
                .where((r) =>
                    (showWinch || r['service_type'] != 'winch') &&
                    _inPeriod(r['created_at'] as String?))
                .toList();
            if (reqs.isEmpty) {
              return const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد طلبات طوارئ')),
              );
            }
            return Column(
              children: reqs.map((r) {
                final arabicStatus = StatusLabels.emergency(
                  r['status'] as String?,
                  progressStep: r['progress_step'] as String?,
                );
                final isWinch = r['service_type'] == 'winch';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      '${(isWinch && showWinch) ? "طلب ونش" : "ميكانيكي طوارئ"} · ${r['car_details'] ?? ""}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المشكلة: ${r['description'] ?? "-"}'),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            arabicStatus,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'تغيير حالة الطلب',
                      icon: const Icon(Icons.more_vert, color: AppColors.navy),
                      onSelected: (val) =>
                          _updateEmergencyStatus(r['id'] as String, val),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'pending', child: Text('بانتظار مزود')),
                        PopupMenuItem(
                            value: 'accepted', child: Text('في الطريق')),
                        PopupMenuItem(value: 'completed', child: Text('مكتمل')),
                        PopupMenuItem(value: 'cancelled', child: Text('ملغي')),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('مواعيد الورش',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('workshop_appointments')
              .stream(primaryKey: ['id'])
              .order('created_at', ascending: false)
              .limit(100),
          builder: (_, snap) {
            final appts = (snap.data ?? [])
                .where((a) => _inPeriod(a['created_at'] as String?))
                .toList();
            if (appts.isEmpty) {
              return const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد مواعيد ورش')),
              );
            }
            return Column(
              children: appts.map((a) {
                final arabicStatus = StatusLabels.appointment(
                  a['status'] as String?,
                  progressStep: a['progress_step'] as String?,
                );
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      '${a['appointment_date']} · ${a['appointment_time']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((a['service_description'] as String?) ?? ''),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            arabicStatus,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'تغيير حالة الموعد',
                      icon: const Icon(Icons.more_vert, color: AppColors.navy),
                      onSelected: (val) =>
                          _updateAppointmentStatus(a['id'] as String, val),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'pending',
                            child: Text('بانتظار موافقة الورشة')),
                        PopupMenuItem(
                            value: 'accepted',
                            child: Text('مقبول / في الطريق')),
                        PopupMenuItem(value: 'completed', child: Text('مكتمل')),
                        PopupMenuItem(value: 'cancelled', child: Text('ملغي')),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _toggleDiscountActive(
      Map<String, dynamic> d, bool nextVal) async {
    final id = d['id'];
    final prevVal = d['is_active'] == true;
    setState(() {
      final idx = _discountsList.indexWhere((x) => x['id'] == id);
      if (idx != -1) {
        _discountsList[idx] = {..._discountsList[idx], 'is_active': nextVal};
      }
    });
    try {
      final updated = await _db
          .from('discounts')
          .update({'is_active': nextVal})
          .eq('id', id)
          .select('id');
      if (updated.isEmpty) {
        throw Exception(
          'تم حظر التعديل بواسطة صلاحيات قاعدة البيانات (شغّل كود SQL صلاحيات جدول discounts)',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(nextVal ? 'تم تفعيل الخصم ✓' : 'تم إيقاف تفعيل الخصم ✓'),
            backgroundColor: nextVal ? AppColors.success : AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _discountsList.indexWhere((x) => x['id'] == id);
          if (idx != -1) {
            _discountsList[idx] = {
              ..._discountsList[idx],
              'is_active': prevVal
            };
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تحديث حالة الخصم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteDiscount(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخصم'),
        content: Text('هل تريد حذف الخصم "${d['title']}" (${d['code']}) نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final deleted = await _db
          .from('discounts')
          .delete()
          .eq('id', d['id'])
          .select('id');
      if (deleted.isEmpty) {
        throw Exception(
          'تم حظر الحذف بواسطة صلاحيات قاعدة البيانات (شغّل كود SQL صلاحيات جدول discounts)',
        );
      }
      if (mounted) {
        setState(() {
          _discountsList.removeWhere((x) => x['id'] == d['id']);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الخصم بنجاح ✓'),
            backgroundColor: AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حذف الخصم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createAdminDiscount() async {
    FocusScope.of(context).unfocus();
    final title = _discTitleCtrl.text.trim();
    final code = _discCodeCtrl.text.trim().toUpperCase();
    final percent = int.tryParse(_discPercentCtrl.text.trim()) ?? 0;
    final days = int.tryParse(_discDaysCtrl.text.trim()) ?? 7;

    if (title.isEmpty || code.isEmpty || percent <= 0 || percent > 90) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل عنوان الخصم، الكود، ونسبة صحيحة بين 1% و 90%'),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }

    List<String> targetUserIds = [];
    if (_discTargetMode == 'users') {
      if (_discSelectedUserIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى تحديد حساب واحد على الأقل لإرسال الخصم'),
            backgroundColor: AppColors.orange,
          ),
        );
        return;
      }
      targetUserIds = _discSelectedUserIds.toList();
    } else if (_discTargetMode == 'new_users') {
      if (_discNewUsersPreset == 'custom' && _discNewUsersCustomRange == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى تحديد الفترة المخصصة (Custom) أولاً'),
            backgroundColor: AppColors.orange,
          ),
        );
        return;
      }
      final matched =
          _filterNewUsers(_discNewUsersPreset, _discNewUsersCustomRange);
      if (matched.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد مستخدمين جدد مسجلين ضمن الفترة المختارة'),
            backgroundColor: AppColors.orange,
          ),
        );
        return;
      }
      targetUserIds = matched.map((u) => u['id'] as String).toList();
    }

    setState(() => _creatingDiscount = true);
    try {
      final expiresAt =
          DateTime.now().add(Duration(days: days)).toUtc().toIso8601String();
      final notifBody =
          'احصل على خصم $percent% على ${_discTargetCategory == "الكل" ? "جميع القطع" : _discTargetCategory} — كود الخصم: $code';

      if (_discTargetMode == 'role') {
        await _db.from('discounts').insert({
          'title': title,
          'code': code,
          'discount_percent': percent,
          'target_role': _discTargetRole,
          'target_category': _discTargetCategory,
          'target_user_id': null,
          'is_active': true,
          'expires_at': expiresAt,
        });
        await NotificationsService.instance.sendBroadcastNotification(
          title: '🎁 $title',
          body: notifBody,
          targetRole: _discTargetRole,
          targetUserId: null,
          type: 'discount',
        );
      } else {
        final rowsToInsert = targetUserIds
            .map((uid) => {
                  'title': title,
                  'code': code,
                  'discount_percent': percent,
                  'target_role': 'specific_user',
                  'target_category': _discTargetCategory,
                  'target_user_id': uid,
                  'is_active': true,
                  'expires_at': expiresAt,
                })
            .toList();
        await _db.from('discounts').insert(rowsToInsert);
        await _sendNotificationToUserIds(
          userIds: targetUserIds,
          title: '🎁 $title',
          body: notifBody,
          type: 'discount',
        );
      }

      _discTitleCtrl.clear();
      _discCodeCtrl.clear();
      await _loadDiscounts();
      if (mounted) {
        final msg = _discTargetMode == 'role'
            ? 'تم إنشاء الخصم وإرسال الإشعار للفئة المختارة ✓'
            : 'تم إنشاء الخصم وإرساله إلى ${targetUserIds.length} حساب بنجاح ✓';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final hint = e.code == '23505'
            ? 'كود الخصم مكرر بسبب قيد UNIQUE على عمود code في جدول discounts — نفّذ في Supabase:\nALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS discounts_code_key;'
            : 'تعذر إنشاء الخصم: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hint),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر إنشاء الخصم: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingDiscount = false);
    }
  }

  Future<void> _sendAdminBroadcast() async {
    FocusScope.of(context).unfocus();
    final title = _notifTitleCtrl.text.trim();
    final body = _notifBodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان ونص الإشعار')),
      );
      return;
    }

    List<String> targetUserIds = [];
    if (_notifTargetMode == 'users') {
      if (_notifSelectedUserIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يرجى تحديد حساب واحد على الأقل لإرسال الإشعار')),
        );
        return;
      }
      targetUserIds = _notifSelectedUserIds.toList();
    } else if (_notifTargetMode == 'new_users') {
      if (_notifNewUsersPreset == 'custom' &&
          _notifNewUsersCustomRange == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يرجى تحديد الفترة المخصصة (Custom) أولاً')),
        );
        return;
      }
      final matched =
          _filterNewUsers(_notifNewUsersPreset, _notifNewUsersCustomRange);
      if (matched.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا يوجد مستخدمين جدد مسجلين ضمن الفترة المختارة')),
        );
        return;
      }
      targetUserIds = matched.map((u) => u['id'] as String).toList();
    }

    setState(() => _sendingNotif = true);
    try {
      if (_notifTargetMode == 'role') {
        await NotificationsService.instance.sendBroadcastNotification(
          title: title,
          body: body,
          targetRole: _notifTargetRole,
          targetUserId: null,
          type: 'announcement',
        );
      } else {
        await _sendNotificationToUserIds(
          userIds: targetUserIds,
          title: title,
          body: body,
          type: 'announcement',
        );
      }
      _notifTitleCtrl.clear();
      _notifBodyCtrl.clear();
      if (mounted) {
        final msg = _notifTargetMode == 'role'
            ? 'تم إرسال الإشعار بنجاح ✓'
            : 'تم إرسال الإشعار إلى ${targetUserIds.length} حساب بنجاح ✓';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل الإرسال: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingNotif = false);
    }
  }

  Widget _buildNewUsersRangeSelector({
    required String preset,
    required DateTimeRange? customRange,
    required ValueChanged<String> onPresetChanged,
    required ValueChanged<DateTimeRange> onCustomRangePicked,
  }) {
    final matched = _filterNewUsers(preset, customRange);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختر فترة تسجيل المستخدمين الجدد:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('سجلوا اليوم'),
                selected: preset == 'today',
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                  color: preset == 'today'
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontSize: 12,
                ),
                onSelected: (_) => onPresetChanged('today'),
              ),
              ChoiceChip(
                label: const Text('آخر 3 أيام'),
                selected: preset == '3d',
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                  color: preset == '3d' ? Colors.white : AppColors.textPrimary,
                  fontSize: 12,
                ),
                onSelected: (_) => onPresetChanged('3d'),
              ),
              ChoiceChip(
                label: const Text('آخر أسبوع'),
                selected: preset == '7d',
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                  color: preset == '7d' ? Colors.white : AppColors.textPrimary,
                  fontSize: 12,
                ),
                onSelected: (_) => onPresetChanged('7d'),
              ),
              ChoiceChip(
                label: const Text('Custom (تاريخ مخصص)'),
                selected: preset == 'custom',
                selectedColor: AppColors.orange,
                labelStyle: TextStyle(
                  color: preset == 'custom'
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontSize: 12,
                ),
                onSelected: (_) async {
                  onPresetChanged('custom');
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: customRange ??
                        DateTimeRange(
                          start:
                              DateTime.now().subtract(const Duration(days: 7)),
                          end: DateTime.now(),
                        ),
                  );
                  if (picked != null) {
                    onCustomRangePicked(picked);
                  }
                },
              ),
            ],
          ),
          if (preset == 'custom') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.date_range,
                    size: 16, color: AppColors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    customRange == null
                        ? 'لم يتم تحديد تاريخ بعد'
                        : 'من ${_formatShortDate(customRange.start)} إلى ${_formatShortDate(customRange.end)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDateRange: customRange ??
                          DateTimeRange(
                            start: DateTime.now()
                                .subtract(const Duration(days: 7)),
                            end: DateTime.now(),
                          ),
                    );
                    if (picked != null) {
                      onCustomRangePicked(picked);
                    }
                  },
                  child: const Text('تغيير التاريخ'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: matched.isNotEmpty
                  ? AppColors.success.withValues(alpha: 0.12)
                  : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'عدد الحسابات المطابقة: ${matched.length} حساب',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: matched.isNotEmpty ? AppColors.success : AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiUsersPickerBox({
    required Set<String> selectedIds,
    required String buttonLabel,
    required VoidCallback onOpenPicker,
    required ValueChanged<String> onRemoveId,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenPicker,
              icon: const Icon(Icons.checklist_rtl, color: AppColors.orange),
              label: Text(
                selectedIds.isEmpty
                    ? buttonLabel
                    : '$buttonLabel (تم تحديد ${selectedIds.length} حساب)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (selectedIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selectedIds
                  .take(8)
                  .map(
                    (uid) => InputChip(
                      label: Text(
                        _userDisplayById(uid),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onDeleted: () => onRemoveId(uid),
                    ),
                  )
                  .toList(),
            ),
            if (selectedIds.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${selectedIds.length - 8} حسابات أخرى محددة',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _discountsAndNotificationsView(bool showWinch) {
    if (!showWinch && _discTargetRole == 'towing') {
      _discTargetRole = 'all';
    }
    if (!showWinch && _notifTargetRole == 'towing') {
      _notifTargetRole = 'all';
    }
    final cats = ['الكل', ...CarPartsCatalogAZ.mainCategories];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('إدارة الخصومات والعروض والإشعارات',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'الخصم المُنشأ هنا يُطبَّق تلقائياً على بطاقات القطع ضمن الصنف المختار ويمكن استخدام الكود عند الدفع.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إنشاء خصم جديد',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'role',
                      label: Text('فئة', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.groups, size: 17),
                    ),
                    ButtonSegment(
                      value: 'users',
                      label:
                          Text('حسابات محددة', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.person_search, size: 17),
                    ),
                    ButtonSegment(
                      value: 'new_users',
                      label: Text('الجدد', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.fiber_new, size: 17),
                    ),
                  ],
                  selected: {_discTargetMode},
                  onSelectionChanged: (s) =>
                      setState(() => _discTargetMode = s.first),
                ),
                const SizedBox(height: 12),
                if (_discTargetMode == 'role')
                  DropdownButtonFormField<String>(
                    initialValue: _discTargetRole,
                    decoration: const InputDecoration(
                      labelText: 'الفئة المستهدفة',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('جميع المستخدمين')),
                      const DropdownMenuItem(
                          value: 'user', child: Text('المستخدمين العاديين')),
                      const DropdownMenuItem(
                          value: 'merchant', child: Text('تجار القطع')),
                      const DropdownMenuItem(
                          value: 'mechanic',
                          child: Text('الميكانيكيين والورش')),
                      if (showWinch)
                        const DropdownMenuItem(
                            value: 'towing', child: Text('أصحاب الونشات')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _discTargetRole = v);
                    },
                  )
                else if (_discTargetMode == 'users')
                  _buildMultiUsersPickerBox(
                    selectedIds: _discSelectedUserIds,
                    buttonLabel: 'تحديد الحسابات المستهدفة للخصم',
                    onOpenPicker: () async {
                      final picked = await _openMultiUserPickerDialog(
                        initialSelected: _discSelectedUserIds,
                        title: 'اختر الحسابات للخصم',
                        showWinch: showWinch,
                      );
                      if (picked != null && mounted) {
                        setState(() => _discSelectedUserIds = picked);
                      }
                    },
                    onRemoveId: (uid) =>
                        setState(() => _discSelectedUserIds.remove(uid)),
                  )
                else
                  _buildNewUsersRangeSelector(
                    preset: _discNewUsersPreset,
                    customRange: _discNewUsersCustomRange,
                    onPresetChanged: (p) =>
                        setState(() => _discNewUsersPreset = p),
                    onCustomRangePicked: (r) =>
                        setState(() => _discNewUsersCustomRange = r),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: cats.contains(_discTargetCategory)
                      ? _discTargetCategory
                      : 'الكل',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText:
                        'الصنف المشمول بالخصم (يُطبَّق مباشرة على بطاقات القطع)',
                    border: OutlineInputBorder(),
                  ),
                  items: cats
                      .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _discTargetCategory = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _discTitleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'عنوان العرض (مثال: خصم نهاية الأسبوع)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _discCodeCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'كود الخصم (مثال: GHYAR15)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _discPercentCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'النسبة %',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _discDaysCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'أيام',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _creatingDiscount ? null : _createAdminDiscount,
                    icon: const Icon(Icons.local_offer),
                    label: Text(
                      _creatingDiscount
                          ? 'جاري النشر...'
                          : 'إنشاء الخصم وإشعار المستهدفين',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text('الخصومات الحالية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            IconButton(
              tooltip: 'تحديث الخصومات',
              onPressed: _loadDiscounts,
              icon: const Icon(Icons.refresh, color: AppColors.navy),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loadingDiscounts)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_discountsList.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد خصومات مسجلة'),
            ),
          )
        else
          ..._discountsList.map((d) {
            final active = d['is_active'] == true;
            final targetUid = d['target_user_id'] as String?;
            final targetRoleStr = (d['target_role'] as String?) ?? 'all';
            final targetLabel = targetUid != null
                ? 'حساب خاص: ${_userDisplayById(targetUid)}'
                : (targetRoleStr == 'all'
                    ? 'الجميع'
                    : (!showWinch && targetRoleStr == 'towing'
                        ? 'مقدمي خدمات'
                        : StatusLabels.role(targetRoleStr)));
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  '${d['title']} (${d['discount_percent']}%) — كود: ${d['code']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: Text(
                  'الصنف: ${d['target_category'] ?? "الكل"} · المستهدف: $targetLabel',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: active,
                      activeTrackColor: AppColors.orange,
                      onChanged: (v) => _toggleDiscountActive(d, v),
                    ),
                    IconButton(
                      tooltip: 'حذف الخصم',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteDiscount(d),
                    ),
                  ],
                ),
              ),
            );
          }),
        const Divider(height: 30),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إرسال إشعار مباشر',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'role',
                      label: Text('فئة', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.groups, size: 17),
                    ),
                    ButtonSegment(
                      value: 'users',
                      label:
                          Text('حسابات محددة', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.person_search, size: 17),
                    ),
                    ButtonSegment(
                      value: 'new_users',
                      label: Text('الجدد', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.fiber_new, size: 17),
                    ),
                  ],
                  selected: {_notifTargetMode},
                  onSelectionChanged: (s) =>
                      setState(() => _notifTargetMode = s.first),
                ),
                const SizedBox(height: 10),
                if (_notifTargetMode == 'role')
                  DropdownButtonFormField<String>(
                    initialValue: _notifTargetRole,
                    decoration: const InputDecoration(
                        labelText: 'الفئة', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('الجميع')),
                      const DropdownMenuItem(
                          value: 'user', child: Text('المستخدمين')),
                      const DropdownMenuItem(
                          value: 'merchant', child: Text('التجار')),
                      const DropdownMenuItem(
                          value: 'mechanic', child: Text('الورش')),
                      if (showWinch)
                        const DropdownMenuItem(
                            value: 'towing', child: Text('أصحاب الونشات')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _notifTargetRole = v);
                    },
                  )
                else if (_notifTargetMode == 'users')
                  _buildMultiUsersPickerBox(
                    selectedIds: _notifSelectedUserIds,
                    buttonLabel: 'تحديد الحسابات المستهدفة للإشعار',
                    onOpenPicker: () async {
                      final picked = await _openMultiUserPickerDialog(
                        initialSelected: _notifSelectedUserIds,
                        title: 'اختر الحسابات للإشعار',
                        showWinch: showWinch,
                      );
                      if (picked != null && mounted) {
                        setState(() => _notifSelectedUserIds = picked);
                      }
                    },
                    onRemoveId: (uid) =>
                        setState(() => _notifSelectedUserIds.remove(uid)),
                  )
                else
                  _buildNewUsersRangeSelector(
                    preset: _notifNewUsersPreset,
                    customRange: _notifNewUsersCustomRange,
                    onPresetChanged: (p) =>
                        setState(() => _notifNewUsersPreset = p),
                    onCustomRangePicked: (r) =>
                        setState(() => _notifNewUsersCustomRange = r),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notifTitleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الإشعار',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notifBodyCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'نص الإشعار',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _sendingNotif ? null : _sendAdminBroadcast,
                    icon: const Icon(Icons.send),
                    label: Text(_sendingNotif
                        ? 'جاري الإرسال...'
                        : 'إرسال الإشعار الآن'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _financeAndSubscriptionsView(bool showWinch) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('الاشتراكات والمعاملات المالية (ملخص مبسّط)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'آلية الربح المبسطة: 1) اشتراكات الباقات (تجار/ورش/مستخدمين) تُفعّل فور الدفع عبر PayTabs/MEPS أو CliQ.\n'
            '2) عمولة المنصة تُحتسب تلقائياً على المبيعات والخدمات داخل التطبيق ويمكن للتاجر تسديدها من محفظته.',
            style: TextStyle(fontSize: 12, color: AppColors.navy, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        DateRangeFilterBar(
          period: _period,
          customRange: _customRange,
          onChanged: (p, r) => setState(() {
            _period = p;
            _customRange = r;
          }),
        ),
        const SizedBox(height: 14),
        // قسم العمولات المستحقة والاشتراكات النشطة
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _db
              .from('customers')
              .select(
                  'id, full_name, username, role, subscription_plan, pending_commission_debt')
              .order('pending_commission_debt', ascending: false)
              .limit(100),
          builder: (_, custSnap) {
            final custs = custSnap.data ?? [];
            final debtors = custs
                .where((c) => ((c['pending_commission_debt'] as num?) ?? 0) > 0)
                .toList();
            final paidSubs = custs
                .where((c) =>
                    (c['subscription_plan'] as String? ?? 'free') != 'free')
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _kpi('المشتركين بالباقات', paidSubs.length,
                          Icons.workspace_premium),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpi('حسابات عليها عمولة', debtors.length,
                          Icons.receipt_long),
                    ),
                  ],
                ),
                if (debtors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('عمولات مستحقة على التجار والورش',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  ...debtors.map((d) {
                    final debt = ((d['pending_commission_debt'] as num?) ?? 0)
                        .toDouble();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          '${d['full_name'] ?? ""} (@${d['username'] ?? "-"})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'مستحق للدفع: ${debt.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            await _db
                                .from('customers')
                                .update({'pending_commission_debt': 0}).eq(
                                    'id', d['id']);
                            if (mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'تم تأكيد استلام العمولة وتصفير الرصيد ✓'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          },
                          child: const Text('تأكيد السداد'),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('wallet_transactions')
              .stream(primaryKey: ['id'])
              .order('created_at', ascending: false)
              .limit(100),
          builder: (_, snap) {
            final txs = (snap.data ?? [])
                .where((t) => _inPeriod(t['created_at'] as String?))
                .map(DbWalletTransaction.fromMap)
                .toList();

            final totalGross = txs.fold(0.0, (s, t) => s + t.grossAmount);
            final totalComm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
            final totalNet = txs.fold(0.0, (s, t) => s + t.netAmount);
            final partsTotal = txs
                .where((t) =>
                    t.transactionType.contains('part') ||
                    t.transactionType == 'order')
                .fold(0.0, (s, t) => s + t.grossAmount);
            final servicesTotal =
                (totalGross - partsTotal).clamp(0.0, totalGross);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _kpi('إجمالي المبيعات (د.أ)', totalGross.toInt(),
                            Icons.payments)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _kpi('ربح المنصة (د.أ)', totalComm.toInt(),
                            Icons.trending_up)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _kpi('صافي المزودين (د.أ)', totalNet.toInt(),
                            Icons.account_balance_wallet)),
                  ],
                ),
                const SizedBox(height: 14),
                InteractiveAnimatedChart(
                  title: 'الحركة المالية والعمولات (د.أ)',
                  unit: 'د.أ',
                  data: [
                    (label: 'المبيعات', value: totalGross),
                    (label: 'ربح المنصة', value: totalComm),
                    (label: 'للمزودين', value: totalNet),
                    (label: 'القطع', value: partsTotal),
                    (
                      label: showWinch ? 'الورش/ونش' : 'الورش/طوارئ',
                      value: servicesTotal,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('سجل الحركات المالية',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                if (txs.isEmpty)
                  const Card(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد حركات مالية')),
                  )
                else
                  ...txs.map((t) => Card(
                        child: ListTile(
                          title: Text(
                              '${_txArabicType(t.transactionType)} · ${t.paymentMethod}'),
                          subtitle: Text(
                            'الإجمالي: ${t.grossAmount.toStringAsFixed(2)} د.أ | عمولة المنصة: ${t.commissionAmount.toStringAsFixed(2)} | صافي المزود: ${t.netAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _reportsModerationView() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db
          .from('content_reports')
          .select()
          .order('created_at', ascending: false)
          .limit(100),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reports = snap.data!;
        if (reports.isEmpty) {
          return const Center(
              child: Text('لا توجد بلاغات من المستخدمين حالياً'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (_, i) {
            final r = reports[i];
            final status = (r['status'] as String?) ?? 'pending';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  Icons.flag,
                  color: status == 'resolved' ? AppColors.success : Colors.red,
                ),
                title: Text(
                  'بلاغ عن ${r['target_type'] == 'product' ? 'منشور قطعة' : 'حساب'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                    'السبب: ${r['reason'] ?? "-"}\nالحالة الإدارية: ${status == 'resolved' ? 'تمت المعالجة' : 'قيد المراجعة'}'),
                trailing: status == 'resolved'
                    ? const Icon(Icons.check_circle, color: AppColors.success)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          await _db
                              .from('content_reports')
                              .update({'status': 'resolved'}).eq('id', r['id']);
                          if (mounted) setState(() {});
                        },
                        child: const Text('تمت المعالجة'),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  String _txArabicType(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => 'طلب قطعة غيار',
        'workshop' || 'workshop_invoice' || 'appointment' => 'فاتورة ورشة صيانة',
        'emergency_mechanic' => 'ميكانيكي طوارئ',
        'winch_towing' || 'winch' || 'emergency' => EnvConfig.winchEnabled.value
            ? 'طلب ونش / طوارئ'
            : 'طلب طوارئ',
        'sub' || 'subscription' => 'اشتراك باقة',
        'debt' => 'تسديد عمولات',
        _ => raw,
      };

  Widget _kpi(String title, int val, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PulseBlink(child: Icon(icon, color: AppColors.orange, size: 22)),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          AnimatedCounter(
            value: val,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}