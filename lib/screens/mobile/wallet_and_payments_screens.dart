import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
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
  final _loc = AppLocaleService.instance;

  DashboardPeriod _period = DashboardPeriod.months3;
  DateTimeRange? _customRange;

  StreamSubscription<List<Map<String, dynamic>>>? _txSub;
  StreamSubscription<List<Map<String, dynamic>>>? _custSub;

  List<DbWalletTransaction> _transactions = [];
  List<Map<String, dynamic>> _withdrawals = [];
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

      List<Map<String, dynamic>> wdRows = [];
      try {
        final res = await _db
            .from('withdrawal_requests')
            .select()
            .eq('provider_id', widget.profile.id)
            .order('created_at', ascending: false);
        wdRows = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

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
        _withdrawals = wdRows;
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
              _transactions = rows.map(DbWalletTransaction.fromMap).toList();
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

  void _showTopToast(String title, String message, {bool isError = false}) {
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

  Future<void> _openWithdrawToBankSheet() async {
    if (_storedWalletBalance < 5.0) {
      _showTopToast(
        _loc.tr('الرصيد القابل للسحب غير كافٍ', 'Insufficient Balance'),
        _loc.tr(
          'الحد الأدنى للسحب للبنك هو 5.00 د.أ من أرباح الدفع الإلكتروني (المتاح حالياً: ${_storedWalletBalance.toStringAsFixed(2)} د.أ).',
          'Minimum withdrawal is 5.00 JOD (Available: ${_storedWalletBalance.toStringAsFixed(2)} JOD).',
        ),
        isError: true,
      );
      return;
    }

    final amountCtrl =
        TextEditingController(text: _storedWalletBalance.toStringAsFixed(2));
    final holderCtrl =
        TextEditingController(text: widget.profile.fullName ?? '');
    final ibanCtrl = TextEditingController();
    String payoutMethod = 'bank_iban';
    String selectedBank = 'البنك العربي (Arab Bank)';
    bool submitting = false;

    const jordanBanks = [
      'البنك العربي (Arab Bank)',
      'بنك الاتحاد (Bank al Etihad)',
      'بنك الإسكان (Housing Bank)',
      'البنك الإسلامي الأردني',
      'بنك الأردن (Bank of Jordan)',
      'بنك القاهرة عمان',
      'بنك صفوة الإسلامي',
      'البنك الأردني الكويتي',
      'كابيتال بنك (Capital Bank)',
      'محفظة إلكترونية (Zain Cash / Orange Money)',
    ];

    final done = await showModalBottomSheet<bool>(
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
                const SizedBox(height: 16),
                Text(
                  _loc.tr('سحب الأرباح إلى حسابك البنكي',
                      'Withdraw Earnings to Bank'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loc.tr(
                    'الرصيد المتاح للسحب: ${_storedWalletBalance.toStringAsFixed(2)} د.أ (الحد الأدنى 5.00 د.أ)',
                    'Available balance: ${_storedWalletBalance.toStringAsFixed(2)} JOD (Min 5.00 JOD)',
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(_loc.tr('تحويل بنكي IBAN', 'Bank IBAN')),
                      selected: payoutMethod == 'bank_iban',
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(
                        color: payoutMethod == 'bank_iban'
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) =>
                          setS(() => payoutMethod = 'bank_iban'),
                    ),
                    ChoiceChip(
                      label: Text(_loc.tr('تحويل CliQ', 'CliQ')),
                      selected: payoutMethod == 'cliq',
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(
                        color: payoutMethod == 'cliq'
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) => setS(() => payoutMethod = 'cliq'),
                    ),
                    ChoiceChip(
                      label: Text(_loc.tr('محفظة إلكترونية', 'E-Wallet')),
                      selected: payoutMethod == 'ewallet',
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(
                        color: payoutMethod == 'ewallet'
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) => setS(() => payoutMethod = 'ewallet'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _loc.tr('المبلغ المراد سحبه (د.أ)', 'Amount (JOD)'),
                    prefixIcon: const Icon(Icons.attach_money),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedBank,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _loc.tr('البنك / المحفظة', 'Bank / Wallet'),
                    prefixIcon: const Icon(Icons.account_balance),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  items: jordanBanks
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setS(() => selectedBank = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holderCtrl,
                  decoration: InputDecoration(
                    labelText: _loc.tr(
                        'اسم صاحب الحساب البنكي', 'Account Holder Name'),
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ibanCtrl,
                  decoration: InputDecoration(
                    labelText: payoutMethod == 'bank_iban'
                        ? _loc.tr('رقم الـ IBAN', 'IBAN Number')
                        : payoutMethod == 'cliq'
                            ? _loc.tr('الاسم المستعار (Alias) أو رقم الهاتف على CliQ',
                                'CliQ Alias or Phone')
                            : _loc.tr('رقم المحفظة الإلكترونية', 'E-Wallet Phone'),
                    hintText: payoutMethod == 'bank_iban'
                        ? 'JO94 CBJO 0010 0000 0000 0131 0003 02'
                        : '079XXXXXXX',
                    prefixIcon: const Icon(Icons.numbers),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
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
                    onPressed: submitting
                        ? null
                        : () async {
                            final amt =
                                double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                            if (amt < 5.0 || amt > _storedWalletBalance + 0.01) {
                              _showTopToast(
                                _loc.tr('مبلغ غير صالح', 'Invalid Amount'),
                                _loc.tr(
                                  'أدخل مبلغاً بين 5.00 و ${_storedWalletBalance.toStringAsFixed(2)} د.أ',
                                  'Enter between 5.00 and ${_storedWalletBalance.toStringAsFixed(2)} JOD',
                                ),
                                isError: true,
                              );
                              return;
                            }
                            if (holderCtrl.text.trim().isEmpty ||
                                ibanCtrl.text.trim().isEmpty) {
                              _showTopToast(
                                _loc.tr('بيانات ناقصة', 'Missing Fields'),
                                _loc.tr(
                                  'يرجى إدخال اسم صاحب الحساب ورقم الـ IBAN أو CliQ',
                                  'Please enter account holder and IBAN/CliQ',
                                ),
                                isError: true,
                              );
                              return;
                            }

                            setS(() => submitting = true);
                            try {
                              await _db.rpc(
                                'request_wallet_withdrawal',
                                params: {
                                  'p_amount': amt,
                                  'p_payout_method': payoutMethod,
                                  'p_bank_name': selectedBank,
                                  'p_account_holder_name':
                                      holderCtrl.text.trim(),
                                  'p_iban_or_alias': ibanCtrl.text.trim(),
                                },
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              setS(() => submitting = false);
                              _showTopToast(
                                _loc.tr('تعذر إرسال الطلب', 'Request Failed'),
                                '$e',
                                isError: true,
                              );
                            }
                          },
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.account_balance_rounded),
                    label: Text(
                      _loc.tr('تأكيد طلب التحويل للبنك',
                          'Submit Bank Withdrawal'),
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
        ),
      ),
    );

    amountCtrl.dispose();
    holderCtrl.dispose();
    ibanCtrl.dispose();

    if (done == true && mounted) {
      _showTopToast(
        _loc.tr('تم تقديم طلب السحب ✓', 'Withdrawal Requested ✓'),
        _loc.tr(
          'سيتم تحويل المبلغ لحسابك البنكي خلال 1-2 يوم عمل وإشعارك فور التحويل.',
          'Funds will be transferred to your bank within 1-2 business days.',
        ),
      );
      await _loadInitial();
      widget.onRefreshProfile();
    }
  }

  bool _inPeriod(DateTime dt) {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  String _txLabel(String type) => switch (type) {
        'workshop' => _loc.tr('فاتورة صيانة ورشة', 'Workshop Invoice'),
        'emergency' || 'emergency_mechanic' =>
          _loc.tr('فاتورة ميكانيكي طوارئ', 'Emergency Mechanic Invoice'),
        'winch' || 'emergency_winch' =>
          _loc.tr('فاتورة ونش سحب', 'Towing Invoice'),
        'commission_settlement' =>
          _loc.tr('سداد عمولة للمنصة', 'Commission Settlement'),
        'withdrawal' => _loc.tr('سحب أرباح للبنك', 'Bank Withdrawal'),
        'subscription' => _loc.tr('اشتراك باقة', 'Plan Subscription'),
        _ => _loc.tr('حركة مالية ($type)', 'Transaction ($type)'),
      };

  String _wdStatusLabel(String status) => switch (status) {
        'paid' => _loc.tr('تم التحويل للبنك ✓', 'Transferred ✓'),
        'rejected' => _loc.tr('مرفوض (أُعيد للرصيد)', 'Rejected'),
        _ => _loc.tr('قيد المراجعة والتحويل', 'Pending Transfer'),
      };

  @override
  Widget build(BuildContext context) {
    final filtered =
        _transactions.where((t) => _inPeriod(t.createdAt)).toList();

    final txGross = filtered.fold<double>(0.0, (s, t) => s + t.grossAmount);
    final txComm = filtered.fold<double>(0.0, (s, t) => s + t.commissionAmount);
    final txNet = filtered.fold<double>(0.0, (s, t) => s + t.netAmount);

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
                Text(
                  _loc.tr(
                    'الرصيد القابل للسحب إلى البنك (إلكتروني)',
                    'Withdrawable Balance (Online)',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_storedWalletBalance.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _loc.tr(
                    'إجمالي أرباح الفترة: ${txNet.toStringAsFixed(2)} د.أ · قبل العمولة: ${txGross.toStringAsFixed(2)} · العمولة: ${txComm.toStringAsFixed(2)}',
                    'Period Net: ${txNet.toStringAsFixed(2)} JOD · Gross: ${txGross.toStringAsFixed(2)} · Fees: ${txComm.toStringAsFixed(2)}',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _openWithdrawToBankSheet,
                    icon: const Icon(Icons.account_balance_rounded, size: 19),
                    label: Text(
                      _loc.tr('سحب الأرباح إلى البنك (IBAN / CliQ)',
                          'Withdraw to Bank (IBAN / CliQ)'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          CommissionDebtCard(
            debtAmount: _commissionDebt,
            walletBalance: _storedWalletBalance,
            onPayTap: () async {
              final settled = await showCommissionPaymentSheet(
                context: context,
                profile: widget.profile,
                debtAmount: _commissionDebt,
                walletBalance: _storedWalletBalance,
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

          if (_withdrawals.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _loc.tr('طلبات السحب إلى البنك', 'Bank Withdrawal Requests'),
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            ..._withdrawals.map((w) {
              final st = (w['status'] as String?) ?? 'pending';
              final amt = (w['amount'] as num?)?.toDouble() ?? 0.0;
              final color = st == 'paid'
                  ? AppColors.success
                  : (st == 'rejected' ? Colors.red : AppColors.orange);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.14),
                    child: Icon(Icons.account_balance, color: color, size: 20),
                  ),
                  title: Text(
                    '${w['bank_name'] ?? 'تحويل بنكي'} · ${amt.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '${w['iban_or_alias'] ?? ''}\n${_wdStatusLabel(st)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  isThreeLine: true,
                ),
              );
            }),
          ],

          const SizedBox(height: 18),
          Text(
            _loc.tr('سجل الحركات المالية', 'Transactions History'),
            style: const TextStyle(
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
              child: Center(
                child: Text(
                  _loc.tr('لا توجد حركات مالية ضمن هذه الفترة',
                      'No transactions in this period'),
                  style: const TextStyle(color: AppColors.textSecondary),
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
                    '${_loc.tr('الوسيلة', 'Method')}: ${t.paymentMethod} · ${_loc.tr('قبل العمولة', 'Gross')}: ${t.grossAmount.toStringAsFixed(2)} · ${_loc.tr('عمولة', 'Fee')}: ${t.commissionAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Text(
                    '${t.netAmount >= 0 ? '+' : ''}${t.netAmount.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}',
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
  final _loc = AppLocaleService.instance;
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
          subtitle:
              '${_loc.tr('طريقة الدفع', 'Method')}: ${_methodArabic(raw['payment_method'] as String?)}',
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
          title: _loc.tr('فاتورة ورشة صيانة', 'Workshop Invoice'),
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
          title: isWinch
              ? _loc.tr('فاتورة ونش طوارئ', 'Tow Invoice')
              : _loc.tr('فاتورة ميكانيكي طوارئ', 'Emergency Mechanic Invoice'),
          subtitle: (e['description'] as String?) ??
              (e['car_details'] as String? ?? ''),
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
        'workshop' => _loc.tr('فاتورة ورشة صيانة', 'Workshop Invoice'),
        'emergency' || 'emergency_mechanic' =>
          _loc.tr('فاتورة ميكانيكي طوارئ', 'Mechanic Invoice'),
        'winch' || 'emergency_winch' =>
          _loc.tr('فاتورة ونش سحب', 'Tow Invoice'),
        'subscription' => _loc.tr('اشتراك عضوية', 'Membership'),
        _ => _loc.tr('دفعة إلكترونية', 'Online Payment'),
      };

  String _methodArabic(String? method) => switch ((method ?? '').toLowerCase()) {
        'visa' || 'card' => 'Visa / Mastercard',
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'cash' => _loc.tr('نقداً (كاش)', 'Cash'),
        'wallet' => _loc.tr('المحفظة', 'Wallet'),
        _ => _loc.tr('دفع إلكتروني', 'Online Payment'),
      };

  @override
  Widget build(BuildContext context) {
    final totalPaid = _records
        .where((r) => r.status == 'paid' || r.status == 'completed')
        .fold<double>(0.0, (s, r) => s + r.amount);

    return Scaffold(
      appBar: AppBar(
          title: Text(_loc.tr('المدفوعات وسجل الدفعات', 'Payment History'))),
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
                  Text(
                    _loc.tr('إجمالي مدفوعاتك المكتملة', 'Total Completed Payments'),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${totalPaid.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _loc.tr('عدد الفواتير المسجلة: ${_records.length}',
                        'Invoices: ${_records.length}'),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
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
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 46, color: AppColors.textSecondary),
                    const SizedBox(height: 10),
                    Text(
                      _loc.tr('لا توجد مدفوعات أو فواتير مسجلة حتى الآن',
                          'No payments or invoices yet'),
                      style: const TextStyle(color: AppColors.textSecondary),
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
                          '${r.amount.toStringAsFixed(2)} ${_loc.tr('د.أ', 'JOD')}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isPaid
                              ? _loc.tr('مدفوعة ✓', 'Paid ✓')
                              : _loc.tr('غير مدفوعة', 'Unpaid'),
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
    final loc = AppLocaleService.instance;
    return Scaffold(
      appBar: AppBar(
          title: Text(loc.tr('الدعم الفني — غيارك', 'Support — Ghiyarak'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const GhiyarakLogo(size: 62),
                const SizedBox(height: 12),
                Text(
                  loc.tr('فريق دعم غيارك', 'Ghiyarak Support Team'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.tr(
                    'نحن هنا لمساعدتك في أي استفسار أو مشكلة تقنية على مدار الساعة',
                    'We are here 24/7 to help with any questions or issues',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone, color: AppColors.orange),
              title: Text(loc.tr('الاتصال الهاتفي', 'Phone Call'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(EnvConfig.supportPhone),
              trailing: const Icon(Icons.arrow_forward_ios, size: 15),
              onTap: () => launchUrl(Uri.parse('tel:${EnvConfig.supportPhone}')),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat, color: AppColors.success),
              title: Text(loc.tr('واتساب الدعم الفني', 'WhatsApp Support'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
              title: Text(loc.tr('البريد الإلكتروني', 'Email'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
  final _loc = AppLocaleService.instance;
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
          _loc.tr('تم التحديث بنجاح', 'Profile Updated'),
          _loc.tr('تم حفظ معلومات البروفايل بنجاح.', 'Your changes are saved.'),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showTopNotice(_loc.tr('تعذر التحديث', 'Update Failed'), '$e',
          isError: true);
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
      appBar:
          AppBar(title: Text(_loc.tr('ملفي الشخصي (البروفايل)', 'My Profile'))),
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
                  p.fullName ?? _loc.tr('المستخدم', 'User'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_loc.tr('اسم المستخدم', 'Username')}: @${p.username ?? "-"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  '${_loc.tr('البريد الإلكتروني', 'Email')}: ${p.email ?? "-"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  '${_loc.tr('نوع الحساب', 'Account')}: ${p.role}',
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
                            ? _loc.tr(
                                'التقييم: ${p.ratingAvg.toStringAsFixed(1)} / 5 (${p.ratingCount} تقييم)',
                                'Rating: ${p.ratingAvg.toStringAsFixed(1)} / 5 (${p.ratingCount})',
                              )
                            : _loc.tr('لا توجد تقييمات بعد', 'No ratings yet'),
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
                    '${_loc.tr('الدولة', 'Country')}: ${_country ?? "-"}  |  ${_loc.tr('العمر', 'Age')}: ${_age ?? "-"}',
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
              labelText: _loc.tr('الاسم الكامل', 'Full Name'),
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
              labelText: _loc.tr('رقم الهاتف', 'Phone Number'),
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
                labelText: _loc.tr('عنوان الورشة', 'Workshop Address'),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_loc.tr('ساعات الدوام', 'Hours')}: ${p.openingHours} · ${_loc.tr('السعة', 'Capacity')}: ${p.maxCarCapacity}',
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
                : Text(
                    _loc.tr('حفظ التعديلات', 'Save Changes'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}