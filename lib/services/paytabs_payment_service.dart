import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';

/// شعار Google Pay الرسمي بـ 4 ألوان (G + Pay)
class GooglePayLogo extends StatelessWidget {
  final double size;

  const GooglePayLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GoogleLogoIcon(size: size),
        const SizedBox(width: 4),
        Text(
          'Pay',
          style: TextStyle(
            fontSize: size * 0.72,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3C4043),
            letterSpacing: -0.3,
          ),
        ),
      ],
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

  /// آخر وسيلة دفع اختارها المستخدم
  static String? lastChosenMethod;

  // =========================================================================
  // إعدادات ربط بوابات الدفع بالـ API (ضع المفاتيح وحوّل false إلى true لاحقاً)
  // =========================================================================

  // 1) Apple Pay API
  static const bool applePayApiEnabled = false;
  static const String applePayMerchantId = ''; // مثال: merchant.com.autoparts.app
  static const String applePayEdgeFunction = 'create-apple-pay-payment';

  // 2) Google Pay API
  static const bool googlePayApiEnabled = false;
  static const String googlePayMerchantId = ''; // مثال: BCR2DN...
  static const String googlePayEdgeFunction = 'create-google-pay-payment';

  // 3) CliQ Request to Pay (RTP) API
  static const bool cliqRtpApiEnabled = false;
  static const String cliqRtpMerchantAlias = 'GHAYARAKJO';
  static const String cliqRtpEdgeFunction = 'cliq-request-to-pay';

  // =========================================================================

  /// التحقق من كود الخصم في قاعدة البيانات
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

  /// 1) فتح قائمة وسائل الدفع:
  /// - Visa / Mastercard (MEPS)
  /// - Apple Pay (API)
  /// - Google Pay (API)
  /// - CliQ Request to Pay (API)
  /// - الدفع نقداً (فقط لفواتير الورشة والطوارئ للزبائن — ممنوع للعمولات والاشتراكات)
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
    bool? allowCash,
  }) async {
    // الدفع نقداً متاح فقط للزبائن في فاتورة الورشة (wrk) والطوارئ (emg)
    // وممنوع تماماً في العمولات (debt) والاشتراكات (sub)
    final bool canPayCash =
        allowCash ?? (orderType == 'wrk' || orderType == 'emg');

    final chosenMethod = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 540),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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

              // 2) Apple Pay (API)
              Card(
                color: applePayApiEnabled ? Colors.white : AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: applePayApiEnabled ? AppColors.navy : AppColors.border,
                    width: applePayApiEnabled ? 1.2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.apple,
                    color: applePayApiEnabled
                        ? Colors.black
                        : AppColors.textSecondary,
                    size: 30,
                  ),
                  title: Text(
                    'Apple Pay',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: applePayApiEnabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    applePayApiEnabled
                        ? 'دفع فوري وآمن عبر Apple Pay'
                        : 'قريباً — بانتظار تفعيل الربط البنكي',
                  ),
                  trailing: applePayApiEnabled
                      ? const Icon(Icons.arrow_forward_ios,
                          size: 16, color: AppColors.navy)
                      : _soonBadge(),
                  onTap: () {
                    if (applePayApiEnabled) {
                      Navigator.pop(ctx, 'apple_pay');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'خدمة Apple Pay قيد الربط حالياً، يرجى استخدام Visa / Mastercard',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),

              // 3) Google Pay (API) مع الشعار الرسمي بـ 4 ألوان
              Card(
                color: googlePayApiEnabled ? Colors.white : AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color:
                        googlePayApiEnabled ? AppColors.navy : AppColors.border,
                    width: googlePayApiEnabled ? 1.2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: const GooglePayLogo(size: 22),
                  title: Text(
                    'Google Pay',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: googlePayApiEnabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    googlePayApiEnabled
                        ? 'دفع فوري وآمن عبر Google Pay'
                        : 'قريباً — بانتظار تفعيل الربط البنكي',
                  ),
                  trailing: googlePayApiEnabled
                      ? const Icon(Icons.arrow_forward_ios,
                          size: 16, color: AppColors.navy)
                      : _soonBadge(),
                  onTap: () {
                    if (googlePayApiEnabled) {
                      Navigator.pop(ctx, 'google_pay');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'خدمة Google Pay قيد الربط حالياً، يرجى استخدام Visa / Mastercard',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),

              // 4) CliQ Request to Pay (API)
              Card(
                color: cliqRtpApiEnabled ? Colors.white : AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: cliqRtpApiEnabled ? AppColors.navy : AppColors.border,
                    width: cliqRtpApiEnabled ? 1.2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: cliqRtpApiEnabled
                        ? AppColors.navy
                        : AppColors.textSecondary,
                    size: 28,
                  ),
                  title: Text(
                    'CliQ · كليك (Request to Pay)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cliqRtpApiEnabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    cliqRtpApiEnabled
                        ? 'طلب دفع فوري مباشر على تطبيق بنكك'
                        : 'قريباً — بانتظار تفعيل ربط Request to Pay',
                  ),
                  trailing: cliqRtpApiEnabled
                      ? const Icon(Icons.arrow_forward_ios,
                          size: 16, color: AppColors.navy)
                      : _soonBadge(),
                  onTap: () {
                    if (cliqRtpApiEnabled) {
                      Navigator.pop(ctx, 'cliq');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'خدمة CliQ (Request to Pay) قيد الربط البنكي حالياً، يرجى استخدام Visa / Mastercard',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),

              // 5) الدفع نقداً (فقط للزبائن في فاتورة الورشة والطوارئ)
              if (canPayCash) ...[
                const SizedBox(height: 10),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.success, width: 1.2),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined,
                        color: AppColors.success, size: 28),
                    title: const Text('الدفع نقداً (كاش)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('ادفع مباشرة لمقدم الخدمة عند الاستلام'),
                    trailing: const Icon(Icons.arrow_forward_ios,
                        size: 16, color: AppColors.success),
                    onTap: () => Navigator.pop(ctx, 'cash'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (chosenMethod == null || !context.mounted) {
      return false;
    }

    lastChosenMethod = chosenMethod;

    if (chosenMethod == 'cash') {
      return true;
    }

    // 2) الانتقال لصفحة ملخص الدفع + كود الخصم
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
          onExecutePayment:
              (finalTotal, appliedCode, appliedDiscount, customerCliqAlias) {
            return switch (chosenMethod) {
              'apple_pay' => payWithApplePayApi(
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
              'google_pay' => payWithGooglePayApi(
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
              'cliq' => payWithCliqRequestToPay(
                  context: context,
                  amount: finalTotal,
                  title: title,
                  orderType: orderType,
                  referenceId: referenceId,
                  customerCliqAlias: customerCliqAlias ?? '',
                  email: email,
                  phone: phone,
                  name: name,
                  discountCode: appliedCode,
                  discountAmount: appliedDiscount,
                ),
              _ => payWithCardRedirect(
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
            };
          },
        ),
      ),
    );

    return paid == true;
  }

  static Widget _soonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.placeholder,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'قريباً',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 2) الاتصال بدالة create-payment وفتح صفحة MEPS (Visa / Mastercard)
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
    return _invokeHostedGateway(
      context: context,
      edgeFunctionName: 'create-payment',
      paymentMethodLabel: 'Card',
      amount: amount,
      title: title,
      orderType: orderType,
      referenceId: referenceId,
      email: email,
      phone: phone,
      name: name,
      discountCode: discountCode,
      discountAmount: discountAmount,
    );
  }

  /// 3) دالة Apple Pay API (جاهزة للربط فور تفعيل applePayApiEnabled)
  Future<bool> payWithApplePayApi({
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
    if (!applePayApiEnabled) {
      throw Exception(
          'خدمة Apple Pay قيد الربط حالياً، يرجى استخدام Visa / Mastercard');
    }
    return _invokeHostedGateway(
      context: context,
      edgeFunctionName: applePayEdgeFunction,
      paymentMethodLabel: 'ApplePay',
      amount: amount,
      title: title,
      orderType: orderType,
      referenceId: referenceId,
      email: email,
      phone: phone,
      name: name,
      discountCode: discountCode,
      discountAmount: discountAmount,
      extraBody: {
        if (applePayMerchantId.isNotEmpty) 'merchant_id': applePayMerchantId,
      },
    );
  }

  /// 4) دالة Google Pay API (جاهزة للربط فور تفعيل googlePayApiEnabled)
  Future<bool> payWithGooglePayApi({
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
    if (!googlePayApiEnabled) {
      throw Exception(
          'خدمة Google Pay قيد الربط حالياً، يرجى استخدام Visa / Mastercard');
    }
    return _invokeHostedGateway(
      context: context,
      edgeFunctionName: googlePayEdgeFunction,
      paymentMethodLabel: 'GooglePay',
      amount: amount,
      title: title,
      orderType: orderType,
      referenceId: referenceId,
      email: email,
      phone: phone,
      name: name,
      discountCode: discountCode,
      discountAmount: discountAmount,
      extraBody: {
        if (googlePayMerchantId.isNotEmpty) 'merchant_id': googlePayMerchantId,
      },
    );
  }

  /// 5) دالة CliQ Request to Pay (RTP) API (جاهزة للربط فور تفعيل cliqRtpApiEnabled)
  Future<bool> payWithCliqRequestToPay({
    required BuildContext context,
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    required String customerCliqAlias,
    String? email,
    String? phone,
    String? name,
    String? discountCode,
    double discountAmount = 0.0,
  }) async {
    if (!cliqRtpApiEnabled) {
      throw Exception(
          'خدمة CliQ (Request to Pay) قيد الربط البنكي حالياً، يرجى استخدام Visa / Mastercard');
    }

    final cleanAlias = customerCliqAlias.trim();
    if (cleanAlias.isEmpty) {
      throw Exception(
          'يرجى إدخال معرّف CliQ الخاص بك (Alias أو رقم الهاتف) لاستلام طلب الدفع');
    }

    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final safeAmount =
        double.parse(amount.clamp(0.5, 99999.0).toStringAsFixed(2));
    final startedAtIso = DateTime.now().toUtc().toIso8601String();

    final res = await _client.functions.invoke(
      cliqRtpEdgeFunction,
      body: {
        'user_id': user.id,
        'amount': safeAmount,
        'currency': 'JOD',
        'payment_method': 'CliQ_RTP',
        'customer_alias': cleanAlias,
        'merchant_alias': cliqRtpMerchantAlias,
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

    if (res.status != 200 || res.data == null) {
      throw Exception(
          res.data?['error'] ?? 'تعذر إرسال طلب الدفع عبر CliQ (Request to Pay)');
    }

    final status = (res.data['status'] as String? ?? '').toLowerCase();
    if (status == 'paid' || status == 'completed' || status == 'success') {
      return true;
    }

    if (!context.mounted) return false;
    return _showServerVerificationDialog(
      context: context,
      userId: user.id,
      referenceId: referenceId,
      orderType: orderType,
      sinceIso: startedAtIso,
      dialogTitle: 'تأكيد طلب الدفع عبر CliQ',
      dialogMessage:
          'تم إرسال طلب دفع (Request to Pay) إلى تطبيق بنكك على المعرّف: $cleanAlias.\nبعد الموافقة على الطلب من تطبيق البنك، اضغط "التحقق من الدفع".',
    );
  }

  /// استدعاء بوابة دفع إلكترونية (MEPS / Apple Pay / Google Pay)
  Future<bool> _invokeHostedGateway({
    required BuildContext context,
    required String edgeFunctionName,
    required String paymentMethodLabel,
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    String? email,
    String? phone,
    String? name,
    String? discountCode,
    double discountAmount = 0.0,
    Map<String, dynamic>? extraBody,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final safeAmount =
        double.parse(amount.clamp(0.5, 99999.0).toStringAsFixed(2));
    final startedAtIso = DateTime.now().toUtc().toIso8601String();

    final res = await _client.functions.invoke(
      edgeFunctionName,
      body: {
        'user_id': user.id,
        'amount': safeAmount,
        'payment_method': paymentMethodLabel,
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

    if (res.status != 200 || res.data == null) {
      throw Exception(
          res.data?['error'] ?? 'تعذر إنشاء جلسة الدفع من البوابة');
    }

    final status = (res.data['status'] as String? ?? '').toLowerCase();
    if (status == 'paid' || status == 'completed' || status == 'success') {
      return true;
    }

    final String? redirectUrl = res.data['redirect_url'] as String?;
    if (redirectUrl == null || redirectUrl.isEmpty) {
      throw Exception(
          res.data?['error'] ?? 'تعذر الحصول على رابط الدفع من البوابة');
    }

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

      return _showServerVerificationDialog(
        context: context,
        userId: user.id,
        referenceId: referenceId,
        orderType: orderType,
        sinceIso: startedAtIso,
        dialogTitle: 'تأكيد الدفع الإلكتروني',
        dialogMessage:
            'تم فتح بوابة الدفع الآمنة في المتصفح.\nبعد إتمام الدفع بنجاح، اضغط "التحقق من الدفع" لتأكيد العملية من السيرفر.',
      );
    }
  }

  Future<bool> _showServerVerificationDialog({
    required BuildContext context,
    required String userId,
    required String referenceId,
    required String orderType,
    required String sinceIso,
    required String dialogTitle,
    required String dialogMessage,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool checking = false;
        String? statusMsg;
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: Text(dialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dialogMessage),
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
                          userId: userId,
                          referenceId: referenceId,
                          orderType: orderType,
                          sinceIso: sinceIso,
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

  /// تحقق سيرفري على Windows/Web لمنع التلاعب اليدوي بزر تأكيد الدفع
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
          .or('customer_id.eq.$userId,provider_id.eq.$userId')
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
                appt['status'] == 'completed' ||
                appt['progress_step'] == 'completed')) {
          return true;
        }
      } else if (orderType == 'emg') {
        final req = await _client
            .from('mechanic_requests')
            .select('status, payment_status')
            .eq('id', referenceId)
            .maybeSingle();
        if (req != null &&
            (req['payment_status'] == 'paid' || req['status'] == 'completed')) {
          return true;
        }
      } else if (orderType == 'debt') {
        final cust = await _client
            .from('customers')
            .select('pending_commission_debt')
            .eq('id', userId)
            .maybeSingle();
        final remaining =
            (cust?['pending_commission_debt'] as num?)?.toDouble() ?? 1.0;
        if (remaining <= 0.0) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
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
    return cliqRtpMerchantAlias;
  }
}

/// صفحة ملخص الدفع + كود الخصم + تنفيذ الدفع عبر البوابة المختارة
class _MepsCheckoutPage extends StatefulWidget {
  final PayTabsPaymentService service;
  final String paymentMethod; // 'visa' | 'apple_pay' | 'google_pay' | 'cliq'
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
    String? customerCliqAlias,
  ) onExecutePayment;

  const _MepsCheckoutPage({
    required this.service,
    required this.paymentMethod,
    required this.title,
    required this.baseAmount,
    required this.feeAmount,
    required this.orderType,
    required this.referenceId,
    required this.onExecutePayment,
    this.initialDiscountCode,
    this.initialDiscountAmount = 0.0,
    this.userRole,
  });

  @override
  State<_MepsCheckoutPage> createState() => _MepsCheckoutPageState();
}

class _MepsCheckoutPageState extends State<_MepsCheckoutPage> {
  final _promoCtrl = TextEditingController();
  final _cliqAliasCtrl = TextEditingController();

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
    _cliqAliasCtrl.dispose();
    super.dispose();
  }

  double get _finalTotal {
    final total = widget.baseAmount - _discountAmount + widget.feeAmount;
    return double.parse((total < 0 ? 0.0 : total).toStringAsFixed(2));
  }

  String get _methodArabicLabel => switch (widget.paymentMethod) {
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'cliq' => 'CliQ · كليك (Request to Pay)',
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
      final ok = await widget.onExecutePayment(
        _finalTotal,
        _appliedCode,
        _discountAmount,
        widget.paymentMethod == 'cliq' ? _cliqAliasCtrl.text.trim() : null,
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
    final isCliq = widget.paymentMethod == 'cliq';

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص الدفع')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
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
                          'وسيلة الدفع: $_methodArabicLabel',
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

                // حقل إدخال وتفعيل كود الخصم (لا يظهر في سداد العمولات)
                if (widget.orderType != 'debt')
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
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _promoCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
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
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12),
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
                                    style: TextStyle(
                                        color: Colors.red, fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                // حقل معرّف CliQ الخاص بالزبون لإرسال طلب Request to Pay
                if (isCliq) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.navy.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'طلب دفع فوري عبر CliQ (Request to Pay)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.navy),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'أدخل الاسم المستعار (Alias) أو رقم الهاتف المربوط بـ CliQ ليصلك إشعار الدفع مباشرة على تطبيق بنكك:',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _cliqAliasCtrl,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submitPayment(),
                          decoration: InputDecoration(
                            labelText: 'معرّف CliQ الخاص بك (Alias أو الهاتف)',
                            hintText: 'مثال: AHMAD99 أو 079xxxxxxx',
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
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _loading ? null : _submitPayment,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            isCliq
                                ? 'إرسال طلب دفع CliQ (${_finalTotal.toStringAsFixed(2)} د.أ)'
                                : 'ادفع الآن (${_finalTotal.toStringAsFixed(2)} د.أ)',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
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
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500),
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