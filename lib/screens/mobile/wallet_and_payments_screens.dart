import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../services/notifications_service.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

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

  late double _walletBalance = widget.profile.walletBalance;
  late double _pendingDebt = widget.profile.pendingCommissionDebt;
  double _minWithdrawal = 20.0;

  List<DbWalletTransaction> _allTransactions = [];
  bool _loading = true;
  bool _settlingDebt = false;

  StreamSubscription<List<Map<String, dynamic>>>? _txSub;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSub;

  @override
  void initState() {
    super.initState();
    _loadWalletData();
    _startRealtimeListeners();
  }

  @override
  void didUpdateWidget(covariant ProviderWalletView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _txSub?.cancel();
      _profileSub?.cancel();
      _walletBalance = widget.profile.walletBalance;
      _pendingDebt = widget.profile.pendingCommissionDebt;
      _loadWalletData();
      _startRealtimeListeners();
    }
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  void _startRealtimeListeners() {
    final uid = widget.profile.id;

    _txSub = _db
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('provider_id', uid)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            final parsed = rows.map(DbWalletTransaction.fromMap).toList();
            setState(() {
              _allTransactions = parsed;
              _loading = false;
            });
          },
          onError: (_) {
            // لا نمسح البيانات المخزنة في حال انقطاع مؤقت للاتصال
          },
        );

    _profileSub = _db
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .listen(
          (rows) {
            if (!mounted || rows.isEmpty) return;
            final row = rows.first;
            setState(() {
              _walletBalance =
                  (row['wallet_balance'] as num?)?.toDouble() ?? _walletBalance;
              _pendingDebt =
                  (row['pending_commission_debt'] as num?)?.toDouble() ??
                      _pendingDebt;
            });
          },
          onError: (_) {},
        );
  }

  Future<void> _loadWalletData() async {
    final uid = widget.profile.id;
    try {
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
            .order('created_at', ascending: false),
        _db
            .from('system_settings')
            .select('value')
            .eq('key', 'min_withdrawal_amount')
            .maybeSingle(),
      ]);

      final custRow = results[0] as Map<String, dynamic>?;
      final txRows = (results[1] as List<dynamic>? ?? [])
          .map((e) => DbWalletTransaction.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final minSetting = results[2] as Map<String, dynamic>?;
      final parsedMin =
          double.tryParse((minSetting?['value'] as String?)?.trim() ?? '');

      if (!mounted) return;
      setState(() {
        if (custRow != null) {
          _walletBalance =
              (custRow['wallet_balance'] as num?)?.toDouble() ?? _walletBalance;
          _pendingDebt =
              (custRow['pending_commission_debt'] as num?)?.toDouble() ??
                  _pendingDebt;
        }
        _allTransactions = txRows;
        if (parsedMin != null && parsedMin > 0) {
          _minWithdrawal = parsedMin;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _inPeriod(DateTime dt) {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
    );
    return !dt.isBefore(start) && !dt.isAfter(end);
  }

  /// تمييز حركات الأرباح الحقيقية عن حركات تسديد العمولة أو السحب حتى لا تتخربط الأرقام
  bool _isNonEarningTx(DbWalletTransaction t) {
    final type = t.transactionType.trim().toLowerCase();
    return type == 'commission_settlement' ||
        type == 'debt_settlement' ||
        type == 'debt' ||
        type == 'cliq_payment' ||
        type == 'withdrawal' ||
        type == 'payout' ||
        type.contains('settlement') ||
        type.contains('withdraw');
  }

  String _txTitle(DbWalletTransaction t) {
    final type = t.transactionType.trim().toLowerCase();
    if (type == 'commission_settlement' ||
        type == 'debt_settlement' ||
        type == 'debt' ||
        type.contains('settlement')) {
      return 'تسديد عمولة مستحقة';
    }
    if (type == 'withdrawal' || type == 'payout' || type.contains('withdraw')) {
      return 'سحب أرباح من المحفظة';
    }
    if (type.contains('winch')) return 'طلب ونش طوارئ';
    if (type.contains('emergency') || type.contains('mechanic')) {
      return 'طلب ميكانيكي طوارئ';
    }
    if (type.contains('workshop') || type.contains('appointment')) {
      return 'صيانة ورشة';
    }
    if (type.contains('part') || type == 'order') return 'بيع قطعة غيار';
    return 'حركة مالية';
  }

  String _methodLabel(String method) {
    return switch (method.trim().toLowerCase()) {
      'visa' || 'card' || 'meps' => 'Visa / Mastercard',
      'apple_pay' => 'Apple Pay',
      'google_pay' => 'Google Pay',
      'cliq' => 'CliQ',
      'cash' => 'كاش',
      'iban' => 'تحويل بنكي IBAN',
      _ => method,
    };
  }

  Future<void> _settleCommissionDebt() async {
    if (_settlingDebt || _pendingDebt <= 0.009) return;
    final amountToPay = double.parse(_pendingDebt.toStringAsFixed(2));

    setState(() => _settlingDebt = true);
    try {
      final paid = await PayTabsPaymentService().startPaymentFlow(
        context: context,
        baseAmount: amountToPay,
        title: 'تسديد عمولات مستحقة للمنصة',
        orderType: 'debt',
        referenceId: widget.profile.id,
        email: widget.profile.email,
        phone: widget.profile.phone,
        name: widget.profile.fullName,
        userRole: widget.profile.role,
      );

      if (!paid || !mounted) return;

      final methodUsed = PayTabsPaymentService.lastChosenMethod ?? 'cliq';

      // 1) تصفير الذمم المستحقة على الحساب فوراً في قاعدة البيانات
      final freshCust = await _db
          .from('customers')
          .select('pending_commission_debt')
          .eq('id', widget.profile.id)
          .maybeSingle();
      final currentDbDebt =
          (freshCust?['pending_commission_debt'] as num?)?.toDouble() ??
              amountToPay;
      final remainingDebt =
          double.parse((currentDbDebt - amountToPay).clamp(0.0, 999999.0).toStringAsFixed(2));

      await _db
          .from('customers')
          .update({'pending_commission_debt': remainingDebt})
          .eq('id', widget.profile.id);

      // 2) تسجيل حركة التسديد بدون التأثير على إجمالي الطلبات أو صافي الأرباح
      try {
        await _db.from('wallet_transactions').insert({
          'provider_id': widget.profile.id,
          'customer_id': widget.profile.id,
          'reference_id': widget.profile.id,
          'transaction_type': 'commission_settlement',
          'payment_method': methodUsed,
          'gross_amount': 0.0,
          'commission_rate': 0.0,
          'commission_amount': amountToPay,
          'net_amount': 0.0,
          'status': 'completed',
        });
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _pendingDebt = remainingDebt;
      });
      widget.onRefreshProfile();
      await _loadWalletData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسديد العمولة المستحقة بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تسديد العمولة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _settlingDebt = false);
    }
  }

  Future<void> _showWithdrawDialog() async {
    if (_walletBalance < _minWithdrawal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الحد الأدنى للسحب هو ${_minWithdrawal.toStringAsFixed(2)} د.أ',
          ),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }

    final amountCtrl =
        TextEditingController(text: _walletBalance.toStringAsFixed(2));
    final accountCtrl = TextEditingController();
    String withdrawMethod = 'cliq';
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('سحب الأرباح (IBAN / CliQ)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('CliQ')),
                        selected: withdrawMethod == 'cliq',
                        selectedColor: AppColors.navy,
                        labelStyle: TextStyle(
                          color: withdrawMethod == 'cliq'
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setD(() => withdrawMethod = 'cliq'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('IBAN')),
                        selected: withdrawMethod == 'iban',
                        selectedColor: AppColors.navy,
                        labelStyle: TextStyle(
                          color: withdrawMethod == 'iban'
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) => setD(() => withdrawMethod = 'iban'),
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
                    labelText: 'المبلغ المطلوب سحبه (د.أ)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: accountCtrl,
                  decoration: InputDecoration(
                    labelText: withdrawMethod == 'cliq'
                        ? 'الاسم المستعار أو رقم الهاتف (CliQ)'
                        : 'رقم الحساب البنكي (IBAN)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final acc = accountCtrl.text.trim();
                      if (amt < _minWithdrawal || amt > _walletBalance) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'أدخل مبلغاً بين ${_minWithdrawal.toStringAsFixed(2)} و ${_walletBalance.toStringAsFixed(2)} د.أ',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      if (acc.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال بيانات الحساب'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setD(() => submitting = true);
                      try {
                        final newBalance = double.parse(
                          (_walletBalance - amt).clamp(0.0, 999999.0).toStringAsFixed(2),
                        );
                        await _db
                            .from('customers')
                            .update({'wallet_balance': newBalance})
                            .eq('id', widget.profile.id);

                        await _db.from('wallet_transactions').insert({
                          'provider_id': widget.profile.id,
                          'customer_id': widget.profile.id,
                          'reference_id': acc,
                          'transaction_type': 'withdrawal',
                          'payment_method': withdrawMethod,
                          'gross_amount': 0.0,
                          'commission_rate': 0.0,
                          'commission_amount': 0.0,
                          'net_amount': -amt,
                          'status': 'pending',
                        });

                        // إشعار الأدمن بطلب السحب
                        try {
                          final admins = await _db
                              .from('customers')
                              .select('id')
                              .eq('role', 'admin')
                              .limit(10);
                          for (final a in (admins as List)) {
                            final adminId = a['id'] as String?;
                            if (adminId != null) {
                              await NotificationsService.instance
                                  .sendNotification(
                                targetUserId: adminId,
                                title: 'طلب سحب أرباح جديد',
                                body:
                                    '${widget.profile.fullName ?? "مزود"} طلب سحب ${amt.toStringAsFixed(2)} د.أ عبر ${withdrawMethod.toUpperCase()} ($acc)',
                                type: 'withdrawal_request',
                                referenceId: widget.profile.id,
                              );
                            }
                          }
                        } catch (_) {}

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          setState(() => _walletBalance = newBalance);
                          widget.onRefreshProfile();
                          await _loadWalletData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم إرسال طلب سحب الأرباح بنجاح ✓'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setD(() => submitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تعذر إرسال الطلب: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('تأكيد السحب'),
            ),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    accountCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final periodTxs =
        _allTransactions.where((t) => _inPeriod(t.createdAt)).toList();

    // حساب الأرباح والعمولات من الطلبات الفعلية فقط (بدون حركات تسديد العمولة أو السحب)
    final earningTxs = periodTxs.where((t) => !_isNonEarningTx(t)).toList();
    final gross = earningTxs.fold<double>(0.0, (s, t) => s + t.grossAmount);
    final comm = earningTxs.fold<double>(0.0, (s, t) => s + t.commissionAmount);
    final periodNet = earningTxs.fold<double>(
      0.0,
      (s, t) => s + (t.netAmount > 0 ? t.netAmount : (t.grossAmount - t.commissionAmount)),
    );

    return RefreshIndicator(
      onRefresh: _loadWalletData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
          const SizedBox(height: 14),

          // بطاقة الرصيد الرئيسية
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
                  'صافي الرصيد القابل للسحب',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_walletBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'إجمالي الفترة: ${gross.toStringAsFixed(2)} د.أ  |  العمولات: ${comm.toStringAsFixed(2)} د.أ  |  الصافي: ${periodNet.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    onPressed: _showWithdrawDialog,
                    icon: const Icon(Icons.account_balance, size: 20),
                    label: const Text(
                      'سحب الأرباح (IBAN / CliQ)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // بطاقة العمولات المستحقة للتسوية (تختفي تلقائياً فور التصفير)
          if (_pendingDebt > 0.009) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFDC2626),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'مستحقات / عمولات مطلوبة للتسوية',
                          style: TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      Text(
                        '${_pendingDebt.toStringAsFixed(2)} د.أ',
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _settlingDebt ? null : _settleCommissionDebt,
                      icon: _settlingDebt
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.credit_card, size: 19),
                      label: const Text(
                        'تسديد الآن',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // عنوان سجل الحركات المالية
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'سجل الحركات المالية',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              Text(
                '${periodTxs.length} حركة',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_loading && _allTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (periodTxs.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 46,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'لا توجد حركات مالية مسجلة حتى الآن',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            ...periodTxs.map((t) {
              final isNonEarning = _isNonEarningTx(t);
              final isWithdrawal =
                  t.transactionType.toLowerCase().contains('withdraw') ||
                      t.transactionType.toLowerCase() == 'payout';
              final isSettlement = isNonEarning && !isWithdrawal;

              final displayNet = isWithdrawal
                  ? t.netAmount
                  : isSettlement
                      ? -t.commissionAmount
                      : (t.netAmount > 0
                          ? t.netAmount
                          : (t.grossAmount - t.commissionAmount));

              final dateStr =
                  '${t.createdAt.year}-${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')}';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSettlement
                        ? AppColors.orangeLight
                        : isWithdrawal
                            ? Colors.blue.withValues(alpha: 0.12)
                            : AppColors.success.withValues(alpha: 0.12),
                    child: Icon(
                      isSettlement
                          ? Icons.verified_outlined
                          : isWithdrawal
                              ? Icons.account_balance
                              : Icons.payments_outlined,
                      color: isSettlement
                          ? AppColors.orange
                          : isWithdrawal
                              ? AppColors.navy
                              : AppColors.success,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '${_txTitle(t)} · ${_methodLabel(t.paymentMethod)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    isSettlement
                        ? 'تسديد عمولة مستحقة · $dateStr'
                        : isWithdrawal
                            ? 'طلب سحب أرباح · $dateStr'
                            : 'المبلغ: ${t.grossAmount.toStringAsFixed(2)} د.أ | العمولة: -${t.commissionAmount.toStringAsFixed(2)} د.أ · $dateStr',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Text(
                    '${displayNet >= 0 ? '+' : ''}${displayNet.toStringAsFixed(2)} د.أ',
                    style: TextStyle(
                      color: isSettlement
                          ? AppColors.orange
                          : displayNet >= 0
                              ? AppColors.success
                              : Colors.red,
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
  }
}

class CustomerPaymentsHistoryScreen extends StatefulWidget {
  final CustomerProfile profile;

  const CustomerPaymentsHistoryScreen({
    super.key,
    required this.profile,
  });

  @override
  State<CustomerPaymentsHistoryScreen> createState() =>
      _CustomerPaymentsHistoryScreenState();
}

class _CustomerPaymentsHistoryScreenState
    extends State<CustomerPaymentsHistoryScreen> {
  final _db = Supabase.instance.client;
  List<DbWalletTransaction> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _db
          .from('wallet_transactions')
          .select()
          .eq('customer_id', widget.profile.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items = (rows as List)
            .map((e) =>
                DbWalletTransaction.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل مدفوعاتي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 54,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(height: 12),
                      Center(
                        child: Text(
                          'لا توجد مدفوعات مسجلة حتى الآن',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final t = _items[i];
                      final amt = t.grossAmount > 0
                          ? t.grossAmount
                          : t.commissionAmount;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.orangeLight,
                            child: Icon(
                              Icons.receipt_long,
                              color: AppColors.orange,
                            ),
                          ),
                          title: Text(
                            '${t.transactionType} · ${t.paymentMethod}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${t.createdAt.year}-${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')}',
                          ),
                          trailing: Text(
                            '${amt.toStringAsFixed(2)} د.أ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}