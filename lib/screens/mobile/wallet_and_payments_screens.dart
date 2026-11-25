import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'workshop_checkout_screen.dart';

String _methodLabel(String method) {
  return switch (method.toLowerCase()) {
    'visa' || 'card' || 'mastercard' => 'Visa / Mastercard',
    'apple_pay' => 'Apple Pay',
    'google_pay' => 'Google Pay',
    'cash' => 'نقدي (كاش)',
    'cliq' => 'CliQ',
    'auto_deduct' => 'خصم تلقائي',
    _ => method,
  };
}

String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return '';
  final y = dt.year;
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d · $hh:$mm';
}

List<Map<String, dynamic>> _filterByPeriod(
  List<Map<String, dynamic>> list,
  DashboardPeriod period,
  DateTimeRange? customRange,
) {
  final range = DateRangeFilterBar.resolveRange(period, customRange);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end =
      DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
  return list.where((tx) {
    final dt = DateTime.tryParse((tx['created_at'] ?? '').toString());
    if (dt == null) return true;
    final local = dt.toLocal();
    return !local.isBefore(start) && !local.isAfter(end);
  }).toList();
}

// ============================================================================
// 1) محفظة مقدم الخدمة والعمولات
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
  final _payService = PayTabsPaymentService();

  DashboardPeriod _period = DashboardPeriod.months3;
  DateTimeRange? _customRange;
  bool _loading = true;
  bool _busy = false;
  double _walletBalance = 0.0;
  double _pendingDebt = 0.0;
  List<Map<String, dynamic>> _transactions = [];

  static const Set<String> _deductionTypes = {
    'commission_settlement',
    'commission_auto_deduct',
    'debt_settlement',
    'withdrawal',
  };

  @override
  void initState() {
    super.initState();
    _walletBalance = widget.profile.walletBalance;
    _pendingDebt = widget.profile.pendingCommissionDebt;
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final uid = widget.profile.id;
      final results = await Future.wait<dynamic>([
        _db
            .from('customers')
            .select('wallet_balance, pending_commission_debt')
            .eq('id', uid)
            .maybeSingle(),
        _db
            .from('wallet_transactions')
            .select()
            .eq('provider_id', uid)
            .order('created_at', ascending: false)
            .limit(200),
      ]);
      final customer = results[0] as Map<String, dynamic>?;
      final txs = List<Map<String, dynamic>>.from(results[1] as List);
      if (!mounted) return;
      setState(() {
        _walletBalance =
            (customer?['wallet_balance'] as num?)?.toDouble() ?? _walletBalance;
        _pendingDebt =
            (customer?['pending_commission_debt'] as num?)?.toDouble() ??
                _pendingDebt;
        _transactions = txs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _settleCommissionRpc(String method, String ref) async {
    final variants = [
      {'p_payment_method': method, 'p_reference': ref},
      {'p_method': method, 'p_reference': ref},
      {'p_payment_method': method, 'p_payment_ref': ref},
    ];
    PostgrestException? lastErr;
    for (final params in variants) {
      try {
        await _db.rpc('settle_provider_commission_debt', params: params);
        return;
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        lastErr = e;
      }
    }
    if (lastErr != null) throw lastErr;
  }

  Future<void> _requestWithdrawalRpc({
    required double amount,
    required String method,
    required String accountDetails,
    required String bankName,
    required String accountHolder,
  }) async {
    final variants = [
      {
        'p_amount': amount,
        'p_payout_method': method,
        'p_account_details': accountDetails,
        'p_bank_name': bankName,
        'p_account_holder': accountHolder,
      },
      {
        'p_amount': amount,
        'p_method': method,
        'p_iban_or_cliq': accountDetails,
        'p_bank_name': bankName,
        'p_account_holder': accountHolder,
      },
      {
        'p_amount': amount,
        'p_method': method,
        'p_account_number': accountDetails,
        'p_bank_name': bankName,
        'p_account_name': accountHolder,
      },
    ];
    PostgrestException? lastErr;
    for (final params in variants) {
      try {
        await _db.rpc('request_wallet_withdrawal', params: params);
        return;
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        lastErr = e;
      }
    }
    if (lastErr != null) throw lastErr;
  }

  Future<void> _openPayCommissionSheet() async {
    if (_busy) return;
    setState(() => _busy = true);
    double liveDebt = _pendingDebt;
    try {
      final row = await _db
          .from('customers')
          .select('pending_commission_debt')
          .eq('id', widget.profile.id)
          .maybeSingle();
      liveDebt =
          (row?['pending_commission_debt'] as num?)?.toDouble() ?? liveDebt;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _pendingDebt = liveDebt;
      _busy = false;
    });

    if (liveDebt <= 0.009) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حسابك المالي مسوّى بالكامل ولا توجد عمولة مستحقة ✓'),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.credit_card, color: AppColors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'سداد عمولة المنصة إلكترونياً',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'المبلغ المستحق للدفع:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${liveDebt.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.orange, width: 1.4),
                ),
                child: ListTile(
                  leading: const Icon(Icons.credit_card,
                      color: AppColors.orange, size: 28),
                  title: const Text('Visa / Mastercard',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('الدفع الإلكتروني الآمن بالبطاقة البنكية'),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 16, color: AppColors.orange),
                  onTap: () => Navigator.pop(ctx, 'visa'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: EnvConfig.applePayEnabled
                    ? Colors.white
                    : AppColors.background,
                child: ListTile(
                  leading: const Icon(Icons.apple, size: 30),
                  title: const Text('Apple Pay',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(EnvConfig.applePayEnabled
                      ? 'دفع سريع وآمن عبر Apple Pay'
                      : 'قريباً — يرجى استخدام Visa / Mastercard'),
                  onTap: () {
                    if (EnvConfig.applePayEnabled) {
                      Navigator.pop(ctx, 'apple_pay');
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Apple Pay قيد التفعيل، يرجى استخدام Visa / Mastercard'),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: EnvConfig.googlePayEnabled
                    ? Colors.white
                    : AppColors.background,
                child: ListTile(
                  leading: const Icon(Icons.g_mobiledata, size: 34),
                  title: const Text('Google Pay',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(EnvConfig.googlePayEnabled
                      ? 'دفع سريع وآمن عبر Google Pay'
                      : 'قريباً — يرجى استخدام Visa / Mastercard'),
                  onTap: () {
                    if (EnvConfig.googlePayEnabled) {
                      Navigator.pop(ctx, 'google_pay');
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Google Pay قيد التفعيل، يرجى استخدام Visa / Mastercard'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final paid = await _payService.payWithCardRedirect(
        context: context,
        amount: liveDebt,
        title: 'سداد عمولة منصة غيارك',
        orderType: 'debt',
        referenceId: widget.profile.id,
        email: widget.profile.email,
        phone: widget.profile.phone,
        name: widget.profile.fullName,
      );
      if (!paid || !mounted) return;
      await _settleCommissionRpc(
        chosen,
        '${chosen}_${DateTime.now().millisecondsSinceEpoch}',
      );
      await _loadWalletData();
      widget.onRefreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم سداد العمولة بنجاح وتصفير الرصيد المستحق ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر سداد العمولة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWithdrawDialog() async {
    if (_pendingDebt > 0.009) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'لا يمكنك سحب الأرباح قبل سداد العمولة المستحقة (${_pendingDebt.toStringAsFixed(2)} د.أ) أولاً.',
          ),
        ),
      );
      return;
    }
    if (_walletBalance < 5.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'الحد الأدنى للسحب للبنك هو 5.00 د.أ من أرباح الدفع الإلكتروني (المتاح حالياً: ${_walletBalance.toStringAsFixed(2)} د.أ).',
          ),
        ),
      );
      return;
    }

    final amountCtrl =
        TextEditingController(text: _walletBalance.toStringAsFixed(2));
    final accountCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final holderCtrl =
        TextEditingController(text: widget.profile.fullName ?? '');
    String method = 'cliq';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('سحب الأرباح إلى البنك'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الرصيد المتاح للسحب: ${_walletBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('CliQ (كليك)'),
                      selected: method == 'cliq',
                      onSelected: (_) => setDlg(() => method = 'cliq'),
                    ),
                    ChoiceChip(
                      label: const Text('حوالة IBAN'),
                      selected: method == 'iban',
                      onSelected: (_) => setDlg(() => method = 'iban'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                  controller: accountCtrl,
                  decoration: InputDecoration(
                    labelText: method == 'cliq'
                        ? 'الاسم المستعار (CliQ) أو الهاتف'
                        : 'رقم الـ IBAN',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم البنك',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم صاحب الحساب',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد السحب'),
            ),
          ],
        ),
      ),
    );

    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
    final acc = accountCtrl.text.trim();
    final bank = bankCtrl.text.trim();
    final holder = holderCtrl.text.trim();
    amountCtrl.dispose();
    accountCtrl.dispose();
    bankCtrl.dispose();
    holderCtrl.dispose();

    if (confirmed != true || !mounted) return;
    if (amt < 5.0 || amt > _walletBalance || acc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح (5 د.أ فأكثر) وبيانات الحساب'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _requestWithdrawalRpc(
        amount: amt,
        method: method,
        accountDetails: acc,
        bankName: bank,
        accountHolder: holder,
      );
      await _loadWalletData();
      widget.onRefreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال طلب سحب الأرباح بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إرسال طلب السحب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _txTitle(String type) {
    return switch (type) {
      'workshop_invoice' || 'workshop' => 'فاتورة ورشة صيانة',
      'emergency_invoice' || 'emergency' => 'فاتورة ميكانيكي طوارئ',
      'winch_invoice' || 'winch' => 'فاتورة ونش طوارئ',
      'part_order' || 'order' => 'بيع قطعة غيار',
      'commission_settlement' || 'debt_settlement' => 'سداد عمولة للمنصة',
      'commission_auto_deduct' => 'خصم عمولة كاش تلقائي',
      'withdrawal' => 'طلب سحب أرباح للبنك',
      _ => 'حركة مالية',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtered = _filterByPeriod(_transactions, _period, _customRange);
    double periodGross = 0.0, periodComm = 0.0, periodNet = 0.0;
    for (final tx in filtered) {
      if (_deductionTypes.contains((tx['transaction_type'] as String?) ?? '')) {
        continue;
      }
      periodGross += (tx['gross_amount'] as num?)?.toDouble() ?? 0.0;
      periodComm += (tx['commission_amount'] as num?)?.toDouble() ?? 0.0;
      periodNet += (tx['net_amount'] as num?)?.toDouble() ?? 0.0;
    }
    final hasDebt = _pendingDebt > 0.009;

    return RefreshIndicator(
      onRefresh: _loadWalletData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الرصيد القابل للسحب إلى البنك (إلكتروني)',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_walletBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'صافي أرباح الفترة: ${periodNet.toStringAsFixed(2)} د.أ · قبل العمولة: ${periodGross.toStringAsFixed(2)} · العمولة: ${periodComm.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    onPressed: _busy ? null : _openWithdrawDialog,
                    icon: const Icon(Icons.account_balance),
                    label: const Text(
                      'سحب الأرباح إلى البنك (IBAN / CliQ)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasDebt
                  ? Colors.red.withValues(alpha: 0.05)
                  : AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasDebt
                    ? Colors.red.withValues(alpha: 0.3)
                    : AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: hasDebt
                          ? Colors.red.withValues(alpha: 0.14)
                          : AppColors.success.withValues(alpha: 0.16),
                      child: Icon(
                        hasDebt ? Icons.account_balance : Icons.verified,
                        color: hasDebt ? Colors.red : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasDebt
                                ? 'عمولة مستحقة للتطبيق'
                                : 'لا توجد عمولات مستحقة عليك',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: hasDebt ? Colors.red : AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasDebt
                                ? 'عمولة الطلبات النقدية (كاش) المستحقة للمنصة'
                                : 'حسابك المالي مسوّى بالكامل ✓',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_pendingDebt.toStringAsFixed(2)} د.أ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: hasDebt ? Colors.red : AppColors.success,
                      ),
                    ),
                  ],
                ),
                if (hasDebt) ...[
                  const SizedBox(height: 14),
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
                      onPressed: _busy ? null : _openPayCommissionSheet,
                      icon: const Icon(Icons.credit_card),
                      label: const Text(
                        'دفع العمولة المستحقة الآن',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'سجل الحركات المالية',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text(
                  'لا توجد حركات مالية في هذه الفترة',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...filtered.map((tx) {
              final type = (tx['transaction_type'] as String?) ?? 'order';
              final method = (tx['payment_method'] as String?) ?? 'visa';
              final gross = (tx['gross_amount'] as num?)?.toDouble() ?? 0.0;
              final comm = (tx['commission_amount'] as num?)?.toDouble() ?? 0.0;
              final net = (tx['net_amount'] as num?)?.toDouble() ?? 0.0;
              final isDeduct = _deductionTypes.contains(type) || net < 0;
              final amt = isDeduct
                  ? (net != 0 ? net.abs() : (comm > 0 ? comm : gross))
                  : net;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isDeduct
                          ? Colors.red.withValues(alpha: 0.12)
                          : AppColors.success.withValues(alpha: 0.12),
                      child: Icon(
                        isDeduct ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isDeduct ? Colors.red : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _txTitle(type),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isDeduct
                                ? 'الوسيلة: ${_methodLabel(method)} · المبلغ: ${amt.toStringAsFixed(2)} د.أ'
                                : 'الوسيلة: ${_methodLabel(method)} · قبل العمولة: ${gross.toStringAsFixed(2)} · عمولة: ${comm.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isDeduct ? '-' : '+'}${amt.toStringAsFixed(2)} د.أ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDeduct ? Colors.red : AppColors.success,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ============================================================================
// 2) شاشة المدفوعات وسجل الدفعات للمستخدم العادي + زر دفع الفواتير
// ============================================================================
class _PendingCustomerInvoice {
  final String id;
  final bool isWorkshop;
  final String title;
  final String subtitle;
  final String statusLabel;
  final double amount;
  final IconData icon;
  final Map<String, dynamic> rawMap;

  const _PendingCustomerInvoice({
    required this.id,
    required this.isWorkshop,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.amount,
    required this.icon,
    required this.rawMap,
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
  DashboardPeriod _period = DashboardPeriod.months3;
  DateTimeRange? _customRange;
  bool _loading = true;
  List<_PendingCustomerInvoice> _pendingInvoices = [];
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    try {
      final uid = widget.profile.id;
      final results = await Future.wait<dynamic>([
        _db
            .from('workshop_appointments')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(60),
        _db
            .from('mechanic_requests')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(60),
        _db
            .from('wallet_transactions')
            .select()
            .eq('customer_id', uid)
            .order('created_at', ascending: false)
            .limit(200),
      ]);

      final workshops = List<Map<String, dynamic>>.from(results[0] as List);
      final emergencies = List<Map<String, dynamic>>.from(results[1] as List);
      final txs = List<Map<String, dynamic>>.from(results[2] as List);
      final pending = <_PendingCustomerInvoice>[];

      for (final a in workshops) {
        final status = (a['status'] as String?) ?? 'pending';
        final step = (a['progress_step'] as String?) ?? 'pending';
        final payStatus = (a['payment_status'] as String?) ?? 'unpaid';
        final amount = (a['total_amount'] as num?)?.toDouble() ?? 0.0;
        final wId = (a['workshop_id'] as String?) ?? '';
        final isUnpaid = payStatus != 'paid' &&
            payStatus != 'pending_verification' &&
            status != 'cancelled' &&
            status != 'rejected' &&
            !(status == 'completed' && amount <= 0) &&
            (amount > 0 ||
                step == 'awaiting_payment' ||
                (status == 'accepted' && wId.isNotEmpty));
        if (isUnpaid) {
          final desc = (a['service_description'] as String?)?.trim() ?? '';
          final date = (a['appointment_date'] as String?) ?? '';
          final time = (a['appointment_time'] as String?) ?? '';
          pending.add(_PendingCustomerInvoice(
            id: a['id'] as String,
            isWorkshop: true,
            title: desc.isNotEmpty ? desc : 'فاتورة صيانة ورشة',
            subtitle: date.isNotEmpty
                ? 'موعد الورشة: $date${time.isNotEmpty ? ' · $time' : ''}'
                : 'فاتورة ورشة صيانة',
            statusLabel: step == 'awaiting_payment'
                ? 'السيارة جاهزة — بانتظار الدفع'
                : 'فاتورة مستحقة للدفع',
            amount: amount,
            icon: Icons.build_circle_outlined,
            rawMap: a,
          ));
        }
      }

      for (final e in emergencies) {
        final status = (e['status'] as String?) ?? 'pending';
        final step = (e['progress_step'] as String?) ?? 'pending';
        final payStatus = (e['payment_status'] as String?) ?? 'unpaid';
        final amount = (e['total_amount'] as num?)?.toDouble() ?? 0.0;
        final mId = (e['mechanic_id'] as String?) ?? '';
        final isWinch = ((e['service_type'] as String?) ?? '') == 'winch';
        final isUnpaid = payStatus != 'paid' &&
            payStatus != 'pending_verification' &&
            status != 'cancelled' &&
            status != 'rejected' &&
            !(status == 'completed' && amount <= 0) &&
            (amount > 0 ||
                step == 'awaiting_payment' ||
                (status == 'accepted' && mId.isNotEmpty));
        if (isUnpaid) {
          final desc = (e['description'] as String?)?.trim() ?? '';
          final car = (e['car_details'] as String?)?.trim() ?? '';
          pending.add(_PendingCustomerInvoice(
            id: e['id'] as String,
            isWorkshop: false,
            title: desc.isNotEmpty
                ? desc
                : (isWinch ? 'فاتورة ونش طوارئ' : 'فاتورة ميكانيكي طوارئ'),
            subtitle: car.isNotEmpty
                ? 'المركبة: $car'
                : (isWinch ? 'خدمة سحب ونش مباشر' : 'خدمة طوارئ ميدانية'),
            statusLabel: step == 'awaiting_payment'
                ? 'بانتظار سداد الفاتورة'
                : 'طلب طوارئ نشط',
            amount: amount,
            icon: isWinch
                ? Icons.local_shipping_outlined
                : Icons.car_crash_outlined,
            rawMap: e,
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _pendingInvoices = pending;
        _transactions = txs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openInvoiceCheckout(_PendingCustomerInvoice inv) async {
    final screen = inv.isWorkshop
        ? WorkshopCheckoutScreen(
            appointment: DbWorkshopAppointment.fromMap(inv.rawMap),
            customerProfile: widget.profile,
            onPaymentCompleted: _loadAll,
          )
        : EmergencyCheckoutScreen(
            request: DbMechanicRequest.fromMap(inv.rawMap),
            customerProfile: widget.profile,
            onPaymentCompleted: _loadAll,
          );
    await Navigator.push(context, animatedRoute(screen));
    if (mounted) await _loadAll();
  }

  void _onPayInvoicesButtonTap() {
    if (_pendingInvoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد فواتير مستحقة للدفع حالياً ✓'),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }
    if (_pendingInvoices.length == 1) {
      _openInvoiceCheckout(_pendingInvoices.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اختر الفاتورة للدفع (${_pendingInvoices.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _pendingInvoices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final inv = _pendingInvoices[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.orangeLight,
                        child: Icon(inv.icon, color: AppColors.orange),
                      ),
                      title: Text(inv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        inv.amount > 0
                            ? '${inv.amount.toStringAsFixed(2)} د.أ'
                            : 'إدخال المبلغ عند الدفع',
                        style: const TextStyle(
                          color: AppColors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openInvoiceCheckout(inv);
                        },
                        child: const Text('ادفع'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _txTitle(String type) {
    return switch (type) {
      'workshop_invoice' || 'workshop' => 'دفع فاتورة ورشة صيانة',
      'emergency_invoice' || 'emergency' => 'دفع فاتورة ميكانيكي طوارئ',
      'winch_invoice' || 'winch' => 'دفع فاتورة ونش طوارئ',
      'part_order' || 'order' => 'شراء قطع غيار من المتجر',
      'subscription' => 'اشتراك باقة غيارك',
      _ => 'عملية دفع إلكترونية',
    };
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterByPeriod(_transactions, _period, _customRange);
    final totalPaid = filtered.fold<double>(
      0.0,
      (sum, tx) => sum + ((tx['gross_amount'] as num?)?.toDouble() ?? 0.0),
    );
    final pendingTotal =
        _pendingInvoices.fold<double>(0.0, (sum, inv) => sum + inv.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المدفوعات وسجل الدفعات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إجمالي مدفوعاتك في الفترة المحددة',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${totalPaid.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'العمليات المكتملة: ${filtered.length} · الفواتير غير المدفوعة: ${_pendingInvoices.length}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
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
                            onPressed: _onPayInvoicesButtonTap,
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: Text(
                              _pendingInvoices.isEmpty
                                  ? 'دفع الفواتير المستحقة'
                                  : pendingTotal > 0
                                      ? 'دفع الفواتير المستحقة (${_pendingInvoices.length} · ${pendingTotal.toStringAsFixed(2)} د.أ)'
                                      : 'دفع الفواتير المستحقة (${_pendingInvoices.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'الفواتير المستحقة للدفع',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_pendingInvoices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              color: AppColors.success),
                          SizedBox(width: 10),
                          Text(
                            'لا توجد فواتير غير مدفوعة حالياً ✓',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._pendingInvoices.map(
                      (inv) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.orange.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.orangeLight,
                                  child: Icon(inv.icon, color: AppColors.orange),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(inv.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5)),
                                      Text(inv.subtitle,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary)),
                                    ],
                                  ),
                                ),
                                Text(
                                  inv.amount > 0
                                      ? '${inv.amount.toStringAsFixed(2)} د.أ'
                                      : 'غير محدد',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppColors.orange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    inv.statusLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.orange,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => _openInvoiceCheckout(inv),
                                  icon: const Icon(Icons.payment, size: 18),
                                  label: const Text('دفع الفاتورة الآن',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  DateRangeFilterBar(
                    period: _period,
                    customRange: _customRange,
                    onChanged: (p, r) => setState(() {
                      _period = p;
                      _customRange = r;
                    }),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'سجل المدفوعات السابقة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Text(
                          'لا توجد مدفوعات مسجلة في هذه الفترة',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...filtered.map((tx) {
                      final type =
                          (tx['transaction_type'] as String?) ?? 'order';
                      final method =
                          (tx['payment_method'] as String?) ?? 'visa';
                      final gross =
                          (tx['gross_amount'] as num?)?.toDouble() ?? 0.0;
                      final dateStr = _formatDate(tx['created_at'] as String?);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  AppColors.navy.withValues(alpha: 0.08),
                              child: const Icon(Icons.check_circle_outline,
                                  color: AppColors.success),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_txTitle(type),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  const SizedBox(height: 3),
                                  Text(
                                    'الوسيلة: ${_methodLabel(method)}${dateStr.isNotEmpty ? ' · $dateStr' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${gross.toStringAsFixed(2)} د.أ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
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
// 3) شاشة الملف الشخصي (البروفايل)
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
    try {
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
    } catch (_) {}
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
          SnackBar(content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                borderRadius: BorderRadius.circular(14),
              ),
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

// ============================================================================
// 4) شاشة الدعم الفني والمساعدة
// ============================================================================
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
                Icon(Icons.support_agent_rounded, color: Colors.white, size: 54),
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
                  'mailto:${EnvConfig.supportEmail}?subject=دعم فني تطبيق غيارك',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}