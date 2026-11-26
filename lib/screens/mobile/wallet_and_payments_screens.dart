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

  StreamSubscription<List<Map<String, dynamic>>>? _txSub;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSub;

  List<DbWalletTransaction> _allTxs = [];
  bool _loadingInitial = true;
  bool _loadedOnce = false;
  bool _settlingDebt = false;

  late double _liveWalletBalance = widget.profile.walletBalance;
  late double _livePendingDebt = widget.profile.pendingCommissionDebt;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _bindRealtimeStreams();
  }

  @override
  void didUpdateWidget(covariant ProviderWalletView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _liveWalletBalance = widget.profile.walletBalance;
      _livePendingDebt = widget.profile.pendingCommissionDebt;
      _loadInitialData();
      _bindRealtimeStreams();
    }
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        _db
            .from('wallet_transactions')
            .select()
            .eq('provider_id', widget.profile.id)
            .order('created_at', ascending: false),
        _db
            .from('customers')
            .select('wallet_balance, pending_commission_debt')
            .eq('id', widget.profile.id)
            .maybeSingle(),
      ]);

      final txRows = results[0] as List;
      final profileRow = results[1] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _allTxs = txRows
            .map((e) => DbWalletTransaction.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (profileRow != null) {
          _liveWalletBalance =
              (profileRow['wallet_balance'] as num?)?.toDouble() ?? 0.0;
          _livePendingDebt =
              (profileRow['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;
        }
        _loadingInitial = false;
        _loadedOnce = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _bindRealtimeStreams() {
    _txSub?.cancel();
    _profileSub?.cancel();

    _txSub = _db
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('provider_id', widget.profile.id)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _allTxs = rows.map(DbWalletTransaction.fromMap).toList();
              _loadingInitial = false;
              _loadedOnce = true;
            });
          },
          onError: (_) {},
        );

    _profileSub = _db
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', widget.profile.id)
        .listen(
          (rows) {
            if (!mounted || rows.isEmpty) return;
            final row = rows.first;
            setState(() {
              _liveWalletBalance =
                  (row['wallet_balance'] as num?)?.toDouble() ?? 0.0;
              _livePendingDebt =
                  (row['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;
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

  bool _isEarningTransaction(DbWalletTransaction t) {
    final type = t.transactionType.toLowerCase();
    if (type == 'withdrawal' ||
        type == 'payout' ||
        type == 'debt' ||
        type == 'debt_settlement' ||
        type == 'commission_settlement' ||
        type == 'subscription') {
      return false;
    }
    return true;
  }

  Future<void> _openWithdrawalSheet(double availableBalance) async {
    if (availableBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رصيد متاح للسحب حالياً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amountCtrl =
        TextEditingController(text: availableBalance.toStringAsFixed(2));
    final destinationCtrl = TextEditingController();
    final holderCtrl =
        TextEditingController(text: widget.profile.fullName ?? '');
    String method = 'cliq'; // 'cliq' | 'iban'
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'طلب سحب الأرباح (CliQ / IBAN)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'الرصيد المتاح للسحب: ${availableBalance.toStringAsFixed(2)} د.أ (يمكنك سحب أي مبلغ متاح)',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('CliQ · كليك')),
                          selected: method == 'cliq',
                          selectedColor: AppColors.navy,
                          labelStyle: TextStyle(
                            color: method == 'cliq'
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (_) =>
                              setSheetState(() => method = 'cliq'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('تحويل بنكي IBAN')),
                          selected: method == 'iban',
                          selectedColor: AppColors.navy,
                          labelStyle: TextStyle(
                            color: method == 'iban'
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (_) =>
                              setSheetState(() => method = 'iban'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المطلوب سحبه (د.أ)',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destinationCtrl,
                    decoration: InputDecoration(
                      labelText: method == 'cliq'
                          ? 'الاسم المستعار CliQ أو رقم الهاتف'
                          : 'رقم الآيبان (IBAN)',
                      hintText: method == 'cliq'
                          ? 'مثال: AHMAD99 أو 079xxxxxxx'
                          : 'JO94 CBJO 0010 0000 ...',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: holderCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم صاحب الحساب البنكي',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: submitting
                          ? null
                          : () async {
                              final amount = double.tryParse(
                                amountCtrl.text.trim().replaceAll(',', '.'),
                              );
                              final dest = destinationCtrl.text.trim();
                              final holder = holderCtrl.text.trim();

                              if (amount == null || amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('يرجى إدخال مبلغ صحيح أكبر من 0'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              if (amount > availableBalance + 0.001) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'المبلغ المطلوب أكبر من الرصيد المتاح'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              if (dest.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      method == 'cliq'
                                          ? 'يرجى إدخال معرّف CliQ أو رقم الهاتف'
                                          : 'يرجى إدخال رقم الـ IBAN',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              setSheetState(() => submitting = true);
                              try {
                                final newBalance = double.parse(
                                  (availableBalance - amount)
                                      .clamp(0.0, double.infinity)
                                      .toStringAsFixed(2),
                                );

                                await _db.from('wallet_transactions').insert({
                                  'provider_id': widget.profile.id,
                                  'customer_id': widget.profile.id,
                                  'reference_id':
                                      '${method.toUpperCase()}:$dest${holder.isNotEmpty ? ' ($holder)' : ''}',
                                  'transaction_type': 'withdrawal',
                                  'payment_method': method,
                                  'gross_amount': amount,
                                  'commission_rate': 0.0,
                                  'commission_amount': 0.0,
                                  'net_amount': -amount,
                                  'status': 'pending',
                                });

                                await _db.from('customers').update({
                                  'wallet_balance': newBalance,
                                }).eq('id', widget.profile.id);

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
                                            '${widget.profile.fullName ?? "مزود"} طلب سحب ${amount.toStringAsFixed(2)} د.أ عبر ${method.toUpperCase()} ($dest)',
                                        type: 'withdrawal_request',
                                        referenceId: widget.profile.id,
                                      );
                                    }
                                  }
                                } catch (_) {}

                                if (mounted) {
                                  setState(() {
                                    _liveWalletBalance = newBalance;
                                  });
                                }
                                widget.onRefreshProfile();

                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'تم إرسال طلب سحب الأرباح بنجاح ✓'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
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
                                if (ctx.mounted) {
                                  setSheetState(() => submitting = false);
                                }
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Text(
                              'إرسال طلب السحب',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    amountCtrl.dispose();
    destinationCtrl.dispose();
    holderCtrl.dispose();
  }

  Future<void> _payPendingCommissionDebt(double debtAmount) async {
    if (debtAmount <= 0 || _settlingDebt) return;

    setState(() => _settlingDebt = true);
    try {
      // دفع العمولات إلكترونياً فقط (ممنوع الدفع نقداً للعمولات)
      final ok = await PayTabsPaymentService().startPaymentFlow(
        context: context,
        baseAmount: debtAmount,
        title: 'سداد عمولات الكاش المستحقة للمنصة',
        orderType: 'debt',
        referenceId: widget.profile.id,
        email: widget.profile.email,
        phone: widget.profile.phone,
        name: widget.profile.fullName,
        userRole: widget.profile.role,
        allowCash: false,
      );

      if (!ok) return;

      await _db.from('customers').update({
        'pending_commission_debt': 0.0,
      }).eq('id', widget.profile.id);

      if (mounted) {
        setState(() => _livePendingDebt = 0.0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم سداد العمولات المستحقة وتصفير الذمة بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      widget.onRefreshProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر سداد العمولات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _settlingDebt = false);
    }
  }

  String _txArabicTitle(DbWalletTransaction t) {
    final type = t.transactionType.toLowerCase();
    return switch (type) {
      'withdrawal' || 'payout' => 'طلب سحب أرباح',
      'workshop' || 'workshop_appointment' || 'wrk' => 'فاتورة ورشة صيانة',
      'emergency' || 'mechanic_emergency' || 'emg' => 'خدمة طوارئ ميكانيكي',
      'winch' || 'winch_towing' || 'towing' => 'رحلة ونش طوارئ',
      'order' || 'part_order' || 'ord' => 'مبيعات قطعة غيار',
      'debt' || 'debt_settlement' || 'commission_settlement' =>
        'سداد عمولات المنصة',
      'subscription' || 'sub' => 'اشتراك باقة',
      _ => t.transactionType,
    };
  }

  String _methodArabic(String method) {
    return switch (method.toLowerCase()) {
      'visa' || 'card' || 'meps' => 'Visa / Mastercard',
      'apple_pay' || 'applepay' => 'Apple Pay',
      'google_pay' || 'googlepay' => 'Google Pay',
      'cliq' => 'CliQ · كليك',
      'iban' => 'تحويل بنكي IBAN',
      'cash' => 'نقداً (كاش)',
      _ => method,
    };
  }

  String _statusArabic(String status) {
    return switch (status.toLowerCase()) {
      'completed' || 'paid' || 'approved' || 'success' => 'مكتملة',
      'pending' || 'pending_review' => 'قيد المراجعة',
      'rejected' || 'failed' || 'cancelled' => 'ملغاة',
      _ => status,
    };
  }

  Color _statusColor(String status) {
    return switch (status.toLowerCase()) {
      'completed' || 'paid' || 'approved' || 'success' => AppColors.success,
      'pending' || 'pending_review' => AppColors.orange,
      'rejected' || 'failed' || 'cancelled' => Colors.red,
      _ => AppColors.textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final periodTxs = _allTxs.where((t) => _inPeriod(t.createdAt)).toList();
    final earningPeriodTxs = periodTxs.where(_isEarningTransaction).toList();

    final periodGross =
        earningPeriodTxs.fold<double>(0.0, (s, t) => s + t.grossAmount);
    final periodComm =
        earningPeriodTxs.fold<double>(0.0, (s, t) => s + t.commissionAmount);
    final periodNet =
        earningPeriodTxs.fold<double>(0.0, (s, t) => s + t.netAmount);

    // إذا تم حذف جميع المعاملات من قاعدة البيانات لا يُعرض رصيد قديم عالق
    final double availableBalance =
        (_loadedOnce && _allTxs.isEmpty) ? 0.0 : _liveWalletBalance;
    final double pendingDebt =
        (_loadedOnce && _allTxs.isEmpty) ? 0.0 : _livePendingDebt;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DateRangeFilterBar(
              period: _period,
              customRange: _customRange,
              onChanged: (p, r) => setState(() {
                _period = p;
                _customRange = r;
              }),
            ),
          ),
          const SizedBox(height: 12),

          // بطاقة الرصيد الرئيسية (بنفس التصميم تماماً)
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
                  'صافي الرصيد القابل للسحب',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${availableBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'إجمالي الفترة: ${periodGross.toStringAsFixed(2)} د.أ  |  العمولات: ${periodComm.toStringAsFixed(2)} د.أ  |  الصافي: ${periodNet.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.account_balance, size: 19),
                    label: const Text(
                      'سحب الأرباح (CliQ / IBAN)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _openWithdrawalSheet(availableBalance),
                  ),
                ),
              ],
            ),
          ),

          // بطاقة عمولات الكاش المستحقة (تظهر فقط إذا وجدت ذمة مستحقة)
          if (pendingDebt > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.orange),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'عمولات الكاش المستحقة للمنصة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${pendingDebt.toStringAsFixed(2)} د.أ',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.orange,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'يمكنك تسديد العمولات إلكترونياً مباشرة (Visa / Apple Pay / Google Pay / CliQ).',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _settlingDebt
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.payment, size: 18),
                      label: Text(
                        'سداد العمولات الآن (${pendingDebt.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _settlingDebt
                          ? null
                          : () => _payPendingCommissionDebt(pendingDebt),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'سجل الحركات المالية',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${periodTxs.length} حركة',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_loadingInitial)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (periodTxs.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'لا توجد حركات مالية مسجلة حتى الآن',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ...periodTxs.map((t) {
              final isWithdrawal =
                  t.transactionType.toLowerCase() == 'withdrawal' ||
                      t.transactionType.toLowerCase() == 'payout' ||
                      t.netAmount < 0;
              final displayAmt = isWithdrawal
                  ? '-${t.netAmount.abs().toStringAsFixed(2)} د.أ'
                  : '+${t.netAmount.toStringAsFixed(2)} د.أ';
              final dateStr =
                  '${t.createdAt.year}/${t.createdAt.month.toString().padLeft(2, '0')}/${t.createdAt.day.toString().padLeft(2, '0')}';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isWithdrawal
                        ? AppColors.orangeLight
                        : AppColors.success.withValues(alpha: 0.12),
                    child: Icon(
                      isWithdrawal
                          ? Icons.north_east
                          : Icons.south_west_rounded,
                      color: isWithdrawal ? AppColors.orange : AppColors.success,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '${_txArabicTitle(t)} · ${_methodArabic(t.paymentMethod)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    isWithdrawal
                        ? '$dateStr · ${_statusArabic(t.status)}'
                        : '$dateStr · قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} | العمولة: -${t.commissionAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayAmt,
                        style: TextStyle(
                          color: isWithdrawal
                              ? AppColors.orange
                              : AppColors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusArabic(t.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(t.status),
                        ),
                      ),
                    ],
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
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<DbWalletTransaction> _txs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _sub = _db
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('customer_id', widget.profile.id)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _txs = rows.map(DbWalletTransaction.fromMap).toList();
              _loading = false;
            });
          },
          onError: (_) {},
        );
  }

  Future<void> _loadInitial() async {
    try {
      final rows = await _db
          .from('wallet_transactions')
          .select()
          .eq('customer_id', widget.profile.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _txs = (rows as List)
            .map((e) =>
                DbWalletTransaction.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _txTitle(String type) {
    return switch (type.toLowerCase()) {
      'workshop' || 'workshop_appointment' || 'wrk' => 'دفع فاتورة ورشة',
      'emergency' || 'mechanic_emergency' || 'emg' => 'دفع خدمة طوارئ',
      'winch' || 'winch_towing' || 'towing' => 'دفع خدمة ونش طوارئ',
      'order' || 'part_order' || 'ord' => 'شراء قطعة غيار',
      'subscription' || 'sub' => 'اشتراك عضوية',
      _ => type,
    };
  }

  String _methodLabel(String method) {
    return switch (method.toLowerCase()) {
      'visa' || 'card' || 'meps' => 'Visa / Mastercard',
      'apple_pay' || 'applepay' => 'Apple Pay',
      'google_pay' || 'googlepay' => 'Google Pay',
      'cliq' => 'CliQ · كليك',
      'cash' => 'نقداً (كاش)',
      _ => method,
    };
  }

  @override
  Widget build(BuildContext context) {
    final totalSpent = _txs.fold<double>(0.0, (s, t) => s + t.grossAmount);

    return Scaffold(
      appBar: AppBar(title: const Text('سجل المدفوعات والفواتير')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: RefreshIndicator(
            onRefresh: _loadInitial,
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
                        'إجمالي المدفوعات المسجلة',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${totalSpent.toStringAsFixed(2)} د.أ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'عدد العمليات: ${_txs.length}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
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
                else if (_txs.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 44, horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 40,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'لا توجد مدفوعات مسجلة حتى الآن',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._txs.map((t) {
                    final dateStr =
                        '${t.createdAt.year}/${t.createdAt.month.toString().padLeft(2, '0')}/${t.createdAt.day.toString().padLeft(2, '0')}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.orangeLight,
                          child: Icon(
                            Icons.receipt_outlined,
                            color: AppColors.orange,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          _txTitle(t.transactionType),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '$dateStr · ${_methodLabel(t.paymentMethod)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          '${t.grossAmount.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}