import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/env_config.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';

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

  /// التحقق من كود الخصم في قاعدة البيانات (فعّال + غير منتهي + مخصص للمستخدم أو لفئته)
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
        if (exp != null && exp.isBefore(now)) {
          continue;
        }
      }

      final targetUserId = row['target_user_id'] as String?;
      if (targetUserId != null && targetUserId.isNotEmpty) {
        if (uid == null || targetUserId != uid) {
          continue;
        }
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

    final percent = ((matched['discount_percent'] as num?)?.toDouble() ?? 0.0)
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

  /// 1) فتح قائمة وسائل الدفع: Visa/Mastercard (MEPS) + Apple Pay + Google Pay
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اختر وسيلة الدفع',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              // 1) Visa / Mastercard (MEPS)
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
                  subtitle: const Text('الدفع الإلكتروني الآمن عبر MEPS'),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 16, color: AppColors.orange),
                  onTap: () => Navigator.pop(ctx, 'visa'),
                ),
              ),
              const SizedBox(height: 10),

              // 2) Apple Pay
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: EnvConfig.applePayEnabled
                        ? Colors.black
                        : AppColors.border,
                    width: 1.2,
                  ),
                ),
                child: ListTile(
                  leading:
                      const Icon(Icons.apple, color: Colors.black, size: 30),
                  title: const Text('Apple Pay',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    EnvConfig.applePayEnabled
                        ? 'دفع سريع وآمن عبر Apple Pay'
                        : 'جاهز للتفعيل فور ربط حساب Apple Developer',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 16, color: Colors.black),
                  onTap: () => Navigator.pop(ctx, 'apple_pay'),
                ),
              ),
              const SizedBox(height: 10),

              // 3) Google Pay
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: EnvConfig.googlePayEnabled
                        ? AppColors.navy
                        : AppColors.border,
                    width: 1.2,
                  ),
                ),
                child: ListTile(
                  leading: const GoogleLogoIcon(size: 24),
                  title: const Text('Google Pay',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    EnvConfig.googlePayEnabled
                        ? 'دفع سريع وآمن عبر Google Pay'
                        : 'جاهز للتفعيل فور ربط حساب Google Pay Merchant',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 16, color: AppColors.navy),
                  onTap: () => Navigator.pop(ctx, 'google_pay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosenMethod == null || !context.mounted) {
      return false;
    }

    // 2) الانتقال لصفحة Checkout وعرض الإجمالي + كود الخصم
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
          onExecutePay: (finalTotal, appliedCode, appliedDiscount) {
            if (chosenMethod == 'apple_pay') {
              return payWithApplePay(
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
              );
            }
            if (chosenMethod == 'google_pay') {
              return payWithGooglePay(
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
              );
            }
            return payWithCardRedirect(
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
            );
          },
        ),
      ),
    );

    return paid == true;
  }

  /// الدفع عبر Apple Pay (يعمل فور وضع APPLE_PAY_MERCHANT_ID وتفعيل applePayEnabled في env_config.dart)
  Future<bool> payWithApplePay({
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
    if (!EnvConfig.applePayEnabled) {
      throw Exception(
        'خدمة Apple Pay جاهزة برمجياً — ضع Apple Merchant ID وفعّل applePayEnabled في env_config.dart بعد الاشتراك بحساب Apple Developer.',
      );
    }
    return payWithCardRedirect(
      context: context,
      amount: amount,
      title: title,
      orderType: orderType,
      referenceId: referenceId,
      email: email,
      phone: phone,
      name: name,
      discountCode: discountCode,
      discountAmount: discountAmount,
      gatewayMethod: 'ApplePay',
      extraBody: {
        'apple_pay_merchant_id': EnvConfig.applePayMerchantId,
        'country_code': EnvConfig.paymentCountryCode,
        'currency': EnvConfig.paymentCurrencyCode,
      },
    );
  }

  /// الدفع عبر Google Pay (يعمل فور وضع GOOGLE_PAY_MERCHANT_ID وتفعيل googlePayEnabled في env_config.dart)
  Future<bool> payWithGooglePay({
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
    if (!EnvConfig.googlePayEnabled) {
      throw Exception(
        'خدمة Google Pay جاهزة برمجياً — ضع Google Pay Merchant ID وفعّل googlePayEnabled في env_config.dart عند التفعيل.',
      );
    }
    return payWithCardRedirect(
      context: context,
      amount: amount,
      title: title,
      orderType: orderType,
      referenceId: referenceId,
      email: email,
      phone: phone,
      name: name,
      discountCode: discountCode,
      discountAmount: discountAmount,
      gatewayMethod: 'GooglePay',
      extraBody: {
        'google_pay_merchant_id': EnvConfig.googlePayMerchantId,
        'google_pay_gateway': EnvConfig.googlePayGateway,
        'google_pay_gateway_merchant_id': EnvConfig.googlePayGatewayMerchantId,
        'country_code': EnvConfig.paymentCountryCode,
        'currency': EnvConfig.paymentCurrencyCode,
      },
    );
  }

  /// الاتصال بدالة create-payment وفتح صفحة MEPS / Apple Pay / Google Pay
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
    String gatewayMethod = 'Card',
    Map<String, dynamic>? extraBody,
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
        'payment_method': gatewayMethod,
        'description': title,
        'order_type': orderType,
        'reference_id': referenceId,
        'customer_email': email ?? user.email,
        'customer_phone': phone ?? '0790000000',
        'customer_name': name ?? 'Customer',
        if (discountCode != null && discountCode.isNotEmpty)
          'discount_code': discountCode,
        if (discountAmount > 0) 'discount_amount': discountAmount,
        if (extraBody != null) ...extraBody,
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
        animatedRoute(PaymentWebViewScreen(
          redirectUrl: redirectUrl,
          title: title,
        )),
      );
      return completed == true;
    } else {
      await launchUrl(Uri.parse(redirectUrl),
          mode: LaunchMode.externalApplication);
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
                  const Text(
                    'تم فتح بوابة الدفع الآمنة في المتصفح.\nبعد إتمام الدفع بنجاح، اضغط "التحقق من الدفع" لتأكيد العملية من السيرفر.',
                  ),
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
                                  'لم يصل تأكيد البنك بعد. تأكد من إتمام الدفع ثم اضغط مجدداً.';
                            });
                          }
                        },
                  child: checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
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
            .select('status, progress_step, payment_status')
            .eq('id', referenceId)
            .maybeSingle();
        if (appt != null &&
            (appt['payment_status'] == 'paid' ||
                appt['status'] == 'completed')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// صفحة الـ Checkout التي تعرض الإجمالي + تفعيل كود الخصم + وسيلة الدفع المختارة
class _MepsCheckoutPage extends StatefulWidget {
  final PayTabsPaymentService service;
  final String paymentMethod; // 'visa' | 'apple_pay' | 'google_pay'
  final String title;
  final double baseAmount;
  final double feeAmount;
  final String? initialDiscountCode;
  final double initialDiscountAmount;
  final String? userRole;
  final String orderType;
  final String referenceId;
  final Future<bool> Function(
          double finalTotal, String? discountCode, double discountAmount)
      onExecutePay;

  const _MepsCheckoutPage({
    required this.service,
    required this.paymentMethod,
    required this.title,
    required this.baseAmount,
    required this.feeAmount,
    required this.orderType,
    required this.referenceId,
    required this.onExecutePay,
    this.initialDiscountCode,
    this.initialDiscountAmount = 0.0,
    this.userRole,
  });

  @override
  State<_MepsCheckoutPage> createState() => _MepsCheckoutPageState();
}

class _MepsCheckoutPageState extends State<_MepsCheckoutPage> {
  final _promoCtrl = TextEditingController();

  bool _loading = false;
  bool _checkingPromo = false;
  String? _appliedCode;
  double _appliedPercent = 0.0;
  double _discountAmount = 0.0;
  String? _promoError;

  @override
  void initState() {
    super.initState();
    if (widget.initialDiscountCode != null &&
        widget.initialDiscountCode!.isNotEmpty) {
      _appliedCode = widget.initialDiscountCode;
      _promoCtrl.text = widget.initialDiscountCode!;
      _discountAmount = widget.initialDiscountAmount;
    }
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  double get _finalTotal {
    final total = widget.baseAmount - _discountAmount + widget.feeAmount;
    return double.parse((total < 0 ? 0.0 : total).toStringAsFixed(2));
  }

  String get _methodLabel => switch (widget.paymentMethod) {
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        _ => 'Visa / Mastercard (MEPS)',
      };

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
          content: Text(
              'تم تفعيل كود الخصم ${res.code} بنجاح (-${res.percent.toInt()}%)'),
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
      final ok = await widget.onExecutePay(
        _finalTotal,
        _appliedCode,
        _discountAmount,
      );
      if (ok && mounted) {
        Navigator.pop(context, true);
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
    final isApple = widget.paymentMethod == 'apple_pay';
    final isGoogle = widget.paymentMethod == 'google_pay';

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
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'وسيلة الدفع: $_methodLabel',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const Divider(height: 28),
                    _row('المبلغ الأساسي',
                        '${widget.baseAmount.toStringAsFixed(2)} د.أ'),
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
                      _row('عمولة الخدمة',
                          '${widget.feeAmount.toStringAsFixed(2)} د.أ',
                          color: AppColors.orange),
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
            const SizedBox(height: 16),

            // حقل إدخال وتفعيل كود الخصم
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
                    'هل لديك كود خصم؟',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                            hintText: 'أدخل كود الخصم هنا',
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
                              horizontal: 16, vertical: 13),
                        ),
                        onPressed: _checkingPromo ? null : _applyPromo,
                        child: _checkingPromo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
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
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'تم تطبيق كود $_appliedCode بخصم ${_discountAmount.toStringAsFixed(2)} د.أ',
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
                          child: const Text('إزالة',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isApple
                      ? Colors.black
                      : (isGoogle ? AppColors.navy : AppColors.orange),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _loading ? null : _submitPayment,
                icon: _loading
                    ? const SizedBox.shrink()
                    : Icon(
                        isApple
                            ? Icons.apple
                            : (isGoogle
                                ? Icons.account_balance_wallet_outlined
                                : Icons.credit_card),
                      ),
                label: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'الدفع عبر $_methodLabel (${_finalTotal.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.bold),
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