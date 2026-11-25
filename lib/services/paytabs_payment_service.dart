import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';
import 'notifications_service.dart';

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

  /// 1) فتح قائمة وسائل الدفع: Visa/Mastercard (MEPS) و CliQ
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
      builder: (ctx) => Padding(
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

            // 2) CliQ (تحويل فوري محلي داخل الأردن — يُفعّل بعد مطابقة الإدارة)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.navy, width: 1.2),
              ),
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.navy, size: 28),
                title: const Text('CliQ · كليك (تحويل فوري)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'حوّل عبر تطبيق بنكك وأرسل رقم المرجع للمطابقة والتأكيد'),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.navy),
                onTap: () => Navigator.pop(ctx, 'cliq'),
              ),
            ),
            const SizedBox(height: 10),

            // 3) Apple Pay (قريباً)
            Card(
              color: AppColors.background,
              child: ListTile(
                leading: const Icon(Icons.apple,
                    color: AppColors.textSecondary, size: 30),
                title: const Text('Apple Pay',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary)),
                subtitle: const Text('سيتم تفعيل الخدمة قريباً'),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.placeholder,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('قريباً',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'خدمة Apple Pay قيد التفعيل، يرجى استخدام Visa / Mastercard أو CliQ'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if ((chosenMethod != 'visa' && chosenMethod != 'cliq') ||
        !context.mounted) {
      return false;
    }

    // 2) الانتقال لصفحة Checkout وعرض الإجمالي + كود الخصم
    final bool? paid = await Navigator.of(context).push<bool>(
      animatedRoute(
        _MepsCheckoutPage(
          service: this,
          paymentMethod: chosenMethod!,
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

  /// 3) الاتصال بدالة create-payment وفتح صفحة MEPS مع تحقق سيرفري إجباري (موبايل + ويب + ويندوز)
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
    // نأخذ هامش 5 ثوانٍ للخلف لتفادي فروق التوقيت البسيطة بين الجهاز والسيرفر
    final startedAtIso = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 5))
        .toIso8601String();
    final idempotencyKey =
        '${orderType}_${referenceId}_${DateTime.now().millisecondsSinceEpoch}';

    final res = await _client.functions.invoke(
      'create-payment',
      body: {
        'user_id': user.id,
        'amount': safeAmount,
        'payment_method': 'Card',
        'description': title,
        'order_type': orderType,
        'reference_id': referenceId,
        'idempotency_key': idempotencyKey,
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

    Future<bool> verifyNow() => _verifyServerPayment(
          userId: user.id,
          referenceId: referenceId,
          orderType: orderType,
          sinceIso: startedAtIso,
        );

    final bool isMobileNative = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileNative) {
      final bool? webViewVerified = await Navigator.of(context).push<bool>(
        animatedRoute(
          PaymentWebViewScreen(
            redirectUrl: redirectUrl,
            title: title,
            onVerifyServer: verifyNow,
          ),
        ),
      );

      // تحقق نهائي: لن يُرجع true إطلاقاً إلا إذا أكّد السيرفر الدفع فعلياً
      if (webViewVerified == true) {
        return true;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لم يتم تأكيد الدفع من البوابة البنكية. لم يتم تفعيل الخدمة.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } else {
      // على Windows و Web: نفتح صفحة الدفع بالمتصفح الخارجي ثم نتحقق من التأكيد السيرفري
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
                          final verified = await verifyNow();
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

  /// تحقق سيرفري صارم عبر RPC verify_gateway_payment لمنع أي تلاعب أو تأكيد وهمي
  Future<bool> _verifyServerPayment({
    required String userId,
    required String referenceId,
    required String orderType,
    required String sinceIso,
  }) async {
    // 1) الفحص الرسمي عبر دالة السيرفر verify_gateway_payment
    try {
      final rpcRes = await _client.rpc(
        'verify_gateway_payment',
        params: {
          'p_order_type': orderType,
          'p_reference_id': referenceId,
          'p_since': sinceIso,
        },
      );
      if (rpcRes == true) return true;
      if (rpcRes is Map && rpcRes['verified'] == true) return true;
      return false;
    } on PostgrestException catch (e) {
      // fallback فقط في حال لم تُنشأ الدالة بعد في قاعدة البيانات
      if (e.code != 'PGRST202') return false;
    } catch (_) {}

    // 2) Fallback صارم: يفحص فقط السجلات المؤكدة من البوابة (يستبعد حوالات CliQ غير المعتمدة)
    try {
      final txRows = await _client
          .from('wallet_transactions')
          .select('id, status, type')
          .eq('user_id', userId)
          .neq('type', 'cliq_payment')
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
      } else if (orderType == 'emg') {
        final req = await _client
            .from('mechanic_requests')
            .select('status, progress_step')
            .eq('id', referenceId)
            .maybeSingle();
        if (req != null &&
            (req['status'] == 'completed' ||
                req['progress_step'] == 'completed')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// تسجيل طلب حوالة CliQ للمراجعة الإدارية (لا يفعّل الخدمة قبل مطابقة البنك)
  Future<void> submitCliqTransferRequest({
    required double amount,
    required String title,
    required String orderType,
    required String referenceId,
    required String senderNote,
    String? discountCode,
    double discountAmount = 0.0,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول أولاً');

    final noteClean = senderNote.trim();
    if (noteClean.isEmpty) {
      throw Exception('يرجى إدخال رقم الحوالة أو اسم المحوّل');
    }

    await _client.from('wallet_transactions').insert({
      'user_id': user.id,
      'type': 'cliq_payment',
      'amount': amount,
      'status': 'pending_review',
      'description':
          '$title | CliQ ($orderType:${referenceId.substring(0, referenceId.length > 8 ? 8 : referenceId.length)}) | مرجع: $noteClean${discountCode != null && discountCode.isNotEmpty ? ' | كود: $discountCode (-${discountAmount.toStringAsFixed(2)})' : ''}',
    });

    // إشعار جميع الأدمن بمراجعة الحوالة
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
            title: 'حوالة CliQ جديدة بانتظار التأكيد',
            body:
                'مبلغ ${amount.toStringAsFixed(2)} د.أ · $title · مرجع: $noteClean',
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

/// صفحة الـ Checkout التي تعرض الإجمالي + تفعيل كود الخصم + خيار MEPS أو CliQ
class _MepsCheckoutPage extends StatefulWidget {
  final PayTabsPaymentService service;
  final String paymentMethod; // 'visa' | 'cliq'
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
      onPayWithCard;

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
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      if (widget.paymentMethod == 'cliq') {
        await widget.service.submitCliqTransferRequest(
          amount: _finalTotal,
          title: widget.title,
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          senderNote: _cliqRefCtrl.text,
          discountCode: _appliedCode,
          discountAmount: _discountAmount,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تم استلام بيانات الحوالة'),
            content: const Text(
              'تم إرسال مرجع حوالة CliQ للإدارة بنجاح.\nسيتم تفعيل الخدمة أو تسديد الفاتورة تلقائياً فور مطابقة الحوالة البنكية.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        // نُرجع false لأن الحوالة ما زالت pending_review ولم تُؤكد بنكياً بعد
        if (mounted) Navigator.pop(context, false);
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
                      isCliq
                          ? 'وسيلة الدفع: CliQ · كليك (تحويل فوري)'
                          : 'وسيلة الدفع: Visa / Mastercard (MEPS)',
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
                      'بيانات التحويل عبر CliQ',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.navy),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الاسم المستعار (Alias): $_cliqAlias',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _cliqAlias));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('تم نسخ $_cliqAlias للحافظة ✓')),
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
                        hintText: 'مثال: أحمد محمد - مرجع 482910',
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
                            ? 'إرسال مرجع حوالة CliQ (${_finalTotal.toStringAsFixed(2)} د.أ)'
                            : 'ادفع الآن (${_finalTotal.toStringAsFixed(2)} د.أ)',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
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