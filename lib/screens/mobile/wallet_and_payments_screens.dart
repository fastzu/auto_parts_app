import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/commission_payment_sheet.dart';
import 'workshop_checkout_screen.dart';

class ProviderWalletView extends StatefulWidget {
  final CustomerProfile? profile;
  final VoidCallback? onRefreshProfile;
  final String title;
  final bool showAppBar;

  const ProviderWalletView({
    super.key,
    this.profile,
    this.onRefreshProfile,
    this.title = 'محفظتي والعمولات',
    this.showAppBar = false,
  });

  @override
  State<ProviderWalletView> createState() => _ProviderWalletViewState();
}

class _ProviderWalletViewState extends State<ProviderWalletView> {
  final _db = Supabase.instance.client;
  final _loc = AppLocaleService.instance;

  DashboardPeriod _period = DashboardPeriod.months3;
  DateTimeRange? _customRange;
  bool _loading = true;
  double _walletBalance = 0.0;
  double _pendingDebt = 0.0;
  double _commissionRate = 0.15;
  List<DbWalletTransaction> _transactions = [];
  List<Map<String, dynamic>> _withdrawals = [];

  static const _jordanBanks = [
    'البنك العربي (Arab Bank)',
    'بنك الإسكان للتجارة والتمويل',
    'بنك الاتحاد (Bank al Etihad)',
    'البنك الإسلامي الأردني',
    'بنك القاهرة عمان',
    'بنك الأردن (Bank of Jordan)',
    'البنك الأردني الكويتي',
    'البنك الأهلي الأردني',
    'بنك صفوة الإسلامي',
    'بنك الاستثمار العربي الأردني (AJIB)',
    'بنك المال الأردني (Capital Bank)',
    'محفظة إلكترونية (ZainCash / Orange Money / UWallet)',
  ];

