import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/location_service.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

// ============================================================================
// 1) محفظة مزود الخدمة (ورشة / تاجر / ونش) مع إصلاح RPC السحب للبنك
// ============================================================================
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

  bool _loading = true;
  double _walletBalance = 0.0;
  double _pendingDebt = 0.0;
  int _warningsCount = 0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _withdrawals = [];

  @override
  void initState() {
    super.initState();
    _walletBalance = widget.profile.walletBalance;
    _pendingDebt = widget.profile.pendingCommissionDebt;
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    setState(() => _loading = true);
    try {
      final uid = widget.profile.id;
      final cust = await _db
          .from('customers')
          .select('wallet_balance, pending_commission_debt, warnings_count')
          .eq('id', uid)
          .maybeSingle();

      final txRows = await _db
          .from('wallet_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);

      List<Map<String, dynamic>> wdRows = [];
      try {
        final res = await _db
            .from('withdrawal_requests')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(30);
        wdRows = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        if (cust != null) {
          _walletBalance =
              ((cust['wallet_balance'] as num?) ?? 0.0).toDouble();
          _pendingDebt =
              ((cust['pending_commission_debt'] as num?) ?? 0.0).toDouble();
          _warningsCount = (cust['warnings_count'] as num?)?.toInt() ?? 0;
        }
        _transactions = List<Map<String, dynamic>>.from(txRows);
        _withdrawals = wdRows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _inPeriod(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  Future<void> _openWithdrawSheet() async {
    final amountCtrl = TextEditingController(
      text: _walletBalance > 0 ? _walletBalance.toStringAsFixed(2) : '',
    );
    final bankCtrl = TextEditingController();
    final holderCtrl = TextEditingController(
      text: widget.profile.fullName ?? widget.profile.username ?? '',
    );
    final ibanOrAliasCtrl = TextEditingController();
    String payoutMethod = 'cliq';
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'سحب الأرباح إلى البنك (IBAN / CliQ)',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'الرصيد المتاح للسحب: ${_walletBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'طريقة الاستلام',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('CliQ · كليك'),
                      selected: payoutMethod == 'cliq',
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(
                        color: payoutMethod == 'cliq'
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      onSelected: (_) => setS(() => payoutMethod = 'cliq'),
                    ),
                    ChoiceChip(
                      label: const Text('تحويل بنكي (IBAN)'),
                      selected: payoutMethod == 'bank_iban',
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(
                        color: payoutMethod == 'bank_iban'
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      onSelected: (_) => setS(() => payoutMethod = 'bank_iban'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المطلوب سحبه (د.أ)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم صاحب الحساب البنكي',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم البنك (مثال: البنك العربي / الاتحاد)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ibanOrAliasCtrl,
                  decoration: InputDecoration(
                    labelText: payoutMethod == 'cliq'
                        ? 'الاسم المستعار CliQ Alias أو رقم الهاتف'
                        : 'رقم الآيبان (IBAN)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: submitting
                        ? null
                        : () async {
                            final amount =
                                double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                            final holder = holderCtrl.text.trim();
                            final bank = bankCtrl.text.trim();
                            final ibanOrAlias = ibanOrAliasCtrl.text.trim();

                            if (amount <= 0 || amount > _walletBalance) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'يرجى إدخال مبلغ صحيح لا يتجاوز الرصيد المتاح',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            if (holder.isEmpty ||
                                bank.isEmpty ||
                                ibanOrAlias.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('يرجى تعبئة جميع بيانات البنك'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            setS(() => submitting = true);
                            try {
                              // استدعاء RPC بالأسماء الدقيقة المطابقة لقاعدة البيانات
                              await _db.rpc(
                                'request_wallet_withdrawal',
                                params: {
                                  'p_amount': amount,
                                  'p_payout_method': payoutMethod,
                                  'p_iban_or_alias': ibanOrAlias,
                                  'p_bank_name': bank,
                                  'p_account_holder': holder,
                                },
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              widget.onRefreshProfile();
                              await _loadWalletData();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'تم إرسال طلب سحب الأرباح بنجاح! سيتم التحويل لحسابك خلال 24-48 ساعة عمل.',
                                    ),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              setS(() => submitting = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تعذر إرسال طلب السحب: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.account_balance),
                    label: const Text(
                      'تأكيد طلب السحب',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    amountCtrl.dispose();
    bankCtrl.dispose();
    holderCtrl.dispose();
    ibanOrAliasCtrl.dispose();
  }

  Future<void> _payPendingDebt() async {
    if (_pendingDebt <= 0) return;
    final ok = await PayTabsPaymentService().startPaymentFlow(
      context: context,
      baseAmount: _pendingDebt,
      title: 'سداد عمولات وغرامات منصة غيارك',
      orderType: 'debt',
      referenceId: widget.profile.id,
      email: widget.profile.email,
      phone: widget.profile.phone,
      name: widget.profile.fullName ?? widget.profile.username,
      userRole: widget.profile.role,
    );
    if (ok && mounted) {
      widget.onRefreshProfile();
      await _loadWalletData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم سداد الذمم المستحقة بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTx =
        _transactions.where((t) => _inPeriod(t['created_at'] as String?)).toList();

    double grossPeriod = 0;
    double commPeriod = 0;
    double netPeriod = 0;
    for (final tx in filteredTx) {
      final type = (tx['type'] as String? ?? '').toLowerCase();
      final amt = ((tx['amount'] as num?) ?? 0).toDouble();
      if (type == 'earning' || type == 'credit' || type == 'order_earning') {
        netPeriod += amt;
        grossPeriod += amt;
      } else if (type == 'commission' || type == 'cancellation_penalty') {
        commPeriod += amt.abs();
      }
    }

    return RefreshIndicator(
      onRefresh: _loadWalletData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
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

          // بطاقة الرصيد القابل للسحب
          Container(
            padding: const EdgeInsets.all(20),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الرصيد القابل للسحب إلى البنك (إلكتروني)',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_walletBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'صافي أرباح الفترة: ${netPeriod.toStringAsFixed(2)} د.أ · قبل العمولة: ${grossPeriod.toStringAsFixed(2)} · العمولة والغرامات: ${commPeriod.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _walletBalance > 0 ? _openWithdrawSheet : null,
                    icon: const Icon(Icons.account_balance),
                    label: const Text(
                      'سحب الأرباح إلى البنك (IBAN / CliQ)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // بطاقة العمولات والذمم المستحقة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _pendingDebt > 0
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _pendingDebt > 0
                    ? Colors.red.withValues(alpha: 0.35)
                    : AppColors.success.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _pendingDebt > 0
                          ? Colors.red.withValues(alpha: 0.14)
                          : AppColors.success.withValues(alpha: 0.14),
                      child: Icon(
                        _pendingDebt > 0
                            ? Icons.warning_amber_rounded
                            : Icons.verified,
                        color: _pendingDebt > 0
                            ? Colors.red
                            : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pendingDebt > 0
                                ? 'ذمم وعمولات مستحقة عليك'
                                : 'لا توجد عمولات مستحقة عليك',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            _pendingDebt > 0
                                ? 'يرجى تسديد المستحقات لتجنب قيود الحساب'
                                : 'حسابك المالي مسوّى بالكامل ✓',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_pendingDebt.toStringAsFixed(2)} د.أ',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color:
                            _pendingDebt > 0 ? Colors.red : AppColors.success,
                      ),
                    ),
                  ],
                ),
                if (_pendingDebt > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _payPendingDebt,
                      icon: const Icon(Icons.payment),
                      label: Text(
                        'سداد الذمم الآن (${_pendingDebt.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_warningsCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, color: AppColors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'لديك $_warningsCount إنذار(ات) على الحساب بسبب تجاوز نسبة إلغاء الطلبات. يرجى الالتزام بسياسة المنصة.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // طلبات السحب البنكي
          if (_withdrawals.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'طلبات السحب البنكي',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            ..._withdrawals.map((w) {
              final status = (w['status'] as String? ?? 'pending');
              final amt = ((w['amount'] as num?) ?? 0).toDouble();
              final bank = w['bank_name'] as String? ?? '';
              final method = w['payout_method'] as String? ?? 'cliq';
              final statusLabel = switch (status) {
                'paid' || 'completed' || 'approved' => 'تم التحويل ✓',
                'rejected' => 'مرفوض (أُعيد للرصيد)',
                _ => 'قيد المراجعة والتحويل',
              };
              final statusColor = switch (status) {
                'paid' || 'completed' || 'approved' => AppColors.success,
                'rejected' => Colors.red,
                _ => AppColors.orange,
              };
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.account_balance_outlined,
                      color: statusColor),
                  title: Text(
                    'سحب ${amt.toStringAsFixed(2)} د.أ · ${method.toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$bank · $statusLabel'),
                  trailing: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 20),
          const Text(
            'سجل الحركات المالية والعمولات',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (filteredTx.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا توجد حركات مالية في هذه الفترة',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            )
          else
            ...filteredTx.map((tx) {
              final type = (tx['type'] as String? ?? '').toLowerCase();
              final amt = ((tx['amount'] as num?) ?? 0).toDouble();
              final desc = tx['description'] as String? ?? '';
              final isPenalty = type == 'cancellation_penalty';
              final isDebit = isPenalty ||
                  type == 'withdrawal' ||
                  type == 'commission' ||
                  amt < 0;
              final label = switch (type) {
                'cancellation_penalty' => 'غرامة إلغاء متكرر',
                'withdrawal' => 'سحب أرباح للبنك',
                'commission' => 'عمولة المنصة',
                'cliq_payment' => 'حوالة CliQ',
                'earning' || 'order_earning' => 'أرباح طلب إلكتروني',
                _ => 'حركة مالية',
              };
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (isDebit ? Colors.red : AppColors.success)
                        .withValues(alpha: 0.12),
                    child: Icon(
                      isPenalty
                          ? Icons.gavel
                          : (isDebit
                              ? Icons.arrow_upward
                              : Icons.arrow_downward),
                      color: isDebit ? Colors.red : AppColors.success,
                    ),
                  ),
                  title: Text(
                    label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '${isDebit ? '-' : '+'}${amt.abs().toStringAsFixed(2)} د.أ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isDebit ? Colors.red : AppColors.success,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ============================================================================
// 2) شاشة الفواتير وسجل الدفعات للمستخدم العادي (مع دفع الفواتير المستحقة)
// ============================================================================
class _PendingCustomerInvoice {
  final String id;
  final String orderType; // 'wrk' | 'emg'
  final String title;
  final String subtitle;
  final double amount;

  const _PendingCustomerInvoice({
    required this.id,
    required this.orderType,
    required this.title,
    required this.subtitle,
    required this.amount,
  });
}

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
  bool _loading = true;
  List<_PendingCustomerInvoice> _pendingInvoices = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final uid = widget.profile.id;
    final List<_PendingCustomerInvoice> pending = [];

    try {
      // 1) فواتير مواعيد الورش الصادرة وغير المسددة
      final wrkRows = await _db
          .from('workshop_appointments')
          .select('id, car_model, service_description, final_price, status, progress_step')
          .eq('customer_id', uid)
          .gt('final_price', 0)
          .neq('status', 'completed')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);

      for (final r in (wrkRows as List)) {
        final price = ((r['final_price'] as num?) ?? 0).toDouble();
        if (price > 0) {
          pending.add(
            _PendingCustomerInvoice(
              id: r['id'].toString(),
              orderType: 'wrk',
              title: 'فاتورة صيانة ورشة (${r['car_model'] ?? 'سيارة'})',
              subtitle: (r['service_description'] as String?) ?? 'خدمة صيانة',
              amount: price,
            ),
          );
        }
      }
    } catch (_) {}

    try {
      // 2) فواتير الطوارئ والونش المستحقة
      final emgRows = await _db
          .from('mechanic_requests')
          .select('id, service_type, problem_type, final_price, estimated_price, status, progress_step')
          .eq('customer_id', uid)
          .inFilter('status', ['accepted', 'in_progress', 'awaiting_payment'])
          .order('created_at', ascending: false);

      for (final r in (emgRows as List)) {
        final price = ((r['final_price'] as num?) ??
                (r['estimated_price'] as num?) ??
                0)
            .toDouble();
        final step = (r['progress_step'] as String? ?? '');
        if (price > 0 &&
            (step == 'car_ready' ||
                step == 'awaiting_payment' ||
                r['status'] == 'awaiting_payment')) {
          final isWinch = r['service_type'] == 'winch';
          pending.add(
            _PendingCustomerInvoice(
              id: r['id'].toString(),
              orderType: 'emg',
              title: isWinch ? 'فاتورة سحب ونش طوارئ' : 'فاتورة ميكانيكي طوارئ',
              subtitle: (r['problem_type'] as String?) ?? 'إنقاذ طريق',
              amount: price,
            ),
          );
        }
      }
    } catch (_) {}

    List<Map<String, dynamic>> txHistory = [];
    try {
      final rows = await _db
          .from('wallet_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(80);
      txHistory = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _pendingInvoices = pending;
      _history = txHistory;
      _loading = false;
    });
  }

  Future<void> _payInvoice(_PendingCustomerInvoice inv) async {
    final ok = await PayTabsPaymentService().startPaymentFlow(
      context: context,
      baseAmount: inv.amount,
      title: inv.title,
      orderType: inv.orderType,
      referenceId: inv.id,
      email: widget.profile.email,
      phone: widget.profile.phone,
      name: widget.profile.fullName ?? widget.profile.username,
      userRole: widget.profile.role,
    );
    if (ok && mounted) {
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد دفع الفاتورة من البنك بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فواتيري وسجل المدفوعات')),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                children: [
                  // قسم الفواتير المستحقة للدفع
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: AppColors.orange,
                          child:
                              Icon(Icons.receipt_long, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'دفع الفواتير المستحقة',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                ),
                              ),
                              Text(
                                _pendingInvoices.isEmpty
                                    ? 'لا توجد فواتير مستحقة عليك حالياً ✓'
                                    : 'لديك ${_pendingInvoices.length} فاتورة جاهزة للدفع الإلكتروني',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_pendingInvoices.isNotEmpty) ...[
                    ..._pendingInvoices.map((inv) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: AppColors.orange.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        inv.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${inv.amount.toStringAsFixed(2)} د.أ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: AppColors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  inv.subtitle,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () => _payInvoice(inv),
                                    icon: const Icon(Icons.credit_card),
                                    label: Text(
                                      'ادفع الفاتورة الآن (${inv.amount.toStringAsFixed(2)} د.أ)',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 14),
                  ],

                  const Text(
                    'سجل الدفعات السابقة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'لا توجد مدفوعات مسجلة بعد',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._history.map((tx) {
                      final amt = ((tx['amount'] as num?) ?? 0).toDouble();
                      final status = (tx['status'] as String? ?? 'completed');
                      final desc = (tx['description'] as String?) ?? 'دفعة إلكترونية';
                      final isPending = status == 'pending_review' || status == 'pending';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (isPending
                                    ? AppColors.orange
                                    : AppColors.success)
                                .withValues(alpha: 0.14),
                            child: Icon(
                              isPending
                                  ? Icons.hourglass_top
                                  : Icons.check_circle,
                              color: isPending
                                  ? AppColors.orange
                                  : AppColors.success,
                            ),
                          ),
                          title: Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          subtitle: Text(
                            isPending ? 'قيد المراجعة البنكية' : 'تم التأكيد ✓',
                            style: TextStyle(
                              fontSize: 12,
                              color: isPending
                                  ? AppColors.orange
                                  : AppColors.success,
                            ),
                          ),
                          trailing: Text(
                            '${amt.abs().toStringAsFixed(2)} د.أ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
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

// ============================================================================
// 3) شاشة الملف الشخصي وإعدادات الحساب (تغيير موقع الورشة + Refund 24h + حذف الحساب + السياسات)
// ============================================================================
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
  final _locationService = LocationService();

  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _workshopAddressCtrl;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _buildingCtrl;
  late final TextEditingController _openingHoursCtrl;
  late final TextEditingController _capacityCtrl;

  double? _workshopLat;
  double? _workshopLng;
  bool _saving = false;
  bool _updatingLocation = false;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _fullNameCtrl = TextEditingController(text: p.fullName ?? '');
    _usernameCtrl = TextEditingController(text: p.username ?? '');
    _phoneCtrl = TextEditingController(text: p.phone ?? '');
    _workshopAddressCtrl = TextEditingController(text: p.workshopAddress ?? '');
    _streetCtrl = TextEditingController(text: p.streetName ?? '');
    _buildingCtrl = TextEditingController(text: p.buildingNumber ?? '');
    _openingHoursCtrl = TextEditingController(text: p.openingHours);
    _capacityCtrl = TextEditingController(text: p.maxCarCapacity.toString());
    _workshopLat = p.workshopLatitude ?? p.latitude;
    _workshopLng = p.workshopLongitude ?? p.longitude;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _workshopAddressCtrl.dispose();
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _openingHoursCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final isMechanic = widget.profile.role == 'mechanic';
      final payload = <String, dynamic>{
        'full_name': _fullNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      };
      if (isMechanic) {
        payload['workshop_address'] = _workshopAddressCtrl.text.trim();
        payload['street_name'] = _streetCtrl.text.trim();
        payload['building_number'] = _buildingCtrl.text.trim();
        payload['opening_hours'] = _openingHoursCtrl.text.trim();
        payload['max_car_capacity'] =
            (int.tryParse(_capacityCtrl.text.trim()) ?? 5).clamp(1, 50);
        if (_workshopLat != null && _workshopLng != null) {
          payload['workshop_latitude'] = _workshopLat;
          payload['workshop_longitude'] = _workshopLng;
          payload['latitude'] = _workshopLat;
          payload['longitude'] = _workshopLng;
        }
      }

      await _db.from('customers').update(payload).eq('id', widget.profile.id);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ التعديلات بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// تغيير موقع الورشة (باختيار الموقع الحالي GPS أو تحديده على الخريطة)
  Future<void> _openWorkshopLocationPicker() async {
    setState(() => _updatingLocation = true);
    LatLng initialPoint = LatLng(
      _workshopLat ?? 31.9539,
      _workshopLng ?? 35.9106,
    );
    String addressText = _workshopAddressCtrl.text.trim();

    if (_workshopLat == null || _workshopLng == null) {
      final res = await _locationService.getCurrentLocation();
      initialPoint = res.coordinates;
      addressText = res.address;
    }
    if (mounted) setState(() => _updatingLocation = false);
    if (!mounted) return;

    LatLng picked = initialPoint;
    String pickedAddr =
        addressText.isNotEmpty ? addressText : 'اضغط على الخريطة لتحديد موقع الورشة';
    bool loadingGps = false;
    final mapCtrl = MapController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تغيير موقع الورشة على الخريطة',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: loadingGps
                          ? null
                          : () async {
                              setM(() => loadingGps = true);
                              final res =
                                  await _locationService.getCurrentLocation();
                              setM(() {
                                picked = res.coordinates;
                                pickedAddr = res.address;
                                loadingGps = false;
                              });
                              mapCtrl.move(picked, 16);
                            },
                      icon: loadingGps
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 18),
                      label: const Text('موقعي الحالي'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FlutterMap(
                  mapController: mapCtrl,
                  options: MapOptions(
                    initialCenter: picked,
                    initialZoom: 15,
                    onTap: (_, latLng) async {
                      setM(() => picked = latLng);
                      final addr =
                          await _locationService.getAddressFromLatLng(latLng);
                      if (ctx.mounted) setM(() => pickedAddr = addr);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.autoparts.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: picked,
                          width: 46,
                          height: 46,
                          child: const Icon(
                            Icons.location_pin,
                            color: AppColors.orange,
                            size: 46,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      pickedAddr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'اعتماد موقع الورشة الجديد',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _workshopLat = picked.latitude;
        _workshopLng = picked.longitude;
        _workshopAddressCtrl.text = pickedAddr;
      });
      await _saveProfile();
    }
  }

  /// طلب استرجاع قيمة الباقة (Refund - خلال 24 ساعة فقط)
  Future<void> _requestSubscriptionRefund() async {
    final reasonCtrl = TextEditingController();
    bool sending = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('طلب استرجاع الباقة (Refund)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سياسة الاسترجاع: يُسمح بطلب استرجاع الاشتراك خلال 24 ساعة فقط من وقت التفعيل. بعد مرور 24 ساعة لا يُقبل الاسترجاع.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'سبب طلب الاسترجاع',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: sending
                  ? null
                  : () async {
                      setD(() => sending = true);
                      try {
                        await _db.rpc(
                          'request_subscription_refund',
                          params: {
                            'p_reason': reasonCtrl.text.trim().isEmpty
                                ? 'طلب استرجاع خلال 24 ساعة'
                                : reasonCtrl.text.trim(),
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تم استلام طلب الاسترجاع بنجاح! ستقوم الإدارة بمراجعته وإعادة المبلغ.',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        setD(() => sending = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('PostgrestException(message: ', ''),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('إرسال طلب الاسترجاع'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  /// حذف الحساب نهائياً (متطلب أساسي لقبول Apple App Store)
  Future<void> _confirmAndDeleteAccount() async {
    final confirmCtrl = TextEditingController();
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'حذف الحساب نهائياً',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تنبيه: سيتم حذف حسابك وبياناتك الشخصية نهائياً ولا يمكن التراجع عن هذا الإجراء.\n(ملاحظة: لا يمكن حذف الحساب في حال وجود عمولات أو ذمم مالية غير مسددة).',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'اكتب كلمة "حذف" للتأكيد',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (confirmCtrl.text.trim() == 'حذف' ||
                  confirmCtrl.text.trim().toUpperCase() == 'DELETE') {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى كتابة كلمة "حذف" للتأكيد'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('تأكيد الحذف النهائي'),
          ),
        ],
      ),
    );
    confirmCtrl.dispose();

    if (step1 != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await _db.rpc('delete_my_account');
      await _db.auth.signOut();
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف حسابك نهائياً بنجاح.'),
            backgroundColor: AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حذف الحساب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final isMechanic = p.role == 'mechanic';
    final hasPaidPlan = p.subscriptionPlan != 'free' && p.subscriptionPlan.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الحساب والإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          TextField(
            controller: _fullNameCtrl,
            decoration: const InputDecoration(
              labelText: 'الاسم الكامل',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              border: OutlineInputBorder(),
            ),
          ),

          if (isMechanic) ...[
            const SizedBox(height: 18),
            const Text(
              'إعدادات الورشة والموقع',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              color: const Color(0xFFFFF7ED),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppColors.orange.withValues(alpha: 0.45)),
              ),
              child: ListTile(
                leading: const Icon(Icons.edit_location_alt,
                    color: AppColors.orange, size: 28),
                title: const Text(
                  'تغيير موقع الورشة على الخريطة (GPS)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  _workshopAddressCtrl.text.trim().isNotEmpty
                      ? _workshopAddressCtrl.text.trim()
                      : (_workshopLat != null
                          ? '${_workshopLat!.toStringAsFixed(4)}, ${_workshopLng!.toStringAsFixed(4)}'
                          : 'اضغط لتحديد موقع ورشتك'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _updatingLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_ios,
                        size: 16, color: AppColors.orange),
                onTap: _updatingLocation ? null : _openWorkshopLocationPicker,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _workshopAddressCtrl,
              decoration: const InputDecoration(
                labelText: 'عنوان الورشة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _streetCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشارع',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buildingCtrl,
                    decoration: const InputDecoration(
                      labelText: 'رقم البناية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _openingHoursCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ساعات العمل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _capacityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعة السيارات',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],

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
              onPressed: _saving ? null : _saveProfile,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text(
                'حفظ التعديلات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),

          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 8),

          // زر طلب استرجاع الباقة (24 ساعة فقط)
          if (hasPaidPlan)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.currency_exchange,
                    color: AppColors.navy),
                title: const Text(
                  'طلب استرجاع الباقة (Refund)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'متاح خلال 24 ساعة فقط من تاريخ الاشتراك',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                onTap: _requestSubscriptionRefund,
              ),
            ),

          // زر الشروط والخصوصية وسياسات المنصة (Apple + Uber + الورش + Refund)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.policy_outlined, color: AppColors.navy),
              title: const Text(
                'الشروط والسياسات وخصوصية التطبيق',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'بنود المستخدم والورشة · الاسترجاع 24 ساعة · خصوصية Apple · سياسة الموقع',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => showAppLegalPoliciesSheet(context),
            ),
          ),

          // زر حذف الحساب نهائياً (متطلب إلزامي من Apple)
          Card(
            color: const Color(0xFFFEF2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
            ),
            child: ListTile(
              leading: _deletingAccount
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.red,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'حذف الحساب نهائياً',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'إزالة الحساب والبيانات الشخصية بشكل دائم',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
              onTap: _deletingAccount ? null : _confirmAndDeleteAccount,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4) شاشة الدعم الفني والتواصل
// ============================================================================
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدعم الفني والمساعدة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(Icons.support_agent, color: AppColors.orange, size: 48),
                SizedBox(height: 10),
                Text(
                  'فريق دعم غيارك بخدمتك دائماً',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'تواصل معنا للاستفسار عن الطلبات، المدفوعات، السحب البنكي أو الباقات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat, color: AppColors.success),
              title: const Text('واتساب الدعم المباشر',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(EnvConfig.supportPhone),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => _launch('https://wa.me/${EnvConfig.supportWhatsapp}'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.call, color: AppColors.navy),
              title: const Text('اتصال هاتفي مباشر',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(EnvConfig.supportPhone),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => _launch('tel:${EnvConfig.supportPhone}'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.email_outlined, color: AppColors.orange),
              title: const Text('البريد الإلكتروني الرسمي',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(EnvConfig.supportEmail),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => _launch('mailto:${EnvConfig.supportEmail}'),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.policy_outlined, color: AppColors.navy),
              title: const Text('الشروط والأحكام وسياسة الخصوصية',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('السياسة الكاملة المتوافقة مع Apple و Uber'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => showAppLegalPoliciesSheet(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5) نافذة الشروط والسياسات الكاملة (المستخدم + الورشة + Refund 24h + Apple + Uber)
// ============================================================================
void showAppLegalPoliciesSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Icon(Icons.verified_user, color: AppColors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الشروط والأحكام وسياسة الخصوصية — غيارك',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: const [
                _PolicySection(
                  title: '1. بنود حساب المستخدم العادي',
                  body:
                      '• يلتزم المستخدم بإدخال بيانات صحيحة (الاسم، رقم الهاتف، وموقع السيارة عند طلب الطوارئ أو الحجز).\n'
                      '• جميع عمليات الدفع الإلكتروني تتم عبر بوابة MEPS المرخّصة ولا يُعتمد أي دفع إلا بعد تأكيد البنك رسمياً.\n'
                      '• يحق للمستخدم تقييم الورش ومقدمي الخدمة بصدق وموضوعية بعد انتهاء الخدمة.\n'
                      '• يُمنع إساءة استخدام طلبات الطوارئ أو إرسال طلبات وهمية، ويحتفظ التطبيق بحق تقييد الحساب المخالف.',
                ),
                _PolicySection(
                  title: '2. بنود مقدمي الخدمات (الورش، التجار، الونش) والغرامات',
                  body:
                      '• قفل سعة الورشة: تلتزم كل ورشة بسعتها الاستيعابية المحددة (مثل 5 سيارات). عند امتلاء السعة بطلبات فعالة غير مكتملة، يُقفل استقبال أي طلبات جديدة تلقائياً حتى يتم إنهاء الطلبات القائمة وإصدار فاتورة رسمية.\n'
                      '• مكافحة التلاعب والإلغاءات المتكررة: في حال تجاوز عدد الطلبات الملغية من قبل الورشة عدد الطلبات المنتهية بفاتورة رسمية، يصدر النظام تلقائياً تنبيهاً وإنذاراً على الحساب مع فرض غرامة مالية (5.00 د.أ لكل مخالفة) تُضاف للذمم المستحقة، وتكرار المخالفة يؤدي لتعليق الحساب.\n'
                      '• تتحول أرباح الدفع الإلكتروني إلى محفظة المزود بعد خصم عمولة المنصة، ويمكن طلب سحبها عبر IBAN أو CliQ خلال 24-48 ساعة عمل.',
                ),
                _PolicySection(
                  title: '3. سياسة الاسترجاع للباقات والاشتراكات (Refund Policy)',
                  body:
                      '• يحق للمشترك (مستخدم أو مزود خدمة) طلب استرجاع قيمة الباقة المدفوعة خلال 24 ساعة فقط من لحظة تفعيل الاشتراك.\n'
                      '• بعد مرور 24 ساعة من تاريخ الاشتراك (أو بعد أسبوع)، لا يحق المطالبة باسترجاع قيمة الباقة نهائياً.\n'
                      '• يُرفع طلب الاسترجاع من داخل إعدادات الحساب (الملف الشخصي -> طلب استرجاع الباقة) وتتم معالجته وإعادة المبلغ خلال 3-7 أيام عمل بنكية.',
                ),
                _PolicySection(
                  title: '4. سياسة الخصوصية (متوافقة مع معايير Apple App Store)',
                  body:
                      '• البيانات التي نجمعها: الاسم، البريد الإلكتروني، رقم الهاتف، وصور القطع/الورشة التي يرفعها المستخدم طوعاً.\n'
                      '• أمان الدفع: لا نقوم بحفظ أرقام البطاقات البنكية أو رموز CVV على خوادمنا إطلاقاً؛ تتم المعالجة بالكامل عبر بوابات دفع مشفّرة (PCI-DSS).\n'
                      '• عدم مشاركة البيانات: لا نبيع أو نؤجّر بياناتك الشخصية لأي طرف ثالث لأغراض تسويقية.\n'
                      '• حذف الحساب والبيانات: يمتلك كل مستخدم زر "حذف الحساب نهائياً" داخل صفحة بيانات الحساب لإزالة حسابه وبياناته الشخصية فوراً وفق متطلبات Apple (بشرط عدم وجود ذمم مالية قائمة).',
                ),
                _PolicySection(
                  title: '5. سياسة الموقع الجغرافي (بأسلوب Uber — بدون حفظ سجل)',
                  body:
                      '• نستخدم الموقع الجغرافي (GPS) حصراً لتوصيل أقرب ميكانيكي أو ونش طوارئ إليك وتحديد المسافة والوصول بدقة.\n'
                      '• لا يتم تخزين سجل تاريخي لتحركات السائقين أو المستخدمين؛ يتم استبدال الإحداثي القديم بالإحداثي الجديد مباشرة (Update in-place) في قاعدة البيانات.\n'
                      '• يتوقف التتبع المباشر تلقائياً فور إنهاء أو إلغاء الطلب، ولا يتم تتبع موقعك في الخلفية خارج أوقات الطلب النشط.',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'فهمت وأوافق',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.8,
              height: 1.65,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}