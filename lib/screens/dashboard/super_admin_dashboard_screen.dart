import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
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
  final _minWithdrawCtrl = TextEditingController(text: '20.0');
  final _cliqAliasCtrl = TextEditingController(text: 'AUTOPARTSJO');
  final _defaultCommCtrl = TextEditingController(text: '0.15');
  final _defaultMaxPostsCtrl = TextEditingController(text: '5');
  bool _postLimitsEnabled = true;
  bool _maintenance = false;
  bool _saving = false;

  // متحكمات الخصومات وإرسال الإشعارات
  final _notifTitleCtrl = TextEditingController();
  final _notifBodyCtrl = TextEditingController();
  String _notifTargetRole = 'all';
  bool _sendingNotif = false;

  final _discTitleCtrl = TextEditingController();
  final _discCodeCtrl = TextEditingController();
  final _discPercentCtrl = TextEditingController(text: '10');
  final _discDescCtrl = TextEditingController();
  String _discTargetRole = 'all';
  String _discTargetCategory = 'الكل';
  bool _notifyOnDiscount = true;
  bool _savingDiscount = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _kmPriceCtrl.dispose();
    _minWithdrawCtrl.dispose();
    _cliqAliasCtrl.dispose();
    _defaultCommCtrl.dispose();
    _defaultMaxPostsCtrl.dispose();
    _notifTitleCtrl.dispose();
    _notifBodyCtrl.dispose();
    _discTitleCtrl.dispose();
    _discCodeCtrl.dispose();
    _discPercentCtrl.dispose();
    _discDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _callPhone(String? rawPhone) async {
    final cleaned = (rawPhone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رقم الهاتف غير متوفر')),
        );
      }
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: cleaned), mode: LaunchMode.externalApplication);
  }

  bool _inPeriod(String? createdAt) {
    final dt = DateTime.tryParse(createdAt ?? '');
    if (dt == null) {
      return true;
    }
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
        animatedRoute(LiveMobileShell(
          profile: widget.profile,
          onRefreshProfile: widget.onSignedOut,
          onSignedOut: widget.onSignedOut,
        )),
      );
    }
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await _db.from('system_settings').select();
      final map = {
        for (final r in rows) r['key'] as String: r['value'] as String
      };
      if (!mounted) {
        return;
      }
      setState(() {
        _kmPriceCtrl.text = map['winch_price_per_km'] ?? '1.5';
        _minWithdrawCtrl.text = map['min_withdrawal_amount'] ?? '20.0';
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
    setState(() => _saving = true);
    try {
      final newDefaultLimit =
          int.tryParse(_defaultMaxPostsCtrl.text.trim()) ?? 5;
      final updates = [
        {'key': 'winch_price_per_km', 'value': _kmPriceCtrl.text.trim()},
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
      ];
      await _db.from('system_settings').upsert(updates);
      await _db.from('customers').update(
          {'max_posts_limit': newDefaultLimit}).eq('subscription_plan', 'free');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ جميع إعدادات السوبر أدمن وتطبيقها!'),
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
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<int> _broadcastNotification({
    required String title,
    required String body,
    required String targetRole,
    String type = 'promo',
  }) async {
    final rows = await _db.from('customers').select('id, role, subscription_plan');
    final targetIds = <String>[];
    for (final r in rows) {
      final id = r['id'] as String?;
      if (id == null) continue;
      final role = (r['role'] as String?) ?? 'user';
      final plan = (r['subscription_plan'] as String?) ?? 'free';
      final match = switch (targetRole) {
        'all' => true,
        'pro' => plan != 'free',
        _ => role == targetRole,
      };
      if (match) {
        targetIds.add(id);
      }
    }
    if (targetIds.isEmpty) return 0;

    final payload = targetIds
        .map((uid) => {
              'user_id': uid,
              'title': title,
              'body': body,
              'type': type,
              'is_read': false,
            })
        .toList();

    // إدراج على دفعات لحماية الأداء عند عدد مستخدمين كبير
    for (var i = 0; i < payload.length; i += 100) {
      final end = (i + 100 > payload.length) ? payload.length : i + 100;
      await _db.from('notifications').insert(payload.sublist(i, end));
    }
    return targetIds.length;
  }

  Future<void> _sendPromoNotification() async {
    final title = _notifTitleCtrl.text.trim();
    final body = _notifBodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال عنوان ونص الإشعار')),
      );
      return;
    }
    setState(() => _sendingNotif = true);
    try {
      final count = await _broadcastNotification(
        title: title,
        body: body,
        targetRole: _notifTargetRole,
        type: 'promo',
      );
      if (mounted) {
        _notifTitleCtrl.clear();
        _notifBodyCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال الإشعار بنجاح إلى $count مستخدم!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الإرسال: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingNotif = false);
    }
  }

  Future<void> _createDiscount() async {
    final title = _discTitleCtrl.text.trim();
    final code = _discCodeCtrl.text.trim().toUpperCase();
    final percent = double.tryParse(_discPercentCtrl.text.trim()) ?? 0;

    if (title.isEmpty || code.isEmpty || percent <= 0 || percent > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال عنوان الخصم والكود ونسبة صحيحة (1 إلى 100)')),
      );
      return;
    }

    setState(() => _savingDiscount = true);
    try {
      await _db.from('discounts').insert({
        'title': title,
        'code': code,
        'description': _discDescCtrl.text.trim().isEmpty ? null : _discDescCtrl.text.trim(),
        'discount_percent': percent,
        'target_role': _discTargetRole,
        'target_category': _discTargetCategory,
        'is_active': true,
      });

      int notified = 0;
      if (_notifyOnDiscount) {
        final catNote = _discTargetCategory == 'الكل' ? 'جميع الأقسام' : _discTargetCategory;
        notified = await _broadcastNotification(
          title: 'خصم جديد ${percent.toStringAsFixed(0)}%: $title',
          body: 'استخدم الكود ($code) للحصول على خصم على $catNote في غيارك!',
          targetRole: _discTargetRole,
          type: 'discount',
        );
      }

      if (mounted) {
        _discTitleCtrl.clear();
        _discCodeCtrl.clear();
        _discDescCtrl.clear();
        _discPercentCtrl.text = '10';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _notifyOnDiscount
                  ? 'تم إنشاء الخصم وإشعار $notified مستخدم بنجاح!'
                  : 'تم إنشاء الخصم بنجاح!',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء إنشاء الخصم: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDiscount = false);
    }
  }

  Future<bool> _confirmDelete(String title, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _editProductDialog(Map<String, dynamic> p) async {
    final titleCtrl = TextEditingController(text: (p['title'] as String?) ?? '');
    final priceCtrl = TextEditingController(text: '${p['price'] ?? 0}');
    final qtyCtrl = TextEditingController(text: '${p['quantity'] ?? 1}');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المنشور (السعر والكمية)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'عنوان القطعة')),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر (د.أ)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية المتوفرة'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
            onPressed: () async {
              final newPrice = double.tryParse(priceCtrl.text.trim()) ??
                  ((p['price'] as num?)?.toDouble() ?? 0.0);
              final rawQty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
              await _db.from('products').update({
                'title': titleCtrl.text.trim().isEmpty ? p['title'] : titleCtrl.text.trim(),
                'price': newPrice,
                'quantity': rawQty < 0 ? 0 : rawQty,
              }).eq('id', p['id']);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث المنشور بنجاح!'), backgroundColor: AppColors.success),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([EnvConfig.paymentsEnabled, EnvConfig.winchEnabled]),
      builder: (context, _) {
        final showPayments = EnvConfig.paymentsEnabled.value;
        final showWinch = EnvConfig.winchEnabled.value;
        final isWide = MediaQuery.of(context).size.width >= 850;
        final menu = <({int id, IconData icon, String title})>[
          (id: 0, icon: Icons.dashboard, title: 'نظرة عامة شاملة'),
          (id: 1, icon: Icons.campaign, title: 'إعلانات الصفحة الرئيسية'),
          (id: 2, icon: Icons.people, title: 'الحسابات والتجار والورش'),
          (id: 3, icon: Icons.tune, title: 'إعدادات النظام والتحكم'),
          (id: 4, icon: Icons.inventory_2, title: 'جميع منشورات القطع'),
          (id: 5, icon: Icons.car_crash, title: 'مراقبة الطوارئ والمواعيد'),
          (id: 7, icon: Icons.local_offer, title: 'الخصومات والإشعارات'),
          if (showPayments)
            (
              id: 6,
              icon: Icons.account_balance,
              title: 'الاشتراكات و CliQ والمالية'
            ),
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
                      icon: const Icon(Icons.storefront, color: Colors.white),
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
                    key: ValueKey('tab_${_tab}_${showPayments}_$showWinch'),
                    child: switch (_tab) {
                      1 => const AdminAdSettingsView(),
                      2 => _accountsControlView(showPayments, showWinch),
                      3 => _settingsView(showPayments, showWinch),
                      4 => _allProductsControlView(),
                      5 => _operationsMonitorView(showWinch),
                      6 => _financeAndSubscriptionsView(),
                      7 => _discountsAndNotificationsView(showWinch),
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
    return Material(
      color: AppColors.navy,
      child: Padding(
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
                    Text('لوحة غيارك',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                  onPressed: () async {
                    await _db.auth.signOut();
                    if (mounted) {
                      Navigator.popUntil(context, (r) => r.isFirst);
                    }
                    widget.onSignedOut();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront, color: Colors.white),
              title: const Text('العودة للرئيسية (المتجر)',
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
                        if (isDrawer) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewView(bool showPayments, bool showWinch, bool isWide) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('products').stream(primaryKey: ['id']),
      builder: (_, prodSnap) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.from('mechanic_requests').stream(primaryKey: ['id']),
        builder: (_, reqSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('workshop_appointments').stream(primaryKey: ['id']),
          builder: (_, apptSnap) => StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db.from('wallet_transactions').stream(primaryKey: ['id']),
            builder: (_, txSnap) => FutureBuilder<List<Map<String, dynamic>>>(
              future: _db.from('customers').select('id, role, created_at'),
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

                final cards = <({String title, int val, IconData icon, VoidCallback onTap})>[
                  (
                    title: 'إجمالي الحسابات',
                    val: users.length,
                    icon: Icons.people,
                    onTap: () => setState(() {
                      _roleFilter = 'all';
                      _tab = 2;
                    }),
                  ),
                  (
                    title: 'الورش والميكانيكيين',
                    val: workshopsCount,
                    icon: Icons.build,
                    onTap: () => setState(() {
                      _roleFilter = 'mechanic';
                      _tab = 2;
                    }),
                  ),
                  (
                    title: 'تجار قطع الغيار',
                    val: merchantsCount,
                    icon: Icons.storefront,
                    onTap: () => setState(() {
                      _roleFilter = 'merchant';
                      _tab = 2;
                    }),
                  ),
                  (
                    title: 'منشورات القطع',
                    val: prods.length,
                    icon: Icons.inventory_2,
                    onTap: () => setState(() => _tab = 4),
                  ),
                  (
                    title: 'إجمالي المشاهدات',
                    val: totalViews,
                    icon: Icons.visibility,
                    onTap: () => setState(() => _tab = 4),
                  ),
                  (
                    title: 'إجمالي النقرات',
                    val: totalClicks,
                    icon: Icons.touch_app,
                    onTap: () => setState(() => _tab = 4),
                  ),
                  (
                    title: 'طلبات الطوارئ',
                    val: reqs.length,
                    icon: Icons.car_crash,
                    onTap: () => setState(() => _tab = 5),
                  ),
                  (
                    title: 'مواعيد الورش',
                    val: appts.length,
                    icon: Icons.event_available,
                    onTap: () => setState(() => _tab = 5),
                  ),
                  if (showPayments) ...[
                    (
                      title: 'إجمالي المبيعات (د.أ)',
                      val: totalGross.toInt(),
                      icon: Icons.payments,
                      onTap: () => setState(() => _tab = 6),
                    ),
                    (
                      title: 'عمولات المنصة (د.أ)',
                      val: totalComm.toInt(),
                      icon: Icons.trending_up,
                      onTap: () => setState(() => _tab = 6),
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
                        childAspectRatio: isWide ? 1.35 : 1.1,
                      ),
                      itemBuilder: (_, i) => FadeSlideIn(
                        index: i,
                        child: _kpi(
                          cards[i].title,
                          cards[i].val,
                          cards[i].icon,
                          onTap: cards[i].onTap,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InteractiveAnimatedChart(
                      title: 'تحليل نشاط المنصة التفاعلي',
                      data: chartData,
                    ),
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future:
          _db.from('customers').select().order('created_at', ascending: false),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allUsers = snap.data!;
        final filtered = allUsers.where((u) {
          if (!showWinch && u['role'] == 'towing') {
            return false;
          }
          if (_roleFilter == 'all') {
            return true;
          }
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
                          Chip(label: Text(m.role)),
                        ],
                      ),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'الإيميل: ${m.email ?? "-"}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          if ((m.phone ?? '').trim().isNotEmpty)
                            InkWell(
                              onTap: () => _callPhone(m.phone),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.call, size: 14, color: AppColors.orange),
                                  const SizedBox(width: 3),
                                  Text(
                                    m.phone!,
                                    style: const TextStyle(
                                      color: AppColors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المنشورات المستخدمة: $postsUsed / الحد الأقصى: $postsLimit منشور',
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
                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _editAccountDialog(
                                raw, showPayments, showWinch),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('تعديل الدور وحد المنشورات'),
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
    final limitCtrl =
        TextEditingController(text: '${raw['max_posts_limit'] ?? 5}');
    final commCtrl =
        TextEditingController(text: '${raw['commission_rate'] ?? 0.15}');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('تعديل حساب: ${raw['full_name'] ?? ""}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'الدور (Role)'),
                items: [
                  const DropdownMenuItem(
                      value: 'user', child: Text('مستخدم عادي (user)')),
                  const DropdownMenuItem(
                      value: 'merchant', child: Text('تاجر قطع (merchant)')),
                  const DropdownMenuItem(
                      value: 'mechanic',
                      child: Text('ميكانيكي/ورشة (mechanic)')),
                  if (showWinch)
                    const DropdownMenuItem(
                        value: 'towing', child: Text('صاحب ونش (towing)')),
                  const DropdownMenuItem(
                      value: 'admin', child: Text('مدير نظام (admin)')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setD(() => role = v);
                  }
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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'نسبة العمولة (مثال: 0.10 = 10%)'),
                ),
              ],
            ],
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
                await _db.from('customers').update({
                  'role': role,
                  'is_admin': role == 'admin',
                  'max_posts_limit': int.tryParse(limitCtrl.text) ?? 5,
                  if (showPayments)
                    'commission_rate': double.tryParse(commCtrl.text) ?? 0.15,
                }).eq('id', raw['id']);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  setState(() {});
                }
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsView(bool showPayments, bool showWinch) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('إعدادات السوبر أدمن والتحكم العام',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            title: const Text('تفعيل قيود عدد المنشورات (فترة التجريب)',
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
              labelText: 'عدد البوستات المسموح (الافتراضي 5 في فترة التجريب)',
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 16),
        if (showWinch && showPayments) ...[
          TextField(
            controller: _kmPriceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'تسعيرة الونش لكل كيلومتر (د.أ)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
        ],
        if (showPayments) ...[
          TextField(
            controller: _defaultCommCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'نسبة العمولة الافتراضية (0.15 = 15%)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minWithdrawCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'الحد الأدنى لسحب الأرباح (د.أ)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cliqAliasCtrl,
            decoration: const InputDecoration(
                labelText: 'حساب CliQ الرسمي', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: SwitchListTile(
            title: const Text('وضع الصيانة'),
            value: _maintenance,
            activeTrackColor: AppColors.orange,
            onChanged: (v) => setState(() => _maintenance = v),
          ),
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
          .stream(primaryKey: ['id']).order('created_at', ascending: false),
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
          padding: const EdgeInsets.all(20),
          itemCount: prods.length,
          itemBuilder: (_, i) {
            final p = prods[i];
            final isHidden = p['is_hidden'] == true;
            final qty = (p['quantity'] as num?)?.toInt() ?? 1;
            final imgs = List<String>.from(p['images'] ?? []);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.placeholder,
                            borderRadius: BorderRadius.circular(10),
                            image: imgs.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(imgs.first),
                                    fit: BoxFit.cover)
                                : null,
                          ),
                          child: imgs.isEmpty ? const Icon(Icons.settings) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p['title'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (isHidden)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'مخفي',
                                        style: TextStyle(color: AppColors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                '${p['car_name']} (${p['car_model']}) · ${p['price']} د.أ · الكمية: $qty',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              Text(
                                'مشاهدات: ${p['views_count'] ?? 0} · نقرات: ${p['clicks_count'] ?? 0}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          onPressed: () => _editProductDialog(p),
                          icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.navy),
                          label: const Text('تعديل السعر/الكمية', style: TextStyle(fontSize: 11, color: AppColors.navy)),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: isHidden ? 'إظهار المنشور' : 'إخفاء المنشور',
                          icon: Icon(
                            isHidden ? Icons.visibility_off : Icons.visibility,
                            color: isHidden ? Colors.orange : AppColors.navy,
                          ),
                          onPressed: () => _db
                              .from('products')
                              .update({'is_hidden': !isHidden}).eq('id', p['id']),
                        ),
                        IconButton(
                          tooltip: 'حذف المنشور',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            final ok = await _confirmDelete(
                              'حذف المنشور',
                              'هل أنت متأكد من حذف منشور "${p['title'] ?? ''}" نهائياً؟',
                            );
                            if (ok) {
                              await _db.from('products').delete().eq('id', p['id']);
                            }
                          },
                        ),
                      ],
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

  Widget _operationsMonitorView(bool showWinch) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('مراقبة طلبات الطوارئ ومواعيد الورش (Live)',
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
              .stream(primaryKey: ['id']).order('created_at', ascending: false),
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
                      child: Text('لا توجد طلبات طوارئ')));
            }
            return Column(
              children: reqs
                  .map((r) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            '${r['service_type'] == 'winch' ? 'ونش' : 'ميكانيكي'} · ${r['car_details'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'المشكلة: ${r['description'] ?? "-"} · الحالة: ${r['status']} (${r['progress_step']})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if ((r['phone'] as String? ?? '').isNotEmpty)
                                InkWell(
                                  onTap: () => _callPhone(r['phone'] as String?),
                                  child: Text(
                                    'اتصال بالعميل: ${r['phone']}',
                                    style: const TextStyle(
                                      color: AppColors.orange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                tooltip: 'تعديل الحالة',
                                icon: const Icon(Icons.edit_note, color: AppColors.navy),
                                onSelected: (val) {
                                  final (newStatus, newStep) = switch (val) {
                                    'pending' => ('pending', 'pending'),
                                    'on_the_way' => ('accepted', 'on_the_way'),
                                    'arrived_at_pickup' => ('accepted', 'arrived_at_pickup'),
                                    'completed' => ('completed', 'completed'),
                                    'cancelled' => ('cancelled', 'cancelled'),
                                    _ => ('pending', 'pending'),
                                  };
                                  _db.from('mechanic_requests').update({
                                    'status': newStatus,
                                    'progress_step': newStep,
                                  }).eq('id', r['id']);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'pending', child: Text('قيد الانتظار (pending)')),
                                  PopupMenuItem(value: 'on_the_way', child: Text('مقبول - في الطريق')),
                                  PopupMenuItem(value: 'arrived_at_pickup', child: Text('وصل لموقع العميل')),
                                  PopupMenuItem(value: 'completed', child: Text('مكتمل (completed)')),
                                  PopupMenuItem(value: 'cancelled', child: Text('ملغي (cancelled)')),
                                ],
                              ),
                              IconButton(
                                tooltip: 'حذف الطلب نهائياً',
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () async {
                                  final ok = await _confirmDelete(
                                    'حذف طلب الطوارئ',
                                    'هل أنت متأكد من حذف هذا الطلب نهائياً من قاعدة البيانات؟',
                                  );
                                  if (ok) {
                                    await _db.from('mechanic_requests').delete().eq('id', r['id']);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
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
              .stream(primaryKey: ['id']).order('created_at', ascending: false),
          builder: (_, snap) {
            final appts = (snap.data ?? [])
                .where((a) => _inPeriod(a['created_at'] as String?))
                .toList();
            if (appts.isEmpty) {
              return const Card(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('لا توجد مواعيد ورش')));
            }
            return Column(
              children: appts
                  .map((a) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            '${a['appointment_date']} · ${a['appointment_time']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${a['service_description'] ?? ""} · الحالة: ${a['status']} (${a['progress_step']})',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                tooltip: 'تعديل حالة الموعد',
                                icon: const Icon(Icons.edit_note, color: AppColors.navy),
                                onSelected: (val) {
                                  final (newStatus, newStep) = switch (val) {
                                    'pending' => ('pending', 'pending'),
                                    'accepted' => ('accepted', 'on_the_way'),
                                    'arrived_at_workshop' => ('accepted', 'arrived_at_workshop'),
                                    'repairing' => ('accepted', 'repairing'),
                                    'completed' => ('completed', 'completed'),
                                    'cancelled' => ('cancelled', 'cancelled'),
                                    _ => ('pending', 'pending'),
                                  };
                                  _db.from('workshop_appointments').update({
                                    'status': newStatus,
                                    'progress_step': newStep,
                                  }).eq('id', a['id']);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'pending', child: Text('بانتظار التأكيد (pending)')),
                                  PopupMenuItem(value: 'accepted', child: Text('مقبول - في الطريق للورشة')),
                                  PopupMenuItem(value: 'arrived_at_workshop', child: Text('وصل للورشة')),
                                  PopupMenuItem(value: 'repairing', child: Text('قيد الإصلاح')),
                                  PopupMenuItem(value: 'completed', child: Text('مكتمل (ينتقل للسجل)')),
                                  PopupMenuItem(value: 'cancelled', child: Text('ملغي (cancelled)')),
                                ],
                              ),
                              IconButton(
                                tooltip: 'حذف الموعد نهائياً',
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () async {
                                  final ok = await _confirmDelete(
                                    'حذف الموعد',
                                    'هل أنت متأكد من حذف هذا الموعد نهائياً (مثلاً موعد محجوز بالغلط)؟',
                                  );
                                  if (ok) {
                                    await _db
                                        .from('workshop_appointments')
                                        .delete()
                                        .eq('id', a['id']);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _discountsAndNotificationsView(bool showWinch) {
    final roleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('جميع المستخدمين')),
      const DropdownMenuItem(value: 'user', child: Text('الزبائن (مستخدم عادي)')),
      const DropdownMenuItem(value: 'merchant', child: Text('تجار قطع الغيار')),
      const DropdownMenuItem(value: 'mechanic', child: Text('الورش والميكانيكيين')),
      if (showWinch) const DropdownMenuItem(value: 'towing', child: Text('أصحاب الونش')),
      const DropdownMenuItem(value: 'pro', child: Text('مشتركي البرو / الباقات')),
    ];

    final categoryItems = ['الكل', ...CarPartsCatalogAZ.mainCategories];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'إرسال الإشعارات والخصومات للزبائن',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        // بطاقة إرسال إشعار فوري للخصومات والعروض
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_active, color: AppColors.orange),
                    SizedBox(width: 8),
                    Text('إرسال إشعار مباشر للهواتف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _notifTargetRole,
                  decoration: const InputDecoration(
                    labelText: 'الفئة المستهدفة بالإشعار',
                    border: OutlineInputBorder(),
                  ),
                  items: roleItems,
                  onChanged: (v) {
                    if (v != null) setState(() => _notifTargetRole = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notifTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الإشعار (مثال: خصم نهاية الأسبوع!)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notifBodyCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'نص الإشعار وتفاصيل العرض',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _sendingNotif ? null : _sendPromoNotification,
                  icon: _sendingNotif
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('إرسال الإشعار للفئة المحددة الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        // بطاقة إنشاء خصم جديد حسب الفئة
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.local_offer, color: AppColors.orange),
                    SizedBox(width: 8),
                    Text('إنشاء كود خصم جديد للزبائن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _discTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العرض / الخصم (مثال: خصم قطع الفرامل)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _discCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'كود الخصم (مثال: GH15)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _discPercentCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'النسبة %',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _discTargetRole,
                  decoration: const InputDecoration(
                    labelText: 'فئة المستخدمين المستهدفة',
                    border: OutlineInputBorder(),
                  ),
                  items: roleItems,
                  onChanged: (v) {
                    if (v != null) setState(() => _discTargetRole = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _discTargetCategory,
                  decoration: const InputDecoration(
                    labelText: 'فئة قطع الغيار المشمولة بالخصم',
                    border: OutlineInputBorder(),
                  ),
                  items: categoryItems
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _discTargetCategory = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _discDescCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات أو شروط الخصم (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _notifyOnDiscount,
                  activeColor: AppColors.orange,
                  title: const Text('إرسال إشعار فوري للفئة المستهدفة بالخصم الجديد', style: TextStyle(fontSize: 13)),
                  onChanged: (v) => setState(() => _notifyOnDiscount = v ?? true),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _savingDiscount ? null : _createDiscount,
                  icon: _savingDiscount
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline),
                  label: const Text('حفظ وتفعيل الخصم', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),
        const Text('الخصومات المسجلة حالياً', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('discounts').stream(primaryKey: ['id']).order('created_at', ascending: false),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد أكواد خصم مضافة حالياً'),
                ),
              );
            }
            return Column(
              children: list.map((d) {
                final active = d['is_active'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: active ? AppColors.orange : AppColors.placeholder,
                      child: Text(
                        '${(d['discount_percent'] as num?)?.toStringAsFixed(0) ?? "0"}%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    title: Text('${d['title']} (${d['code']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      'الفئة: ${d['target_role']} · القسم: ${d['target_category'] ?? "الكل"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: active,
                          activeTrackColor: AppColors.orange,
                          onChanged: (v) => _db.from('discounts').update({'is_active': v}).eq('id', d['id']),
                        ),
                        IconButton(
                          tooltip: 'حذف الخصم',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            final ok = await _confirmDelete('حذف الخصم', 'هل تريد حذف كود الخصم "${d['code']}"؟');
                            if (ok) {
                              await _db.from('discounts').delete().eq('id', d['id']);
                            }
                          },
                        ),
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

  Widget _financeAndSubscriptionsView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('الاشتراكات والحركات المالية',
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
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('wallet_transactions')
              .stream(primaryKey: ['id']).order('created_at', ascending: false),
          builder: (_, snap) {
            final txs = (snap.data ?? [])
                .where((t) => _inPeriod(t['created_at'] as String?))
                .map(DbWalletTransaction.fromMap)
                .toList();

            final totalGross = txs.fold(0.0, (s, t) => s + t.grossAmount);
            final totalComm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
            final totalNet = txs.fold(0.0, (s, t) => s + t.netAmount);
            final partsTotal = txs
                .where((t) => t.transactionType.contains('part'))
                .fold(0.0, (s, t) => s + t.grossAmount);
            final servicesTotal = totalGross - partsTotal;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _kpi('إجمالي المبيعات (د.أ)', totalGross.toInt(),
                            Icons.payments)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _kpi('عمولات المنصة (د.أ)', totalComm.toInt(),
                            Icons.trending_up)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _kpi('صافي المزودين (د.أ)', totalNet.toInt(),
                            Icons.account_balance_wallet)),
                  ],
                ),
                const SizedBox(height: 14),
                InteractiveAnimatedChart(
                  title: 'الرسم البياني للحركة المالية والعمولات',
                  unit: 'د.أ',
                  data: [
                    (label: 'قبل العمولة', value: totalGross),
                    (label: 'العمولات', value: totalComm),
                    (label: 'للمزودين', value: totalNet),
                    (label: 'القطع', value: partsTotal),
                    (label: 'الورش/طوارئ', value: servicesTotal),
                  ],
                ),
                const SizedBox(height: 16),
                if (txs.isEmpty)
                  const Card(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد حركات مالية')),
                  )
                else
                  ...txs.map((t) => Card(
                        child: ListTile(
                          title:
                              Text('${t.transactionType} · ${t.paymentMethod}'),
                          subtitle: Text(
                            'الإجمالي: ${t.grossAmount.toStringAsFixed(2)} | العمولة: ${t.commissionAmount.toStringAsFixed(2)} | الصافي: ${t.netAmount.toStringAsFixed(2)}',
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

  Widget _kpi(String title, int val, IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PulseBlink(child: Icon(icon, color: AppColors.orange, size: 22)),
                  if (onTap != null)
                    const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AnimatedCounter(
                  value: val,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}