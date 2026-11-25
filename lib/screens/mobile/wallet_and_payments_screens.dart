import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/commission_payment_sheet.dart';

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

  DashboardPeriod _period = DashboardPeriod.months3;
  DateTimeRange? _customRange;

  StreamSubscription<List<Map<String, dynamic>>>? _txSub;
  StreamSubscription<List<Map<String, dynamic>>>? _custSub;

  List<DbWalletTransaction> _transactions = [];
  bool _loading = true;

  late double _storedWalletBalance = widget.profile.walletBalance;
  late double _commissionDebt = widget.profile.pendingCommissionDebt;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _bindStreams();
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _custSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final cust = await _db
          .from('customers')
          .select('wallet_balance, pending_commission_debt')
          .eq('id', widget.profile.id)
          .maybeSingle();

      final rows = await _db
          .from('wallet_transactions')
          .select()
          .eq('provider_id', widget.profile.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        if (cust != null) {
          _storedWalletBalance =
              (cust['wallet_balance'] as num?)?.toDouble() ??
                  _storedWalletBalance;
          _commissionDebt =
              (cust['pending_commission_debt'] as num?)?.toDouble() ??
                  _commissionDebt;
        }
        _transactions = List<Map<String, dynamic>>.from(rows)
            .map(DbWalletTransaction.fromMap)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _bindStreams() {
    _txSub?.cancel();
    _custSub?.cancel();

    _txSub = _db
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('provider_id', widget.profile.id)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _transactions =
                  rows.map(DbWalletTransaction.fromMap).toList();
              _loading = false;
            });
          },
          onError: (_) {},
        );

    _custSub = _db
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', widget.profile.id)
        .listen(
          (rows) {
            if (!mounted || rows.isEmpty) return;
            final c = rows.first;
            setState(() {
              _storedWalletBalance =
                  (c['wallet_balance'] as num?)?.toDouble() ??
                      _storedWalletBalance;
              _commissionDebt =
                  (c['pending_commission_debt'] as num?)?.toDouble() ??
                      _commissionDebt;
            });
          },
          onError: (_) {},
        );
  }

  bool _inPeriod(DateTime dt) {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  String _txLabel(String type) => switch (type) {
        'workshop' => 'فاتورة صيانة ورشة',
        'emergency' => 'فاتورة خدمة طوارئ',
        'winch' => 'فاتورة ونش سحب',
        'commission_settlement' => 'سداد عمولة للمنصة',
        'subscription' => 'اشتراك باقة',
        _ => 'حركة مالية ($type)',
      };

  @override
  Widget build(BuildContext context) {
    final filtered =
        _transactions.where((t) => _inPeriod(t.createdAt)).toList();

    final txGross = filtered.fold<double>(0.0, (s, t) => s + t.grossAmount);
    final txComm = filtered.fold<double>(0.0, (s, t) => s + t.commissionAmount);
    final txNet = filtered.fold<double>(0.0, (s, t) => s + t.netAmount);

    final displayNet = _storedWalletBalance > 0 ? _storedWalletBalance : txNet;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadInitial();
        widget.onRefreshProfile();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'صافي الرصيد في المحفظة (بعد العمولة)',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${displayNet.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'قبل العمولة: ${txGross.toStringAsFixed(2)} د.أ  |  العمولات: ${txComm.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          CommissionDebtCard(
            debtAmount: _commissionDebt,
            walletBalance: displayNet,
            onPayTap: () async {
              final settled = await showCommissionPaymentSheet(
                context: context,
                profile: widget.profile,
                debtAmount: _commissionDebt,
                walletBalance: displayNet,
                onSettled: () {
                  _loadInitial();
                  widget.onRefreshProfile();
                },
              );
              if (settled) {
                await _loadInitial();
                widget.onRefreshProfile();
              }
            },
          ),

          const SizedBox(height: 18),
          const Text(
            'سجل الحركات المالية',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text(
                  'لا توجد حركات مالية ضمن هذه الفترة',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...filtered.map(
              (t) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: t.netAmount >= 0
                        ? AppColors.success.withValues(alpha: 0.14)
                        : Colors.red.withValues(alpha: 0.12),
                    child: Icon(
                      t.netAmount >= 0
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color:
                          t.netAmount >= 0 ? AppColors.success : Colors.red,
                    ),
                  ),
                  title: Text(
                    _txLabel(t.transactionType),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'الوسيلة: ${t.paymentMethod} · قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} · عمولة: ${t.commissionAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Text(
                    '${t.netAmount >= 0 ? '+' : ''}${t.netAmount.toStringAsFixed(2)} د.أ',
                    style: TextStyle(
                      color:
                          t.netAmount >= 0 ? AppColors.success : Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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

class CustomerPaymentsHistoryScreen extends StatefulWidget {
  final CustomerProfile profile;
  const CustomerPaymentsHistoryScreen({super.key, required this.profile});

  @override
  State<CustomerPaymentsHistoryScreen> createState() =>
      _CustomerPaymentsHistoryScreenState();
}

class _PaymentRecord {
  final String title;
  final String subtitle;
  final double amount;
  final String method;
  final String status;
  final DateTime date;

  const _PaymentRecord({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.method,
    required this.status,
    required this.date,
  });
}

class _CustomerPaymentsHistoryScreenState
    extends State<CustomerPaymentsHistoryScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  List<_PaymentRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    final list = <_PaymentRecord>[];
    final seenIds = <String>{};

    try {
      final txRows = await _db
          .from('wallet_transactions')
          .select()
          .eq('customer_id', widget.profile.id)
          .order('created_at', ascending: false);

      for (final raw in List<Map<String, dynamic>>.from(txRows)) {
        final refId = (raw['reference_id'] ?? raw['id']).toString();
        seenIds.add(refId);
        list.add(_PaymentRecord(
          title: _typeArabic((raw['transaction_type'] as String?) ?? ''),
          subtitle: 'طريقة الدفع: ${_methodArabic(raw['payment_method'] as String?)}',
          amount: (raw['gross_amount'] as num?)?.toDouble() ?? 0.0,
          method: _methodArabic(raw['payment_method'] as String?),
          status: (raw['status'] as String?) ?? 'completed',
          date: DateTime.tryParse((raw['created_at'] ?? '').toString()) ??
              DateTime.now(),
        ));
      }
    } catch (_) {}

    try {
      final appts = await _db
          .from('workshop_appointments')
          .select()
          .eq('user_id', widget.profile.id)
          .gt('total_amount', 0)
          .order('created_at', ascending: false);

      for (final a in List<Map<String, dynamic>>.from(appts)) {
        final id = (a['id'] ?? '').toString();
        if (seenIds.contains(id)) continue;
        list.add(_PaymentRecord(
          title: 'فاتورة ورشة صيانة',
          subtitle:
              '${a['service_description'] ?? 'صيانة مركبة'} · ${a['appointment_date'] ?? ''}',
          amount: (a['total_amount'] as num?)?.toDouble() ?? 0.0,
          method: _methodArabic(a['payment_method'] as String?),
          status: (a['payment_status'] as String?) ?? 'unpaid',
          date: DateTime.tryParse((a['created_at'] ?? '').toString()) ??
              DateTime.now(),
        ));
      }
    } catch (_) {}

    try {
      final emgs = await _db
          .from('mechanic_requests')
          .select()
          .eq('user_id', widget.profile.id)
          .gt('total_amount', 0)
          .order('created_at', ascending: false);

      for (final e in List<Map<String, dynamic>>.from(emgs)) {
        final id = (e['id'] ?? '').toString();
        if (seenIds.contains(id)) continue;
        final isWinch = (e['service_type'] as String?) == 'winch';
        list.add(_PaymentRecord(
          title: isWinch ? 'فاتورة ونش طوارئ' : 'فاتورة ميكانيكي طوارئ',
          subtitle: (e['description'] as String?) ?? (e['car_details'] as String? ?? ''),
          amount: (e['total_amount'] as num?)?.toDouble() ?? 0.0,
          method: _methodArabic(e['payment_method'] as String?),
          status: (e['payment_status'] as String?) ?? 'unpaid',
          date: DateTime.tryParse((e['created_at'] ?? '').toString()) ??
              DateTime.now(),
        ));
      }
    } catch (_) {}

    list.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  String _typeArabic(String type) => switch (type) {
        'workshop' => 'فاتورة ورشة صيانة',
        'emergency' => 'فاتورة ميكانيكي طوارئ',
        'winch' => 'فاتورة ونش سحب',
        'subscription' => 'اشتراك عضوية',
        _ => 'دفعة إلكترونية',
      };

  String _methodArabic(String? method) => switch ((method ?? '').toLowerCase()) {
        'visa' || 'card' => 'Visa / Mastercard',
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'cash' => 'نقداً (كاش)',
        'wallet' => 'المحفظة',
        _ => 'دفع إلكتروني',
      };

  @override
  Widget build(BuildContext context) {
    final totalPaid = _records
        .where((r) => r.status == 'paid' || r.status == 'completed')
        .fold<double>(0.0, (s, r) => s + r.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات وسجل الدفعات')),
      body: RefreshIndicator(
        onRefresh: _loadPayments,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إجمالي مدفوعاتك المكتملة',
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
                  const SizedBox(height: 4),
                  Text(
                    'عدد الفواتير المسجلة: ${_records.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_records.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 46, color: AppColors.textSecondary),
                    SizedBox(height: 10),
                    Text(
                      'لا توجد مدفوعات أو فواتير مسجلة حتى الآن',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            else
              ..._records.map((r) {
                final isPaid = r.status == 'paid' || r.status == 'completed';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isPaid
                          ? AppColors.success.withValues(alpha: 0.14)
                          : AppColors.orangeLight,
                      child: Icon(
                        isPaid ? Icons.check_circle : Icons.schedule,
                        color: isPaid ? AppColors.success : AppColors.orange,
                      ),
                    ),
                    title: Text(
                      r.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${r.subtitle}\n${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')} · ${r.method}',
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
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isPaid ? 'مدفوعة ✓' : 'غير مدفوعة',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                isPaid ? AppColors.success : AppColors.orange,
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

  void _showTopNotice(String title, String message, {bool isError = false}) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFDC2626) : AppColors.success,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
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
        _showTopNotice(
          'تم التحديث بنجاح',
          'تم حفظ معلومات البروفايل بنجاح.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showTopNotice('تعذر التحديث', '$e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final isProvider =
        p.role == 'merchant' || p.role == 'mechanic' || p.role == 'towing';

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
                if (isProvider) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        p.ratingCount > 0
                            ? 'التقييم: ${p.ratingAvg.toStringAsFixed(1)} / 5 (${p.ratingCount} تقييم)'
                            : 'لا توجد تقييمات بعد',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
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