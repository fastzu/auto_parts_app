import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
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

  final _kmPriceCtrl = TextEditingController(text: '1.5');
  final _minWithdrawCtrl = TextEditingController(text: '20.0');
  final _cliqAliasCtrl = TextEditingController(text: 'AUTOPARTSJO');
  final _defaultCommCtrl = TextEditingController(text: '0.15');
  bool _maintenance = false;
  bool _saving = false;

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
    super.dispose();
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
        _maintenance = map['maintenance_mode'] == 'true';
        if (map['enable_payments'] != null) {
          EnvConfig.paymentsEnabled.value = map['enable_payments'] == 'true';
        }
        if (map['enable_winch'] != null) {
          EnvConfig.winchEnabled.value = map['enable_winch'] == 'true';
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل الإعدادات: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateSingleSetting(String key, String value) async {
    try {
      await _db.from('system_settings').upsert({'key': key, 'value': value});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم الحفظ في القاعدة (تأكد من صلاحيات SQL): $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final updates = [
        {'key': 'winch_price_per_km', 'value': _kmPriceCtrl.text.trim()},
        {'key': 'min_withdrawal_amount', 'value': _minWithdrawCtrl.text.trim()},
        {'key': 'cliq_alias', 'value': _cliqAliasCtrl.text.trim()},
        {
          'key': 'default_parts_commission',
          'value': _defaultCommCtrl.text.trim()
        },
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ جميع إعدادات السوبر أدمن وتطبيقها فوراً!'),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EnvConfig.paymentsEnabled,
        EnvConfig.winchEnabled,
      ]),
      builder: (context, _) {
        final showPayments = EnvConfig.paymentsEnabled.value;
        final showWinch = EnvConfig.winchEnabled.value;
        final isWide = MediaQuery.of(context).size.width >= 850;

        final menu = <({int id, IconData icon, String title})>[
          (id: 0, icon: Icons.dashboard, title: 'نظرة عامة شاملة'),
          (id: 1, icon: Icons.campaign, title: 'إعلان الصفحة الرئيسية'),
          (id: 2, icon: Icons.people, title: 'الحسابات والتجار والورش'),
          (id: 3, icon: Icons.tune, title: 'إعدادات النظام والتحكم'),
          (id: 4, icon: Icons.inventory_2, title: 'جميع منشورات القطع'),
          (id: 5, icon: Icons.car_crash, title: 'مراقبة الطوارئ والمواعيد'),
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
                  title: Text(
                    currentTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'العودة للرئيسية',
                      icon: const Icon(Icons.storefront),
                      onPressed: _goHome,
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
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
                      _ => _overviewView(showPayments, showWinch),
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
              const Text(
                'لوحة السوبر أدمن',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
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
            leading: const Icon(Icons.storefront, color: Colors.white70),
            title: const Text(
              'العودة للرئيسية (المتجر)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
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
                    leading: Icon(
                      item.icon,
                      color: active ? Colors.white : Colors.white70,
                      size: 20,
                    ),
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
    );
  }

  Widget _overviewView(bool showPayments, bool showWinch) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('products').stream(primaryKey: ['id']),
      builder: (_, prodSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('mechanic_requests').stream(primaryKey: ['id']),
          builder: (_, reqSnap) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream:
                  _db.from('workshop_appointments').stream(primaryKey: ['id']),
              builder: (_, apptSnap) {
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _db.from('customers').select('id, role'),
                  builder: (_, userSnap) {
                    final users = userSnap.data ?? [];
                    final prods = prodSnap.data ?? [];
                    final reqs = (reqSnap.data ?? [])
                        .where((r) => showWinch || r['service_type'] != 'winch')
                        .toList();
                    final appts = apptSnap.data ?? [];

                    final totalViews = prods.fold<int>(
                        0, (s, p) => s + ((p['views_count'] as int?) ?? 0));
                    final totalClicks = prods.fold<int>(
                        0, (s, p) => s + ((p['clicks_count'] as int?) ?? 0));
                    final workshopsCount =
                        users.where((u) => u['role'] == 'mechanic').length;
                    final merchantsCount =
                        users.where((u) => u['role'] == 'merchant').length;

                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Text(
                          'الرؤية الشاملة للمنصة',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'الدفع والمالية: ${showPayments ? "مفعّل" : "مخفي"}  |  الونش: ${showWinch ? "مفعّل" : "مخفي"}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            _kpi('إجمالي الحسابات', '${users.length}',
                                Icons.people),
                            _kpi('الورش والميكانيكيين', '$workshopsCount',
                                Icons.build),
                            _kpi('تجار قطع الغيار', '$merchantsCount',
                                Icons.storefront),
                            _kpi('منشورات القطع', '${prods.length}',
                                Icons.inventory_2),
                            _kpi('إجمالي المشاهدات', '$totalViews',
                                Icons.visibility),
                            _kpi('إجمالي النقرات', '$totalClicks',
                                Icons.touch_app),
                            _kpi('طلبات الطوارئ', '${reqs.length}',
                                Icons.car_crash),
                            _kpi('مواعيد الورش', '${appts.length}',
                                Icons.event_available),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
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
            const Text(
              'التحكم الكامل بالحسابات والتجار والورش',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
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
                      Text(
                        'الإيميل: ${m.email ?? "-"} | الهاتف: ${m.phone ?? "-"}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (m.workshopAddress != null)
                        Text(
                          'عنوان الورشة: ${m.workshopAddress} · السعة: ${m.maxCarCapacity} سيارة/يوم',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      if (showWinch && m.winchPlateNumber != null)
                        Text(
                          'نمرة الونش: ${m.winchPlateNumber} · السائق: ${m.isOwnerWinchDriver ? "صاحب الحساب" : "${m.winchDriverName ?? ""} (${m.winchDriverPhone ?? ""})"}',
                          style: const TextStyle(
                              color: AppColors.orange, fontSize: 12),
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
                                  try {
                                    await _db.from('customers').update({
                                      'is_trusted_merchant': val
                                    }).eq('id', m.id);
                                    if (mounted) {
                                      setState(() {});
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text('خطأ: $e')),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                          OutlinedButton(
                            onPressed: () => _editAccountDialog(
                                raw, showPayments, showWinch),
                            child: const Text('تعديل الحساب'),
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
                decoration:
                    const InputDecoration(labelText: 'الحد الأقصى للمنشورات'),
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
                try {
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
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('تعذر التحديث: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
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
        const Text(
          'إعدادات السوبر أدمن والتحكم العام',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            title: const Text(
              'تفعيل خدمات الونش والسحب',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'عند الإيقاف يُخفى الونش من التسجيل والطوارئ ولوحة التحكم، وعند التفعيل يعود فوراً',
            ),
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
            title: const Text(
              'تفعيل المعاملات المالية والدفع والاشتراكات',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'عند الإيقاف تختفي كل شاشات الدفع والمحافظ والاشتراكات والعمولات، وعند التفعيل تعود فوراً',
            ),
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
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showPayments) ...[
          TextField(
            controller: _defaultCommCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'نسبة العمولة الافتراضية (مثال 0.15 = 15%)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minWithdrawCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'الحد الأدنى لسحب الأرباح (د.أ)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cliqAliasCtrl,
            decoration: const InputDecoration(
              labelText: 'حساب CliQ الرسمي',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SwitchListTile(
          title: const Text('وضع الصيانة'),
          value: _maintenance,
          activeTrackColor: AppColors.orange,
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
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
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
        final prods = snap.data!;
        if (prods.isEmpty) {
          return const Center(
              child: Text('لا توجد منشورات قطع غيار في المنصة'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: prods.length,
          itemBuilder: (_, i) {
            final p = prods[i];
            final isHidden = p['is_hidden'] == true;
            final imgs = List<String>.from(p['images'] ?? []);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
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
                title: Text(p['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${p['car_name']} (${p['car_model']}) · ${p['price']} د.أ · مشاهدات: ${p['views_count'] ?? 0} · نقرات: ${p['clicks_count'] ?? 0}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      tooltip: 'حذف نهائي',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () =>
                          _db.from('products').delete().eq('id', p['id']),
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
        const Text(
          'مراقبة طلبات الطوارئ ومواعيد الورش (Live)',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                .where((r) => showWinch || r['service_type'] != 'winch')
                .toList();
            if (reqs.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد طلبات طوارئ'),
                ),
              );
            }
            return Column(
              children: reqs.map((r) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${r['service_type']} · ${r['car_details']}'),
                    subtitle: Text(
                      'المشكلة: ${r['description'] ?? "-"} · الحالة: ${r['status']} (${r['progress_step']})',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) => _db
                          .from('mechanic_requests')
                          .update({'status': val, 'progress_step': val}).eq(
                              'id', r['id']),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'pending', child: Text('تعليق (pending)')),
                        PopupMenuItem(
                            value: 'completed',
                            child: Text('إنهاء (completed)')),
                        PopupMenuItem(
                            value: 'cancelled',
                            child: Text('إلغاء (cancelled)')),
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
              .stream(primaryKey: ['id']).order('created_at', ascending: false),
          builder: (_, snap) {
            final appts = snap.data ?? [];
            if (appts.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد مواعيد ورش'),
                ),
              );
            }
            return Column(
              children: appts.map((a) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                        '${a['appointment_date']} · ${a['appointment_time']}'),
                    subtitle: Text(
                      '${a['service_description'] ?? ""} · الحالة: ${a['status']} (${a['progress_step']})',
                    ),
                    trailing: IconButton(
                      tooltip: 'إلغاء الموعد',
                      icon:
                          const Icon(Icons.cancel_outlined, color: Colors.red),
                      onPressed: () => _db
                          .from('workshop_appointments')
                          .update({'status': 'cancelled'}).eq('id', a['id']),
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
        const Text(
          'الاشتراكات وطلبات CliQ والحركات المالية',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        const Text('طلبات الاشتراكات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _db
              .from('subscription_requests')
              .select()
              .order('created_at', ascending: false),
          builder: (_, snap) {
            final subs = snap.data ?? [];
            if (subs.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد طلبات اشتراك حالياً'),
                ),
              );
            }
            return Column(
              children: subs.map((s) {
                final isPending = s['status'] == 'pending';
                return Card(
                  child: ListTile(
                    title: Text('${s['plan_name']} (${s['amount']})'),
                    subtitle: Text(
                        'الوسيلة: ${s['payment_method']} · الحالة: ${s['status']}'),
                    trailing: isPending
                        ? ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              await _db.from('subscription_requests').update(
                                  {'status': 'approved'}).eq('id', s['id']);
                              if (s['user_id'] != null) {
                                await _db.from('customers').update({
                                  'subscription_plan': 'provider_1m',
                                  'is_trusted_merchant': true,
                                }).eq('id', s['user_id']);
                              }
                              setState(() {});
                            },
                            child: const Text('اعتماد'),
                          )
                        : null,
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('الحركات المالية (المحافظ)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('wallet_transactions')
              .stream(primaryKey: ['id']).order('created_at', ascending: false),
          builder: (_, snap) {
            final txs =
                (snap.data ?? []).map(DbWalletTransaction.fromMap).toList();
            if (txs.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد حركات مالية بعد'),
                ),
              );
            }
            return Column(
              children: txs.map((t) {
                return Card(
                  child: ListTile(
                    title: Text('${t.transactionType} · ${t.paymentMethod}'),
                    subtitle: Text(
                      'الإجمالي: ${t.grossAmount.toStringAsFixed(2)} | العمولة: ${t.commissionAmount.toStringAsFixed(2)} | الصافي للمزود: ${t.netAmount.toStringAsFixed(2)}',
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

  Widget _kpi(String title, String val, IconData icon) {
    return Container(
      width: 195,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 22),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(val,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
