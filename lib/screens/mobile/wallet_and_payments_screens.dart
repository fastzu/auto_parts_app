import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_top_toast.dart';
import '../../widgets/commission_payment_sheet.dart';

/// شاشة المحفظة الثابتة للتاجر والميكانيكي والونش (لا ترجع لصفر + خيار دفع العمولة)
class ProviderWalletView extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onRefreshProfile;

  const ProviderWalletView({
    super.key,
    required this.profile,
    required this.onRefreshProfile,
  });

  @override
  State<ProviderWalletView> createState() => _ProviderWalletViewState();
}

class _ProviderWalletViewState extends State<ProviderWalletView> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;

  bool _loading = true;
  late double _walletBalance = widget.profile.walletBalance;
  late double _pendingCommissionDebt = widget.profile.pendingCommissionDebt;
  List<DbWalletTransaction> _txs = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _channel = _db
        .channel('provider_wallet_view_${widget.profile.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: widget.profile.id,
          ),
          callback: (_) => _loadData(silent: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'customers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.profile.id,
          ),
          callback: (_) => _loadData(silent: true),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) {
      _db.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
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
            .limit(150),
      ]);

      final cust = results[0] as Map<String, dynamic>?;
      final rows = List<Map<String, dynamic>>.from(results[1] as List);
      final parsed = rows.map(DbWalletTransaction.fromMap).toList();

      if (!mounted) return;
      setState(() {
        if (cust != null) {
          _walletBalance = (cust['wallet_balance'] as num?)?.toDouble() ?? 0.0;
          _pendingCommissionDebt =
              (cust['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;
        }
        _txs = parsed;
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

  @override
  Widget build(BuildContext context) {
    final filtered = _txs.where((t) => _inPeriod(t.createdAt)).toList();
    final earnings = filtered
        .where((t) => t.transactionType != 'commission_settlement')
        .toList();
    final gross = earnings.fold(0.0, (s, t) => s + t.grossAmount);
    final comm = earnings.fold(0.0, (s, t) => s + t.commissionAmount);
    final net = earnings.fold(0.0, (s, t) => s + t.netAmount);
    final displayBalance = _walletBalance > 0 ? _walletBalance : net;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadData();
        widget.onRefreshProfile();
      },
      child: ListView(
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
                const Text('صافي الرصيد في المحفظة (بعد العمولة)',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  '${displayBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'قبل العمولة: ${gross.toStringAsFixed(2)} د.أ  |  العمولات: ${comm.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // بطاقة وزر دفع العمولة المستحقة بنفس وسائل الدفع في التطبيق
          CommissionDebtCard(
            dueCommission: _pendingCommissionDebt,
            walletBalance: _walletBalance,
            onPayTap: () => showCommissionPaymentSheet(
              context: context,
              profile: widget.profile,
              dueCommission: _pendingCommissionDebt,
              walletBalance: _walletBalance,
              onSettled: () {
                _loadData();
                widget.onRefreshProfile();
              },
            ),
          ),

          const SizedBox(height: 16),
          if (_loading && _txs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'لا توجد حركات مالية خلال هذه الفترة',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...filtered.map((t) {
              final isSettlement = t.transactionType == 'commission_settlement';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSettlement
                        ? AppColors.orangeLight
                        : AppColors.success.withValues(alpha: 0.12),
                    child: Icon(
                      isSettlement
                          ? Icons.receipt_long_rounded
                          : Icons.arrow_downward_rounded,
                      color:
                          isSettlement ? AppColors.orange : AppColors.success,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '${_txTypeAr(t.transactionType)} · ${_payMethodAr(t.paymentMethod)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    isSettlement
                        ? 'الحالة: ${t.status == 'pending_review' ? 'بانتظار مراجعة الإدارة' : 'تم التأكيد ✓'}'
                        : 'قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} · عمولة: -${t.commissionAmount.toStringAsFixed(2)}',
                  ),
                  trailing: Text(
                    isSettlement
                        ? '-${t.grossAmount.toStringAsFixed(2)} د.أ'
                        : '+${t.netAmount.toStringAsFixed(2)} د.أ',
                    style: TextStyle(
                      color:
                          isSettlement ? AppColors.orange : AppColors.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _txTypeAr(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => 'بيع قطعة غيار',
        'workshop' || 'appointment' => 'خدمة ورشة',
        'winch_towing' || 'winch' || 'emergency' => 'طلب طوارئ / ونش',
        'commission_settlement' => 'سداد عمولة المنصة',
        _ => raw,
      };

  String _payMethodAr(String raw) => switch (raw.toLowerCase()) {
        'visa' || 'card' || 'meps' => 'Visa / Mastercard',
        'apple_pay' || 'applepay' => 'Apple Pay',
        'google_pay' || 'googlepay' => 'Google Pay',
        'wallet' => 'رصيد المحفظة',
        'cash' => 'نقداً (كاش)',
        _ => raw,
      };
}

/// شاشة المدفوعات وسجل الدفعات للمستخدم العادي
class CustomerPaymentsHistoryScreen extends StatefulWidget {
  final CustomerProfile profile;
  const CustomerPaymentsHistoryScreen({super.key, required this.profile});

  @override
  State<CustomerPaymentsHistoryScreen> createState() =>
      _CustomerPaymentsHistoryScreenState();
}

class _PaymentRecordItem {
  final String id;
  final String title;
  final String providerName;
  final String paymentMethod;
  final double amount;
  final String status;
  final DateTime createdAt;

  const _PaymentRecordItem({
    required this.id,
    required this.title,
    required this.providerName,
    required this.paymentMethod,
    required this.amount,
    required this.status,
    required this.createdAt,
  });
}

class _CustomerPaymentsHistoryScreenState
    extends State<CustomerPaymentsHistoryScreen> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month3;
  DateTimeRange? _customRange;
  bool _loading = true;
  List<_PaymentRecordItem> _records = [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final uid = widget.profile.id;
      final results = await Future.wait([
        _db
            .from('wallet_transactions')
            .select()
            .eq('customer_id', uid)
            .order('created_at', ascending: false)
            .limit(100)
            .catchError((_) => <dynamic>[]),
        _db
            .from('workshop_appointments')
            .select()
            .eq('user_id', uid)
            .eq('payment_status', 'paid')
            .order('created_at', ascending: false)
            .limit(100)
            .catchError((_) => <dynamic>[]),
        _db
            .from('mechanic_requests')
            .select()
            .eq('user_id', uid)
            .eq('payment_status', 'paid')
            .order('created_at', ascending: false)
            .limit(100)
            .catchError((_) => <dynamic>[]),
      ]);

      final txRows = List<Map<String, dynamic>>.from(results[0] as List);
      final apptRows = List<Map<String, dynamic>>.from(results[1] as List);
      final emgRows = List<Map<String, dynamic>>.from(results[2] as List);

      final providerIds = <String>{};
      for (final r in txRows) {
        final pid = r['provider_id'] as String?;
        if (pid != null && pid.isNotEmpty) providerIds.add(pid);
      }
      for (final r in apptRows) {
        final pid = r['workshop_id'] as String?;
        if (pid != null && pid.isNotEmpty) providerIds.add(pid);
      }
      for (final r in emgRows) {
        final pid = r['mechanic_id'] as String?;
        if (pid != null && pid.isNotEmpty) providerIds.add(pid);
      }

      final providerNames = <String, String>{};
      if (providerIds.isNotEmpty) {
        try {
          final pRows = await _db
              .from('customers')
              .select('id, full_name, username')
              .inFilter('id', providerIds.toList());
          for (final p in (pRows as List)) {
            final full = (p['full_name'] as String?)?.trim() ?? '';
            final user = (p['username'] as String?)?.trim() ?? '';
            providerNames[p['id'] as String] =
                full.isNotEmpty ? full : (user.isNotEmpty ? user : 'مقدم خدمة');
          }
        } catch (_) {}
      }

      final seenRefs = <String>{};
      final items = <_PaymentRecordItem>[];

      for (final r in txRows) {
        final refId = (r['reference_id'] ?? r['id']).toString();
        seenRefs.add(refId);
        final pid = r['provider_id'] as String?;
        final type = (r['transaction_type'] as String? ?? 'order');
        items.add(
          _PaymentRecordItem(
            id: (r['id'] ?? '').toString(),
            title: _typeLabel(type),
            providerName:
                pid != null ? (providerNames[pid] ?? 'غيارك') : 'غيارك',
            paymentMethod: (r['payment_method'] as String?) ?? 'visa',
            amount: (r['gross_amount'] as num?)?.toDouble() ?? 0.0,
            status: (r['status'] as String?) ?? 'completed',
            createdAt: DateTime.tryParse((r['created_at'] as String?) ?? '') ??
                DateTime.now(),
          ),
        );
      }

      for (final a in apptRows) {
        final id = (a['id'] ?? '').toString();
        if (seenRefs.contains(id)) continue;
        final pid = a['workshop_id'] as String?;
        items.add(
          _PaymentRecordItem(
            id: id,
            title: (a['service_description'] as String?)?.isNotEmpty == true
                ? 'صيانة ورشة · ${a['service_description']}'
                : 'فاتورة موعد ورشة',
            providerName:
                pid != null ? (providerNames[pid] ?? 'ورشة صيانة') : 'ورشة',
            paymentMethod: (a['payment_method'] as String?) ?? 'cash',
            amount: (a['total_amount'] as num?)?.toDouble() ?? 0.0,
            status: 'completed',
            createdAt: DateTime.tryParse((a['created_at'] as String?) ?? '') ??
                DateTime.now(),
          ),
        );
      }

      for (final e in emgRows) {
        final id = (e['id'] ?? '').toString();
        if (seenRefs.contains(id)) continue;
        final pid = e['mechanic_id'] as String?;
        final isWinch = (e['service_type'] as String?) == 'winch';
        items.add(
          _PaymentRecordItem(
            id: id,
            title: isWinch ? 'فاتورة ونش طوارئ' : 'فاتورة ميكانيكي طوارئ',
            providerName: pid != null
                ? (providerNames[pid] ?? 'مزود طوارئ')
                : 'طوارئ غيارك',
            paymentMethod: (e['payment_method'] as String?) ?? 'cash',
            amount: (e['total_amount'] as num?)?.toDouble() ?? 0.0,
            status: 'completed',
            createdAt: DateTime.tryParse((e['created_at'] as String?) ?? '') ??
                DateTime.now(),
          ),
        );
      }

      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _records = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppTopToast.error('تعذر تحميل سجل الدفعات: $e', context: context);
      }
    }
  }

  bool _inPeriod(DateTime dt) {
    final local = dt.toLocal();
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !local.isBefore(range.start) &&
        !local.isAfter(range.end.add(const Duration(days: 1)));
  }

  String _typeLabel(String raw) => switch (raw.toLowerCase()) {
        'workshop' || 'appointment' => 'فاتورة صيانة ورشة',
        'winch_towing' || 'winch' => 'فاتورة ونش طوارئ',
        'emergency' => 'فاتورة ميكانيكي طوارئ',
        'order' || 'part_order' => 'شراء قطعة غيار',
        'subscription' => 'اشتراك باقة غيارك',
        _ => 'دفعة مالية',
      };

  String _methodLabel(String raw) => switch (raw.toLowerCase()) {
        'visa' || 'card' || 'meps' => 'Visa / Mastercard',
        'apple_pay' || 'applepay' => 'Apple Pay',
        'google_pay' || 'googlepay' => 'Google Pay',
        'cash' => 'نقداً (كاش)',
        _ => raw,
      };

  IconData _methodIcon(String raw) => switch (raw.toLowerCase()) {
        'apple_pay' || 'applepay' => Icons.apple,
        'google_pay' || 'googlepay' => Icons.g_mobiledata_rounded,
        'cash' => Icons.payments_outlined,
        _ => Icons.credit_card_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final filtered = _records.where((r) => _inPeriod(r.createdAt)).toList();
    final totalPaid = filtered.fold(0.0, (s, r) => s + r.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات وسجل الدفعات')),
      body: RefreshIndicator(
        onRefresh: _loadPayments,
        child: ListView(
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
                    'إجمالي مدفوعاتك خلال الفترة',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${totalPaid.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'عدد العمليات المكتملة: ${filtered.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 48, color: AppColors.textSecondary),
                      SizedBox(height: 10),
                      Text(
                        'لا توجد دفعات مسجلة خلال هذه الفترة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filtered.map((r) {
                final dateStr = r.createdAt.toLocal().toString().substring(0, 16);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.orangeLight,
                      child: Icon(_methodIcon(r.paymentMethod),
                          color: AppColors.orange, size: 20),
                    ),
                    title: Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${r.providerName} · ${_methodLabel(r.paymentMethod)}\n$dateStr',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${r.amount.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'مدفوعة ✓',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
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
        AppTopToast.success('تم تحديث معلومات البروفايل بنجاح!',
            context: context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppTopToast.error('تعذر التحديث: $e', context: context);
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