  @override
  void initState() {
    super.initState();
    _walletBalance = widget.profile?.walletBalance ?? 0.0;
    _pendingDebt = widget.profile?.pendingCommissionDebt ?? 0.0;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final uid = widget.profile?.id ?? _db.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    try {
      final profileRow = await _db
          .from('customers')
          .select('wallet_balance, pending_commission_debt, commission_rate')
          .eq('id', uid)
          .maybeSingle();

      final txRows = await _db
          .from('wallet_transactions')
          .select()
          .eq('provider_id', uid)
          .order('created_at', ascending: false)
          .limit(200);

      List<Map<String, dynamic>> withdrawRows = [];
      try {
        final wr = await _db
            .from('withdrawal_requests')
            .select()
            .eq('provider_id', uid)
            .order('created_at', ascending: false)
            .limit(30);
        withdrawRows = List<Map<String, dynamic>>.from(wr);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _walletBalance =
            (profileRow?['wallet_balance'] as num?)?.toDouble() ?? 0.0;
        _pendingDebt =
            (profileRow?['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;
        _commissionRate =
            (profileRow?['commission_rate'] as num?)?.toDouble() ?? 0.15;
        _transactions = (txRows as List)
            .map((e) => DbWalletTransaction.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        _withdrawals = withdrawRows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DbWalletTransaction> get _filteredTransactions {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(
        range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return _transactions
        .where((t) =>
            !t.createdAt.isBefore(start) && !t.createdAt.isAfter(end))
        .toList();
  }

  bool _isEarningType(String type) {
    return type != 'commission_settlement' &&
        type != 'commission_auto_deduct' &&
        type != 'withdrawal';
  }

  void _showSnack(
    String msg, {
    Color bg = AppColors.navy,
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: bg,
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        action: action,
      ),
    );
  }

  Future<void> _openWithdrawSheet() async {
    // 1) منع السحب تماماً إذا كان على المزود أي عمولة كاش غير مدفوعة
    if (_pendingDebt > 0.009) {
      _showSnack(
        _loc.tr(
          'لا يمكنك سحب الأرباح قبل تسديد العمولة المستحقة عليك (${_pendingDebt.toStringAsFixed(2)} د.أ) أولاً',
          'You cannot withdraw before settling your due commission (${_pendingDebt.toStringAsFixed(2)} JOD) first',
        ),
        bg: Colors.red.shade700,
        action: SnackBarAction(
          label: _loc.tr('سدد الآن', 'Pay Now'),
          textColor: Colors.white,
          onPressed: () async {
            final paid = await showCommissionPaymentSheet(
              context,
              debtAmount: _pendingDebt,
              walletBalance: _walletBalance,
            );
            if (paid) {
              widget.onRefreshProfile?.call();
              _loadAll();
            }
          },
        ),
      );
      return;
    }

    // 2) التحقق من الحد الأدنى للسحب
    if (_walletBalance < 5.0) {
      _showSnack(
        _loc.tr(
          'الحد الأدنى للسحب للبنك هو 5.00 د.أ من أرباح الدفع الإلكتروني بعد العمولة (المتاح حالياً: ${_walletBalance.toStringAsFixed(2)} د.أ).',
          'Minimum bank withdrawal is 5.00 JOD from net online earnings (available: ${_walletBalance.toStringAsFixed(2)} JOD).',
        ),
        bg: Colors.red.shade700,
      );
      return;
    }

    final amountCtrl =
        TextEditingController(text: _walletBalance.toStringAsFixed(2));
    final holderCtrl = TextEditingController();
    final ibanCtrl = TextEditingController();
    String payoutMethod = 'iban';
    String selectedBank = _jordanBanks.first;
    bool submitting = false;

    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _loc.tr('سحب الأرباح إلى حسابك البنكي',
                      'Withdraw Earnings to Bank'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _loc.tr(
                    'صافي الرصيد الجاهز للتحويل (بعد خصم العمولة): ${_walletBalance.toStringAsFixed(2)} د.أ',
                    'Net withdrawable balance (after commission): ${_walletBalance.toStringAsFixed(2)} JOD',
                  ),
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'iban',
                      label: Text(_loc.tr('حوالة IBAN', 'IBAN')),
                    ),
                    const ButtonSegment(
                      value: 'cliq',
                      label: Text('CliQ'),
                    ),
                    ButtonSegment(
                      value: 'ewallet',
                      label: Text(_loc.tr('محفظة', 'E-Wallet')),
                    ),
                  ],
                  selected: {payoutMethod},
                  onSelectionChanged: (s) =>
                      setSheet(() => payoutMethod = s.first),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedBank,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _loc.tr('اسم البنك / المحفظة', 'Bank / Wallet'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _jordanBanks
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(b, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSheet(() => selectedBank = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        _loc.tr('المبلغ المطلوب سحبه (د.أ)', 'Amount (JOD)'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: holderCtrl,
                  decoration: InputDecoration(
                    labelText: _loc.tr(
                        'اسم صاحب الحساب البنكي بالكامل', 'Account Holder Name'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ibanCtrl,
                  decoration: InputDecoration(
                    labelText: payoutMethod == 'iban'
                        ? _loc.tr('رقم الآيبان (JO...)', 'IBAN (JO...)')
                        : payoutMethod == 'cliq'
                            ? _loc.tr(
                                'الاسم المستعار (CliQ Alias) أو رقم الهاتف',
                                'CliQ Alias or Phone')
                            : _loc.tr('رقم هاتف المحفظة الإلكترونية',
                                'E-Wallet Phone Number'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
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
                          final amt =
                              double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                          if (amt < 5.0 || amt > _walletBalance) {
                            _showSnack(
                              _loc.tr(
                                'أدخل مبلغاً بين 5.00 و ${_walletBalance.toStringAsFixed(2)} د.أ',
                                'Enter an amount between 5.00 and ${_walletBalance.toStringAsFixed(2)} JOD',
                              ),
                              bg: Colors.red,
                            );
                            return;
                          }
                          if (holderCtrl.text.trim().isEmpty ||
                              ibanCtrl.text.trim().isEmpty) {
                            _showSnack(
                              _loc.tr('يرجى تعبئة اسم صاحب الحساب ورقم الحساب',
                                  'Please fill in account holder and IBAN/Alias'),
                              bg: Colors.red,
                            );
                            return;
                          }

                          setSheet(() => submitting = true);
                          try {
                            await _db.rpc('request_wallet_withdrawal', params: {
                              'p_amount': amt,
                              'p_payout_method': payoutMethod,
                              'p_bank_name': selectedBank,
                              'p_account_holder': holderCtrl.text.trim(),
                              'p_iban_or_alias': ibanCtrl.text.trim(),
                            });
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            setSheet(() => submitting = false);
                            _showSnack(
                              e.toString().replaceFirst('Exception: ', ''),
                              bg: Colors.red,
                            );
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.account_balance),
                  label: Text(
                    _loc.tr('إرسال طلب التحويل البنكي',
                        'Submit Bank Withdrawal Request'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    amountCtrl.dispose();
    holderCtrl.dispose();
    ibanCtrl.dispose();

    if (done == true) {
      _showSnack(
        _loc.tr(
          'تم إرسال طلب سحب الأرباح بنجاح ✓ سيتم تحويل المبلغ لحسابك البنكي قريباً',
          'Withdrawal request submitted ✓ Funds will be transferred shortly',
        ),
        bg: AppColors.success,
      );
      widget.onRefreshProfile?.call();
      _loadAll();
    }
  }

  String _txTitle(String type) {
    return switch (type) {
      'emergency_mechanic' =>
        _loc.tr('فاتورة ميكانيكي طوارئ', 'Emergency Mechanic Invoice'),
      'emergency_winch' =>
        _loc.tr('فاتورة ونش طوارئ', 'Emergency Winch Invoice'),
      'workshop_invoice' =>
        _loc.tr('فاتورة صيانة ورشة', 'Workshop Maintenance Invoice'),
      'part_order' => _loc.tr('بيع قطعة غيار', 'Spare Part Sale'),
      'commission_settlement' =>
        _loc.tr('سداد عمولة للمنصة', 'Platform Commission Payment'),
      'commission_auto_deduct' => _loc.tr(
          'خصم تلقائي لعمولة كاش سابقة', 'Auto-Deducted Prior Cash Commission'),
      'withdrawal' => _loc.tr('سحب أرباح إلى البنك', 'Bank Withdrawal'),
      _ => _loc.tr('حركة مالية', 'Financial Transaction'),
    };
  }

  String _methodLabel(String method) {
    return switch (method.toLowerCase()) {
      'cash' => _loc.tr('كاش', 'Cash'),
      'visa' || 'card' => 'Visa / Mastercard',
      'apple_pay' => 'Apple Pay',
      'google_pay' => 'Google Pay',
      'cliq' => 'CliQ',
      'iban' => 'IBAN',
      'ewallet' => _loc.tr('محفظة إلكترونية', 'E-Wallet'),
      _ => method,
    };
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTransactions;
    // استثناء حركات سداد العمولة والخصم التلقائي والسحب من إجمالي أرباح الفترة حتى لا تتضاعف العمولة
    final earningRows =
        filtered.where((t) => _isEarningType(t.transactionType)).toList();

    final periodGross =
        earningRows.fold<double>(0.0, (s, t) => s + t.grossAmount);
    final periodCommission =
        earningRows.fold<double>(0.0, (s, t) => s + t.commissionAmount);
    final periodNet = earningRows.fold<double>(0.0, (s, t) => s + t.netAmount);
    final commPct = (_commissionRate * 100).toStringAsFixed(1);

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
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

                // البطاقة الرئيسية للأرباح والرصيد القابل للسحب
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.navy, Color(0xFF1A283A)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _loc.tr(
                                'صافي الرصيد المتاح للسحب (بعد العمولة)',
                                'Net Withdrawable Balance (After Commission)',
                              ),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _loc.tr('عمولتك $commPct%', 'Rate $commPct%'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_walletBalance.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // شريط تفصيل أرباح الفترة (صافي الأرباح / قبل العمولة / العمولة)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _metricCell(
                                label:
                                    _loc.tr('صافي أرباح الفترة', 'Period Net'),
                                value: periodNet.toStringAsFixed(2),
                                color: const Color(0xFF4ADE80),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              color: Colors.white24,
                            ),
                            Expanded(
                              child: _metricCell(
                                label: _loc.tr('قبل العمولة', 'Gross'),
                                value: periodGross.toStringAsFixed(2),
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              color: Colors.white24,
                            ),
                            Expanded(
                              child: _metricCell(
                                label: _loc.tr('العمولة', 'Commission'),
                                value: periodCommission.toStringAsFixed(2),
                                color: const Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_walletBalance <= 0 && periodNet > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          _loc.tr(
                            'ملاحظة: أرباح الكاش استلمتها مباشرة من العميل. فقط مدفوعات البطاقة تُضاف هنا صافية بعد خصم العمولة للسحب إلى بنكك.',
                            'Note: Cash earnings were collected directly. Only card payments accumulate here (net after commission) for bank withdrawal.',
                          ),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pendingDebt > 0.009
                              ? Colors.grey.shade700
                              : AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _openWithdrawSheet,
                        icon: Icon(
                          _pendingDebt > 0.009
                              ? Icons.lock_outline
                              : Icons.account_balance,
                          size: 19,
                        ),
                        label: Text(
                          _pendingDebt > 0.009
                              ? _loc.tr(
                                  'سدّد عمولة الكاش أولاً لتفعيل السحب',
                                  'Pay Cash Commission First to Withdraw',
                                )
                              : _loc.tr(
                                  'سحب الأرباح إلى البنك (IBAN / CliQ)',
                                  'Withdraw to Bank (IBAN / CliQ)',
                                ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // بطاقة العمولة المستحقة (Visa / Apple Pay / Google Pay فقط)
                CommissionDebtCard(
                  debtAmount: _pendingDebt,
                  walletBalance: _walletBalance,
                  onSettled: () {
                    widget.onRefreshProfile?.call();
                    _loadAll();
                  },
                ),

                if (_withdrawals.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    _loc.tr('طلبات السحب البنكي', 'Bank Withdrawal Requests'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._withdrawals.map((w) {
                    final status = (w['status'] as String?) ?? 'pending';
                    final amount = (w['amount'] as num?)?.toDouble() ?? 0.0;
                    final statusColor = status == 'paid'
                        ? AppColors.success
                        : status == 'rejected'
                            ? Colors.red
                            : AppColors.orange;
                    final statusText = status == 'paid'
                        ? _loc.tr('تم التحويل ✓', 'Transferred ✓')
                        : status == 'rejected'
                            ? _loc.tr('مرفوض (أُعيد للرصيد)', 'Rejected')
                            : _loc.tr('قيد التحويل البنكي', 'Processing');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withValues(alpha: 0.14),
                          child: Icon(Icons.account_balance,
                              color: statusColor, size: 20),
                        ),
                        title: Text(
                          '${amount.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')} · ${w['bank_name'] ?? ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          '${w['account_holder'] ?? ''} · ${w['iban_or_alias'] ?? ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 20),
                Text(
                  _loc.tr('سجل الحركات المالية', 'Transactions History'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 34),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Text(
                        _loc.tr('لا توجد حركات مالية خلال هذه الفترة',
                            'No financial transactions in this period'),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ...filtered.map((t) {
                    final isDeduction = !_isEarningType(t.transactionType);
                    final displayAmt = isDeduction
                        ? (t.netAmount != 0 ? t.netAmount.abs() : t.grossAmount)
                        : t.netAmount;
                    final amountText = isDeduction
                        ? '-${displayAmt.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}'
                        : '+${displayAmt.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}';
                    final amountColor =
                        isDeduction ? Colors.red.shade700 : AppColors.success;

                    final subtitleText = isDeduction
                        ? _loc.tr(
                            'الوسيلة: ${_methodLabel(t.paymentMethod)} · المبلغ: ${displayAmt.toStringAsFixed(2)} د.أ',
                            'Method: ${_methodLabel(t.paymentMethod)} · Amount: ${displayAmt.toStringAsFixed(2)} JOD',
                          )
                        : _loc.tr(
                            'الوسيلة: ${_methodLabel(t.paymentMethod)} · قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} · عمولة: ${t.commissionAmount.toStringAsFixed(2)}',
                            'Method: ${_methodLabel(t.paymentMethod)} · Gross: ${t.grossAmount.toStringAsFixed(2)} · Comm: ${t.commissionAmount.toStringAsFixed(2)}',
                          );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                amountColor.withValues(alpha: 0.12),
                            child: Icon(
                              isDeduction
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              color: amountColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _txTitle(t.transactionType),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.navy,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitleText,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            amountText,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              color: amountColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          );

    if (!widget.showAppBar) return content;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: content,
    );
  }

  Widget _metricCell({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 10.5),
        ),
        const SizedBox(height: 3),
        Text(
          '$value ${_loc.tr('د.أ', 'JOD')}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

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
        final workshopId = (a['workshop_id'] as String?) ?? '';

        final isUnpaid = payStatus != 'paid' &&
            payStatus != 'pending_verification' &&
            status != 'cancelled' &&
            status != 'rejected' &&
            !(status == 'completed' && amount <= 0) &&
            (amount > 0 ||
                step == 'awaiting_payment' ||
                (status == 'accepted' && workshopId.isNotEmpty));

        if (isUnpaid) {
          final desc = (a['service_description'] as String?)?.trim() ?? '';
          final date = (a['appointment_date'] as String?) ?? '';
          final time = (a['appointment_time'] as String?) ?? '';
          pending.add(
            _PendingCustomerInvoice(
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
            ),
          );
        }
      }

      for (final e in emergencies) {
        final status = (e['status'] as String?) ?? 'pending';
        final step = (e['progress_step'] as String?) ?? 'pending';
        final payStatus = (e['payment_status'] as String?) ?? 'unpaid';
        final amount = (e['total_amount'] as num?)?.toDouble() ?? 0.0;
        final mechanicId = (e['mechanic_id'] as String?) ?? '';
        final serviceType = (e['service_type'] as String?) ?? 'mechanic';
        final isWinch = serviceType == 'winch';

        final isUnpaid = payStatus != 'paid' &&
            payStatus != 'pending_verification' &&
            status != 'cancelled' &&
            status != 'rejected' &&
            !(status == 'completed' && amount <= 0) &&
            (amount > 0 ||
                step == 'awaiting_payment' ||
                (status == 'accepted' && mechanicId.isNotEmpty));

        if (isUnpaid) {
          final desc = (e['description'] as String?)?.trim() ?? '';
          final car = (e['car_details'] as String?)?.trim() ?? '';
          pending.add(
            _PendingCustomerInvoice(
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
            ),
          );
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
    final Widget screen = inv.isWorkshop
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
    if (mounted) {
      await _loadAll();
    }
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اختر الفاتورة المراد دفعها (${_pendingInvoices.length})',
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
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _pendingInvoices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final inv = _pendingInvoices[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.orangeLight,
                            child: Icon(inv.icon, color: AppColors.orange),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inv.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  inv.amount > 0
                                      ? '${inv.amount.toStringAsFixed(2)} د.أ'
                                      : 'إدخال المبلغ عند الدفع',
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openInvoiceCheckout(inv);
                            },
                            child: const Text(
                              'ادفع الآن',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
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

  List<Map<String, dynamic>> get _filteredTransactions {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end =
        DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

    return _transactions.where((tx) {
      final dt = DateTime.tryParse((tx['created_at'] ?? '').toString());
      if (dt == null) return true;
      final local = dt.toLocal();
      return !local.isBefore(start) && !local.isAfter(end);
    }).toList();
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

  String _methodLabel(String method) {
    return switch (method.toLowerCase()) {
      'visa' || 'card' || 'mastercard' => 'Visa / Mastercard',
      'apple_pay' => 'Apple Pay',
      'google_pay' => 'Google Pay',
      'cash' => 'نقدي (كاش)',
      'cliq' => 'CliQ',
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTransactions;
    final totalPaid = filtered.fold<double>(
      0.0,
      (sum, tx) => sum + ((tx['gross_amount'] as num?)?.toDouble() ?? 0.0),
    );
    final pendingTotal = _pendingInvoices.fold<double>(
      0.0,
      (sum, inv) => sum + inv.amount,
    );

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
                            color: Colors.white70,
                            fontSize: 12,
                          ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الفواتير المستحقة للدفع',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      if (_pendingInvoices.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_pendingInvoices.length} فاتورة',
                            style: const TextStyle(
                              color: AppColors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
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
                          Expanded(
                            child: Text(
                              'لا توجد فواتير غير مدفوعة حالياً ✓',
                              style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
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
                                      Text(
                                        inv.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        inv.subtitle,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
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
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => _openInvoiceCheckout(inv),
                                  icon: const Icon(Icons.payment, size: 18),
                                  label: const Text(
                                    'دفع الفاتورة الآن',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
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
                    onChanged: (p, r) {
                      setState(() {
                        _period = p;
                        _customRange = r;
                      });
                    },
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
                        vertical: 32,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.receipt_outlined,
                            size: 42,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'لا توجد مدفوعات مسجلة في هذه الفترة',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
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
                              child: const Icon(
                                Icons.check_circle_outline,
                                color: AppColors.success,
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
                                      fontSize: 14,
                                    ),
                                  ),
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
  final _loc = AppLocaleService.instance;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.fullName ?? '');
    _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.profile.workshopAddress ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _db.from('customers').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'workshop_address': _addressCtrl.text.trim(),
      }).eq('id', widget.profile.id);
      widget.onSaved();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
          content: Text(_loc.tr('تم تحديث البيانات بنجاح ✓', 'Profile updated ✓')),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            content: Text('$e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_loc.tr('الملف الشخصي', 'My Profile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: _loc.tr('الاسم الكامل', 'Full Name'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: _loc.tr('رقم الهاتف', 'Phone Number'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: InputDecoration(
              labelText: _loc.tr('العنوان / المنطقة', 'Address / Area'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _loc.tr('حفظ التعديلات', 'Save Changes'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}
