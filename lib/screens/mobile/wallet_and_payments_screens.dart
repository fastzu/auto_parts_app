import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

/// شاشة المحفظة المالية الكاملة (تُستخدم في الـ Drawer وفي لوحات التحكم للتاجر والميكانيكي والونش)
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

  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;

  bool _loadingLiveProfile = false;
  bool _settlingDebt = false;
  bool _submittingWithdraw = false;

  late double _walletBalance = widget.profile.walletBalance;
  late double _pendingDebt = widget.profile.pendingCommissionDebt;

  @override
  void initState() {
    super.initState();
    _refreshLiveNumbers();
  }

  Future<void> _refreshLiveNumbers() async {
    setState(() => _loadingLiveProfile = true);
    try {
      final row = await _db
          .from('customers')
          .select('wallet_balance, pending_commission_debt')
          .eq('id', widget.profile.id)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _walletBalance = (row['wallet_balance'] as num?)?.toDouble() ?? 0.0;
          _pendingDebt =
              (row['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingLiveProfile = false);
    }
  }

  bool _inPeriod(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  /// تسديد العمولات / المخالفات عبر نفس طرق الدفع الموحدة (Visa/Mastercard MEPS + CliQ)
  Future<void> _settlePendingDebt() async {
    if (_pendingDebt <= 0) return;
    setState(() => _settlingDebt = true);
    try {
      final ok = await PayTabsPaymentService().startPaymentFlow(
        context: context,
        baseAmount: _pendingDebt,
        title: _loc.tr('تسوية عمولات ومستحقات المنصة', 'Platform Debt Settlement'),
        orderType: 'debt',
        referenceId: widget.profile.id,
        email: widget.profile.email,
        phone: widget.profile.phone,
        name: widget.profile.fullName,
        userRole: widget.profile.role,
      );
      if (ok) {
        await _refreshLiveNumbers();
        widget.onRefreshProfile();
      }
    } finally {
      if (mounted) setState(() => _settlingDebt = false);
    }
  }

  Future<void> _openWithdrawDialog(double availableBalance) async {
    final amountCtrl =
        TextEditingController(text: availableBalance.toStringAsFixed(2));
    final ibanCtrl = TextEditingController();
    final holderCtrl =
        TextEditingController(text: widget.profile.fullName ?? '');
    String method = 'iban';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_loc.tr('طلب سحب أرباح للبنك', 'Request Bank Payout')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('IBAN')),
                        selected: method == 'iban',
                        selectedColor: AppColors.navy,
                        labelStyle: TextStyle(
                          color: method == 'iban'
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setD(() => method = 'iban'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('CliQ')),
                        selected: method == 'cliq',
                        selectedColor: AppColors.orange,
                        labelStyle: TextStyle(
                          color: method == 'cliq'
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setD(() => method = 'cliq'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _loc.tr('المبلغ المطلوب (د.أ)', 'Amount (JOD)'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holderCtrl,
                  decoration: InputDecoration(
                    labelText: _loc.tr('اسم صاحب الحساب', 'Account Holder Name'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ibanCtrl,
                  decoration: InputDecoration(
                    labelText: method == 'iban'
                        ? _loc.tr('رقم الآيبان (IBAN)', 'IBAN Number')
                        : _loc.tr('الاسم المستعار في CliQ', 'CliQ Alias'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _submittingWithdraw ? null : () => Navigator.pop(ctx),
              child: Text(_loc.tr('إلغاء', 'Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: _submittingWithdraw
                  ? null
                  : () async {
                      final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amt <= 0 || amt > availableBalance) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_loc.tr(
                              'المبلغ غير صالح أو أكبر من الرصيد المتاح',
                              'Invalid amount or exceeds available balance',
                            )),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      if (ibanCtrl.text.trim().isEmpty) return;

                      setState(() => _submittingWithdraw = true);
                      setD(() {});
                      try {
                        await _db.from('wallet_transactions').insert({
                          'provider_id': widget.profile.id,
                          'transaction_type': 'withdrawal_request',
                          'payment_method': method,
                          'gross_amount': amt,
                          'commission_rate': 0,
                          'commission_amount': 0,
                          'net_amount': -amt,
                          'status': 'pending',
                          'notes':
                              '${holderCtrl.text.trim()} | ${ibanCtrl.text.trim()}',
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_loc.tr(
                                'تم إرسال طلب سحب الأرباح وسيتم التحويل خلال 24-48 ساعة ✓',
                                'Withdrawal request submitted (24-48h processing) ✓',
                              )),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('$e'),
                                backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _submittingWithdraw = false);
                      }
                    },
              child: Text(_loc.tr('إرسال طلب السحب', 'Submit Payout')),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    ibanCtrl.dispose();
    holderCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _loc.langCode,
      builder: (context, _) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('wallet_transactions')
              .stream(primaryKey: ['id'])
              .eq('provider_id', widget.profile.id)
              .order('created_at', ascending: false)
              .limit(100),
          builder: (context, snap) {
            final allTxs =
                (snap.data ?? []).map(DbWalletTransaction.fromMap).toList();
            final periodTxs = (snap.data ?? [])
                .where((t) => _inPeriod(t['created_at'] as String?))
                .map(DbWalletTransaction.fromMap)
                .toList();

            final gross = periodTxs
                .where((t) => t.transactionType != 'withdrawal_request')
                .fold(0.0, (s, t) => s + t.grossAmount);
            final comm = periodTxs
                .where((t) => t.transactionType != 'withdrawal_request')
                .fold(0.0, (s, t) => s + t.commissionAmount);
            final netPeriod = periodTxs.fold(0.0, (s, t) => s + t.netAmount);
            final effectiveBalance =
                _walletBalance > 0 ? _walletBalance : mathMaxZero(netPeriod);

            return RefreshIndicator(
              color: AppColors.orange,
              onRefresh: _refreshLiveNumbers,
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

                  // البطاقة الرئيسية للرصيد والسحب
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.navy, Color(0xFF1F2D3D)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.navy.withValues(alpha: 0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _loc.tr(
                                'صافي الرصيد القابل للسحب',
                                'Available Wallet Balance',
                              ),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            if (_loadingLiveProfile)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${effectiveBalance.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _loc.tr(
                            'إجمالي الفترة: ${gross.toStringAsFixed(2)} د.أ  |  العمولات: ${comm.toStringAsFixed(2)} د.أ',
                            'Period Gross: ${gross.toStringAsFixed(2)} JOD  |  Fees: ${comm.toStringAsFixed(2)} JOD',
                          ),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.orange,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: effectiveBalance >= 5
                                    ? () => _openWithdrawDialog(effectiveBalance)
                                    : null,
                                icon: const Icon(Icons.account_balance_rounded,
                                    size: 18),
                                label: Text(_loc.tr(
                                  'سحب الأرباح (IBAN / CliQ)',
                                  'Withdraw (IBAN / CliQ)',
                                )),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // بطاقة العمولات / المخالفات المستحقة (تظهر فقط إن كانت > 0)
                  if (_pendingDebt > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _loc.tr(
                                    'مستحقات / عمولات مطلوبة للتسوية',
                                    'Pending Commissions / Dues',
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                              ),
                              Text(
                                '${_pendingDebt.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed:
                                  _settlingDebt ? null : _settlePendingDebt,
                              icon: const Icon(Icons.payment_rounded, size: 18),
                              label: Text(_loc.tr(
                                'تسديد الآن (Visa / Mastercard / CliQ)',
                                'Settle Now (Visa / Mastercard / CliQ)',
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _loc.tr('سجل الحركات المالية', 'Financial Transactions'),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                      Text(
                        '${periodTxs.length} ${_loc.tr("حركة", "items")}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (periodTxs.isEmpty && allTxs.isEmpty)
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
                              size: 40, color: AppColors.textSecondary),
                          const SizedBox(height: 8),
                          Text(
                            _loc.tr(
                              'لا توجد حركات مالية مسجلة حتى الآن',
                              'No financial transactions recorded yet',
                            ),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  else
                    ...periodTxs.map((t) {
                      final isDebit = t.netAmount < 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDebit
                                ? Colors.orange.withValues(alpha: 0.14)
                                : AppColors.success.withValues(alpha: 0.14),
                            child: Icon(
                              isDebit
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              color:
                                  isDebit ? AppColors.orange : AppColors.success,
                            ),
                          ),
                          title: Text(
                            '${_txTypeLabel(t.transactionType)} · ${_methodLabel(t.paymentMethod)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          subtitle: Text(
                            _loc.tr(
                              'الإجمالي: ${t.grossAmount.toStringAsFixed(2)} | العمولة: ${t.commissionAmount.toStringAsFixed(2)} د.أ',
                              'Gross: ${t.grossAmount.toStringAsFixed(2)} | Fee: ${t.commissionAmount.toStringAsFixed(2)} JOD',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Text(
                            '${t.netAmount >= 0 ? "+" : ""}${t.netAmount.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                            style: TextStyle(
                              color: isDebit
                                  ? AppColors.orange
                                  : AppColors.success,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double mathMaxZero(double v) => v < 0 ? 0.0 : v;

  String _txTypeLabel(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => _loc.tr('بيع قطعة غيار', 'Part Sale'),
        'workshop' || 'appointment' => _loc.tr('خدمة ورشة', 'Workshop Service'),
        'winch_towing' || 'winch' || 'emergency' =>
          _loc.tr('خدمة طوارئ / ونش', 'Emergency / Tow'),
        'debt' => _loc.tr('تسديد عمولات', 'Commission Settlement'),
        'withdrawal_request' => _loc.tr('طلب سحب أرباح', 'Payout Request'),
        _ => raw,
      };

  String _methodLabel(String raw) => switch (raw.toLowerCase()) {
        'visa' || 'card' || 'meps' => 'Visa / Mastercard',
        'cliq' => 'CliQ',
        'cash' => _loc.tr('نقداً', 'Cash'),
        'iban' => 'IBAN',
        _ => raw,
      };
}

/// سجل المدفوعات والفواتير للزبون العادي
class CustomerPaymentsHistoryScreen extends StatelessWidget {
  final CustomerProfile profile;
  const CustomerPaymentsHistoryScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final loc = AppLocaleService.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('المدفوعات وسجل الدفعات', 'Payment History')),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: db
            .from('wallet_transactions')
            .stream(primaryKey: ['id'])
            .eq('customer_id', profile.id)
            .order('created_at', ascending: false)
            .limit(80),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final txs = snap.data!.map(DbWalletTransaction.fromMap).toList();
          if (txs.isEmpty) {
            return Center(
              child: Text(loc.tr(
                'لا توجد مدفوعات سابقة حتى الآن',
                'No past payments found',
              )),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: txs.length,
            itemBuilder: (_, i) {
              final t = txs[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.orangeLight,
                    child: Icon(Icons.receipt_long, color: AppColors.orange),
                  ),
                  title: Text(
                    '${t.transactionType} · ${t.paymentMethod.toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(t.createdAt.toString().substring(0, 16)),
                  trailing: Text(
                    '${t.grossAmount.toStringAsFixed(2)} ${loc.tr("د.أ", "JOD")}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// شاشة البروفايل الشخصي + زر "تحويل إلى حساب تاجر" للمستخدم العادي
class UserProfileScreen extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onSaved;
  final VoidCallback? onSignedOut;

  const UserProfileScreen({
    super.key,
    required this.profile,
    required this.onSaved,
    this.onSignedOut,
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
  bool _upgradingToMerchant = false;

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
          SnackBar(
            content: Text(_loc.tr(
              'تم تحديث معلومات البروفايل بنجاح ✓',
              'Profile updated successfully ✓',
            )),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// تحويل الحساب العادي (user) إلى حساب تاجر (merchant)
  Future<void> _upgradeToMerchant() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_loc.tr('تحويل إلى حساب تاجر', 'Switch to Merchant Account')),
        content: Text(_loc.tr(
          'سيتم تحويل حسابك فوراً إلى حساب تاجر قطع غيار، لتتمكن من نشر قطع الغيار، الوصول للوحة المنتجات، والمحفظة المالية والباقات. هل تريد المتابعة؟',
          'Your account will immediately switch to a Parts Merchant account so you can list spare parts, access the merchant dashboard, wallet, and plans. Continue?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_loc.tr('إلغاء', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_loc.tr('نعم، حوّل حسابي لتاجر', 'Yes, Switch Now')),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _upgradingToMerchant = true);
    try {
      try {
        await _db.rpc('upgrade_current_user_to_merchant');
      } catch (_) {
        await _db
            .from('customers')
            .update({'role': 'merchant'})
            .eq('id', widget.profile.id);
      }
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'مبروك! تم تحويل حسابك إلى حساب تاجر بنجاح ✓',
              'Congratulations! Your account is now a Merchant account ✓',
            )),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('تعذر تحويل الحساب: $e', 'Switch failed: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _upgradingToMerchant = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final isNormalUser = p.role == 'user' && !p.isAdmin;

    return ListenableBuilder(
      listenable: _loc.langCode,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('ملفي الشخصي (البروفايل)', 'My Profile')),
          ),
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
                      '${_loc.tr("اسم المستخدم:", "Username:")} @${p.username ?? "-"}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      '${_loc.tr("البريد الإلكتروني:", "Email:")} ${p.email ?? "-"}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      '${_loc.tr("نوع الحساب:", "Account Type:")} ${p.role}',
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_country != null || _age != null)
                      Text(
                        '${_loc.tr("الدولة:", "Country:")} ${_country ?? "-"}  |  ${_loc.tr("العمر:", "Age:")} ${_age ?? "-"}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
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
                  _loc.tr(
                    'ساعات الدوام: ${p.openingHours} · السعة: ${p.maxCarCapacity} سيارة/يوم',
                    'Hours: ${p.openingHours} · Capacity: ${p.maxCarCapacity} cars/day',
                  ),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
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
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        _loc.tr('حفظ التعديلات', 'Save Changes'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),

              // خيار تحويل المستخدم العادي إلى حساب تاجر
              if (isNormalUser) ...[
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.orange.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.storefront_rounded,
                              color: AppColors.orange, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _loc.tr(
                                'هل لديك قطع غيار للبيع؟',
                                'Want to sell spare parts?',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _loc.tr(
                          'حوّل حسابك بضغطة زر إلى حساب تاجر لفتح لوحة المنتجات والمحفظة المالية والوصول لآلاف المشترين.',
                          'Switch to a Merchant account in one tap to list spare parts, unlock the merchant dashboard, and manage your wallet.',
                        ),
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed:
                              _upgradingToMerchant ? null : _upgradeToMerchant,
                          icon: _upgradingToMerchant
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.swap_horiz_rounded),
                          label: Text(
                            _loc.tr(
                              'تحويل إلى حساب تاجر',
                              'Switch to Merchant Account',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// شاشة الدعم الفني
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    return ListenableBuilder(
      listenable: loc.langCode,
      builder: (context, _) {
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
                        'We are here to assist you around the clock',
                      ),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
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
                  onTap: () =>
                      launchUrl(Uri.parse('tel:${EnvConfig.supportPhone}')),
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
                  leading:
                      const Icon(Icons.email_outlined, color: AppColors.navy),
                  title: Text(loc.tr('البريد الإلكتروني', 'Email Support'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(EnvConfig.supportEmail),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () => launchUrl(
                    Uri.parse(
                        'mailto:${EnvConfig.supportEmail}?subject=Ghiyarak Support'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.policy_outlined,
                      color: AppColors.orange),
                  title: Text(
                    loc.tr('الشروط والأحكام وسياسة الخصوصية',
                        'Terms & Privacy Policy'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () => showAppLegalPoliciesSheet(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// نافذة الشروط والأحكام وسياسة الخصوصية والاسترجاع (بالعربية والإنجليزية)
void showAppLegalPoliciesSheet(BuildContext context) {
  final loc = AppLocaleService.instance;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Text(
            loc.tr(
              'الشروط والأحكام وسياسة الخصوصية — غيارك',
              'Terms, Privacy & Refund Policy — Ghiyarak',
            ),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.navy),
          ),
          const SizedBox(height: 14),
          _policyBlock(
            loc.tr('1. شروط الاستخدام', '1. Terms of Use'),
            loc.tr(
              'يُستخدم تطبيق غيارك لربط مالكي المركبات بتجار قطع الغيار والورش ومزودي الطوارئ والونش داخل الأردن. لا يجوز إلغاء الفاتورة بعد إصدارها النهائي من مزود الخدمة.',
              'Ghiyarak connects vehicle owners with spare parts merchants, workshops, and roadside/towing providers in Jordan. Finalized invoices cannot be cancelled once issued.',
            ),
          ),
          _policyBlock(
            loc.tr('2. سياسة الاسترجاع (24 ساعة)', '2. 24-Hour Refund Policy'),
            loc.tr(
              'يمكن طلب استرجاع رسوم الباقات والاشتراكات خلال 24 ساعة من تاريخ الدفع عبر التواصل مع الدعم الفني، بشرط عدم استهلاك مزايا الباقة.',
              'Subscription payments may be refunded within 24 hours of purchase by contacting support, provided plan benefits have not been consumed.',
            ),
          ),
          _policyBlock(
            loc.tr('3. خصوصية الموقع الجغرافي (Zero-History)',
                '3. Location Privacy (Zero-History)'),
            loc.tr(
              'يُستخدم موقعك الجغرافي فقط لتحديد موقعك أثناء طلب الطوارئ أو توجيه المزود، ولا يتم الاحتفاظ بسجل تحركات تاريخي بعد انتهاء الطلب.',
              'Your GPS location is used strictly for live emergency dispatching and active routing. No historical location trail is retained after order completion.',
            ),
          ),
          _policyBlock(
            loc.tr('4. أمان المدفوعات', '4. Payment Security'),
            loc.tr(
              'تتم جميع عمليات الدفع بالبطاقات عبر بوابة MEPS المشفرة ولا يقوم تطبيق غيارك بتخزين بيانات بطاقتك الائتمانية.',
              'All card payments are processed via encrypted MEPS gateways; Ghiyarak never stores your credit card details.',
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _policyBlock(String title, String body) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.orange),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: const TextStyle(
              color: AppColors.navy, fontSize: 13, height: 1.45),
        ),
      ],
    ),
  );
}