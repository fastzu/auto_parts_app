import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';
import 'notifications_service.dart';

/// شعار Google Pay الرسمي بالألوان الأربعة (G Pay)
class GooglePayLogo extends StatelessWidget {
  final double height;
  const GooglePayLogo({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFDADCE0), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GoogleLogoIcon(size: height * 0.56),
            const SizedBox(width: 4),
            Text(
              'Pay',
              style: TextStyle(
                color: const Color(0xFF3C4043),
                fontSize: height * 0.50,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppliedDiscountResult {
  final String code;
  final double percent;
  final double discountAmount;
  final String? title;

  const AppliedDiscountResult({
    required this.code,
    required this.percent,
    required this.discountAmount,
    this.title,
  });
}

class PayTabsPaymentService {
  final SupabaseClient _client = Supabase.instance.client;

  /// آخر وسيلة دفع اختارها المستخدم (تُستخدم لتسجيل نوع الدفع بدقة في المحفظة)
  static String? lastChosenMethod;

  Future<AppliedDiscountResult> validateDiscountCode({
    required String rawCode,
    required double baseAmount,
    String? userRole,
  }) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw Exception('يرجى إدخال كود الخصم');
    }

    final uid = _client.auth.currentUser?.id;
    String effectiveRole = (userRole ?? '').toLowerCase();
    if (effectiveRole.isEmpty && uid != null) {
      final me = await _client
          .from('customers')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      effectiveRole = (me?['role'] as String? ?? 'user').toLowerCase();
    }

    final rows = await _client
        .from('discounts')
        .select()
        .ilike('code', code)
        .eq('is_active', true)
        .limit(5);

    if ((rows as List).isEmpty) {
      throw Exception('كود الخصم غير صالح أو غير مفعّل');
    }

    Map<String, dynamic>? matched;
    final now = DateTime.now();

    for (final item in rows) {
      final row = Map<String, dynamic>.from(item as Map);
      final expStr = row['expires_at'] as String?;
      if (expStr != null && expStr.isNotEmpty) {
        final exp = DateTime.tryParse(expStr);
        if (exp != null && exp.isBefore(now)) continue;
      }

      final targetUserId = row['target_user_id'] as String?;
      if (targetUserId != null && targetUserId.isNotEmpty) {
        if (uid == null || targetUserId != uid) continue;
        matched = row;
        break;
      }

      final targetRole = (row['target_role'] as String? ?? 'all').toLowerCase();
      if (targetRole == 'all' ||
          targetRole.isEmpty ||
          targetRole == effectiveRole) {
        matched = row;
        break;
      }
    }

    if (matched == null) {
      throw Exception('هذا الكود غير متاح لحسابك أو انتهت صلاحيته');
    }

    final percent =
        ((matched['discount_percent'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 95.0);
    if (percent <= 0) {
      throw Exception('نسبة الخصم غير صالحة');
    }

    final discountAmount =
        double.parse((baseAmount * (percent / 100.0)).toStringAsFixed(2));
    return AppliedDiscountResult(
      code: (matched['code'] as String? ?? code).toUpperCase(),
      percent: percent,
      discountAmount: discountAmount,
      title: matched['title'] as String?,
    );
  }

  /// قائمة وسائل الدفع الموحدة: Visa/Mastercard · Apple Pay · Google Pay · CliQ · Cash
  Future<bool> startPaymentFlow({
    required BuildContext context,
    required double baseAmount,
    double feeAmount = 0.0,
    required String title,
    required String orderType, // 'sub' | 'wrk' | 'ord' | 'emg' | 'debt'
    required String referenceId,
    String? email,
    String? phone,
    String? name,
    String? discountCode,
    double discountAmount = 0.0,
    String? userRole,
  }) async {
    final chosenMethod = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اختر وسيلة الدفع',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _methodCard(
                ctx: ctx,
                methodCode: 'visa',
                leading: const Icon(
                  Icons.credit_card,
                  color: AppColors.orange,
                  size: 28,
                ),
                title: 'Visa / Mastercard',
                borderColor: AppColors.orange,
              ),
              const SizedBox(height: 8),
              _methodCard(
                ctx: ctx,
                methodCode: 'apple_pay',
                leading: const Icon(Icons.apple, color: Colors.black, size: 30),
                title: 'Apple Pay',
              ),
              const SizedBox(height: 8),
              _methodCard(
                ctx: ctx,
                methodCode: 'google_pay',
                leading: const GooglePayLogo(height: 28),
                title: 'Google Pay',
              ),
              const SizedBox(height: 8),
              _methodCard(
                ctx: ctx,
                methodCode: 'cliq',
                leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.navy,
                  size: 26,
                ),
                title: 'CliQ',
              ),
              const SizedBox(height: 8),
              _methodCard(
                ctx: ctx,
                methodCode: 'cash',
                leading: const Icon(
                  Icons.payments_outlined,
                  color: AppColors.success,
                  size: 26,
                ),
                title: 'Cash (نقداً)',
              ),
            ],
          ),
        ),
      ),
    );

    if (chosenMethod == null || !context.mounted) return false;
    lastChosenMethod = chosenMethod;

    final bool? paid = await Navigator.of(context).push<bool>(
      animatedRoute(
        _MepsCheckoutPage(
          service: this,
          paymentMethod: chosenMethod,
          title: title,
          baseAmount: baseAmount,
          feeAmount: feeAmount,
          initialDiscountCode: discountCode,
          initialDiscountAmount: discountAmount,
          userRole: userRole,
          orderType: orderType,
          referenceId: referenceId,
          onPayWithCard: (finalTotal, appliedCode, appliedDiscount) =>
              payWithCardRedirect(
            context: context,
            amount: finalTotal,
            title: title,
            orderType: orderType,
            referenceId: referenceId,
            email: email,
            phone: phone,
            name: name,
            discountCode: appliedCode,
            discountAmount: appliedDiscount,
          ),
        ),
      ),
    );

    return paid == true;
  }

  Widget _methodCard({
    required BuildContext ctx,
    required String methodCode,
    required Widget leading,
    required String title,
    Color? borderColor,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: borderColor ?? AppColors.border,
          width: borderColor != null ? 1.4 : 1,
        ),
      ),
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 15,
          color: AppColors.textSecondary,
        ),
        onTap: () => Navigator.pop(ctx, methodCode),
      ),
    );
  }

  Future<bool> payWithCardRedirect({
    required BuildContext context,
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    String? email,
    String? phone,
    String? name,
    String? discountCode,
    double discountAmount = 0.0,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final safeAmount =
        double.parse(amount.clamp(0.5, 99999.0).toStringAsFixed(2));
    final startedAtIso = DateTime.now().toUtc().toIso8601String();

    final res = await _client.functions.invoke(
      'create-payment',
      body: {
        'user_id': user.id,
        'amount': safeAmount,
        'payment_method': 'Card',
        'description': title,
        'order_type': orderType,
        'reference_id': referenceId,
        'customer_email': email ?? user.email,
        'customer_phone': phone ?? '0790000000',
        'customer_name': name ?? 'Customer',
        if (discountCode != null && discountCode.isNotEmpty)
          'discount_code': discountCode,
        if (discountAmount > 0) 'discount_amount': discountAmount,
      },
    );

    if (res.status != 200 ||
        res.data == null ||
        res.data['redirect_url'] == null) {
      throw Exception(
          res.data?['error'] ?? 'تعذر إنشاء جلسة الدفع من البوابة');
    }

    final String redirectUrl = res.data['redirect_url'] as String;
    if (!context.mounted) return false;

    final bool isMobileNative = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileNative) {
      final bool? completed = await Navigator.of(context).push<bool>(
        animatedRoute(
          PaymentWebViewScreen(
            redirectUrl: redirectUrl,
            title: title,
          ),
        ),
      );
      return completed == true;
    } else {
      await launchUrl(
        Uri.parse(redirectUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted) return false;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          bool checking = false;
          String? statusMsg;
          return StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
              title: const Text('تأكيد الدفع الإلكتروني'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اضغط "التحقق من الدفع" بعد إتمام العملية في المتصفح.'),
                  if (statusMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      statusMsg!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: checking ? null : () => Navigator.pop(ctx, false),
                  child: const Text('إغلاق'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: checking
                      ? null
                      : () async {
                          setDlg(() {
                            checking = true;
                            statusMsg = null;
                          });
                          final verified = await _verifyServerPayment(
                            userId: user.id,
                            referenceId: referenceId,
                            orderType: orderType,
                            sinceIso: startedAtIso,
                          );
                          if (!ctx.mounted) return;
                          if (verified) {
                            Navigator.pop(ctx, true);
                          } else {
                            setDlg(() {
                              checking = false;
                              statusMsg =
                                  'لم يصل تأكيد الدفع بعد، حاول مرة أخرى.';
                            });
                          }
                        },
                  child: checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('التحقق من الدفع'),
                ),
              ],
            ),
          );
        },
      );
      return confirmed == true;
    }
  }

  Future<bool> _verifyServerPayment({
    required String userId,
    required String referenceId,
    required String orderType,
    required String sinceIso,
  }) async {
    try {
      final txRows = await _client
          .from('wallet_transactions')
          .select('id, status')
          .eq('customer_id', userId)
          .gte('created_at', sinceIso)
          .inFilter('status', ['completed', 'paid', 'success']).limit(5);
      if ((txRows as List).isNotEmpty) return true;

      if (orderType == 'wrk') {
        final appt = await _client
            .from('workshop_appointments')
            .select('status, progress_step')
            .eq('id', referenceId)
            .maybeSingle();
        if (appt != null &&
            (appt['status'] == 'completed' ||
                appt['progress_step'] == 'completed')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// تسجيل CliQ أو Cash بشكل نظيف بدون تخريب أرقام wallet_transactions عند تسديد العمولات
  Future<void> submitManualPaymentRequest({
    required String paymentMethod, // 'cliq' | 'cash'
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    String? senderNote,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final noteClean = (senderNote ?? '').trim();
    if (paymentMethod == 'cliq' && noteClean.isEmpty) {
      throw Exception('يرجى إدخال رقم الحوالة أو اسم المحوّل');
    }

    // في حال CliQ نسجل في جدول cliq_requests إن وجد بدون إضافة صف أرباح وهمي
    if (paymentMethod == 'cliq') {
      try {
        await _client.from('cliq_requests').insert({
          'user_id': user.id,
          'amount': amount.toStringAsFixed(2),
          'reference_number': noteClean,
          'status': 'pending',
        });
      } catch (_) {}
    }

    // إشعار الأدمن
    try {
      final admins = await _client
          .from('customers')
          .select('id')
          .eq('role', 'admin')
          .limit(10);
      for (final a in (admins as List)) {
        final adminId = a['id'] as String?;
        if (adminId != null) {
          await NotificationsService.instance.sendNotification(
            targetUserId: adminId,
            title: paymentMethod == 'cliq'
                ? 'حوالة CliQ جديدة'
                : 'تأكيد دفع نقدي (Cash)',
            body:
                'مبلغ ${amount.toStringAsFixed(2)} د.أ · $title${noteClean.isNotEmpty ? ' · مرجع: $noteClean' : ''}',
            type: 'payment_review',
            referenceId: referenceId,
          );
        }
      }
    } catch (_) {}
  }

  Future<String> fetchCliqAlias() async {
    try {
      final row = await _client
          .from('system_settings')
          .select('value')
          .eq('key', 'cliq_alias')
          .maybeSingle();
      final val = (row?['value'] as String? ?? '').trim();
      if (val.isNotEmpty) return val;
    } catch (_) {}
    return 'GHAYARAKJO';
  }
}

class _MepsCheckoutPage extends StatefulWidget {
  final PayTabsPaymentService service;
  final String paymentMethod;
  final String title;
  final double baseAmount;
  final double feeAmount;
  final String? initialDiscountCode;
  final double initialDiscountAmount;
  final String? userRole;
  final String orderType;
  final String referenceId;
  final Future<bool> Function(
    double finalTotal,
    String? discountCode,
    double discountAmount,
  ) onPayWithCard;

  const _MepsCheckoutPage({
    required this.service,
    required this.paymentMethod,
    required this.title,
    required this.baseAmount,
    required this.feeAmount,
    required this.orderType,
    required this.referenceId,
    required this.onPayWithCard,
    this.initialDiscountCode,
    this.initialDiscountAmount = 0.0,
    this.userRole,
  });

  @override
  State<_MepsCheckoutPage> createState() => _MepsCheckoutPageState();
}

class _MepsCheckoutPageState extends State<_MepsCheckoutPage> {
  final _promoCtrl = TextEditingController();
  final _cliqRefCtrl = TextEditingController();

  bool _loading = false;
  bool _checkingPromo = false;
  String? _appliedCode;
  double _appliedPercent = 0.0;
  double _discountAmount = 0.0;
  String? _promoError;
  String _cliqAlias = 'GHAYARAKJO';

  @override
  void initState() {
    super.initState();
    if (widget.initialDiscountCode != null &&
        widget.initialDiscountCode!.isNotEmpty) {
      _appliedCode = widget.initialDiscountCode;
      _promoCtrl.text = widget.initialDiscountCode!;
      _discountAmount = widget.initialDiscountAmount;
    }
    if (widget.paymentMethod == 'cliq') {
      widget.service.fetchCliqAlias().then((alias) {
        if (mounted) setState(() => _cliqAlias = alias);
      });
    }
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    _cliqRefCtrl.dispose();
    super.dispose();
  }

  double get _finalTotal {
    final total = widget.baseAmount - _discountAmount + widget.feeAmount;
    return double.parse((total < 0 ? 0.0 : total).toStringAsFixed(2));
  }

  String get _methodDisplayName {
    return switch (widget.paymentMethod) {
      'apple_pay' => 'Apple Pay',
      'google_pay' => 'Google Pay',
      'cliq' => 'CliQ',
      'cash' => 'Cash (نقداً)',
      _ => 'Visa / Mastercard',
    };
  }

  Future<void> _applyPromo() async {
    FocusScope.of(context).unfocus();
    final raw = _promoCtrl.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _checkingPromo = true;
      _promoError = null;
    });

    try {
      final res = await widget.service.validateDiscountCode(
        rawCode: raw,
        baseAmount: widget.baseAmount,
        userRole: widget.userRole,
      );
      if (!mounted) return;
      setState(() {
        _appliedCode = res.code;
        _appliedPercent = res.percent;
        _discountAmount = res.discountAmount;
        _checkingPromo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تفعيل كود الخصم ${res.code} (-${res.percent.toInt()}%)'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingPromo = false;
        _promoError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _submitPayment() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      if (widget.paymentMethod == 'cliq' || widget.paymentMethod == 'cash') {
        await widget.service.submitManualPaymentRequest(
          paymentMethod: widget.paymentMethod,
          amount: _finalTotal,
          title: widget.title,
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          senderNote: _cliqRefCtrl.text,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final ok = await widget.onPayWithCard(
          _finalTotal,
          _appliedCode,
          _discountAmount,
        );
        if (ok && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCliq = widget.paymentMethod == 'cliq';
    final isCash = widget.paymentMethod == 'cash';

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص الدفع')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'وسيلة الدفع: $_methodDisplayName',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const Divider(height: 28),
                    _row(
                      'المبلغ الأساسي',
                      '${widget.baseAmount.toStringAsFixed(2)} د.أ',
                    ),
                    if (_discountAmount > 0) ...[
                      const SizedBox(height: 10),
                      _row(
                        'كود الخصم (${_appliedCode ?? ''}${_appliedPercent > 0 ? ' - ${_appliedPercent.toInt()}%' : ''})',
                        '-${_discountAmount.toStringAsFixed(2)} د.أ',
                        color: AppColors.success,
                      ),
                    ],
                    if (widget.feeAmount > 0) ...[
                      const SizedBox(height: 10),
                      _row(
                        'عمولة الخدمة',
                        '${widget.feeAmount.toStringAsFixed(2)} د.أ',
                        color: AppColors.orange,
                      ),
                    ],
                    const Divider(height: 28),
                    _row(
                      'الإجمالي للدفع',
                      '${_finalTotal.toStringAsFixed(2)} د.أ',
                      bold: true,
                      color: AppColors.navy,
                    ),
                  ],
                ),
              ),
            ),
            if (widget.orderType != 'debt') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'كود الخصم',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promoCtrl,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _applyPromo(),
                            decoration: InputDecoration(
                              hintText: 'أدخل كود الخصم',
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                          ),
                          onPressed: _checkingPromo ? null : _applyPromo,
                          child: _checkingPromo
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('تطبيق'),
                        ),
                      ],
                    ),
                    if (_promoError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _promoError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    if (_appliedCode != null && _discountAmount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'كود $_appliedCode (-${_discountAmount.toStringAsFixed(2)} د.أ)',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _appliedCode = null;
                                _appliedPercent = 0;
                                _discountAmount = 0;
                                _promoCtrl.clear();
                              });
                            },
                            child: const Text(
                              'إزالة',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (isCliq) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.navy.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'CliQ Alias: $_cliqAlias',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _cliqAlias));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم نسخ $_cliqAlias ✓')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 15),
                          label: const Text('نسخ'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _cliqRefCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitPayment(),
                      decoration: InputDecoration(
                        labelText: 'رقم مرجع الحوالة أو اسم المحوّل',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _loading ? null : _submitPayment,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        isCliq
                            ? 'تأكيد حوالة CliQ (${_finalTotal.toStringAsFixed(2)} د.أ)'
                            : isCash
                                ? 'تأكيد الدفع نقداً (${_finalTotal.toStringAsFixed(2)} د.أ)'
                                : 'ادفع الآن (${_finalTotal.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String val, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500),
          ),
        ),
        Text(
          val,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.bold,
            fontSize: bold ? 18 : 14,
            color: color,
          ),
        ),
      ],
    );
  }
}