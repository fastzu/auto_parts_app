import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'customer_subscriptions_screen.dart';

/// شاشة دفع فاتورة الورشة (للزبائن — متاح فيها الكاش والدفع الإلكتروني)
class WorkshopCheckoutScreen extends StatelessWidget {
  final DbWorkshopAppointment appointment;
  final CustomerProfile customerProfile;
  final VoidCallback onPaymentCompleted;

  const WorkshopCheckoutScreen({
    super.key,
    required this.appointment,
    required this.customerProfile,
    required this.onPaymentCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return _ServiceCheckoutScreen(
      screenTitle: 'دفع فاتورة الورشة',
      serviceTitle: appointment.serviceDescription ?? 'صيانة مركبة في الورشة',
      serviceSubtitle:
          'موعد بتاريخ ${appointment.appointmentDate} · ${appointment.appointmentTime}',
      initialBaseAmount: appointment.totalAmount,
      orderType: 'wrk',
      serviceKind: 'workshop',
      referenceId: appointment.id,
      customerProfile: customerProfile,
      onPaymentCompleted: onPaymentCompleted,
    );
  }
}

/// شاشة دفع فاتورة الطوارئ والونش (للزبائن — متاح فيها الكاش والدفع الإلكتروني)
class EmergencyCheckoutScreen extends StatelessWidget {
  final DbMechanicRequest request;
  final CustomerProfile customerProfile;
  final VoidCallback onPaymentCompleted;

  const EmergencyCheckoutScreen({
    super.key,
    required this.request,
    required this.customerProfile,
    required this.onPaymentCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final isWinch = request.serviceType == 'winch';
    return _ServiceCheckoutScreen(
      screenTitle:
          isWinch ? 'دفع فاتورة ونش الطوارئ' : 'دفع فاتورة طوارئ الميكانيكي',
      serviceTitle: (request.description ?? '').trim().isNotEmpty
          ? request.description!
          : (isWinch ? 'خدمة سحب ونش طوارئ' : 'خدمة ميكانيكي طوارئ ميداني'),
      serviceSubtitle: request.carDetails.isNotEmpty
          ? 'المركبة: ${request.carDetails}'
          : 'طلب طوارئ مباشر #${request.id.substring(0, 6)}',
      initialBaseAmount: request.totalAmount,
      orderType: 'emg',
      serviceKind: 'emergency',
      referenceId: request.id,
      customerProfile: customerProfile,
      onPaymentCompleted: onPaymentCompleted,
    );
  }
}

class _ServiceCheckoutScreen extends StatefulWidget {
  final String screenTitle;
  final String serviceTitle;
  final String serviceSubtitle;
  final double initialBaseAmount;
  final String orderType; // 'wrk' | 'emg'
  final String serviceKind; // 'workshop' | 'emergency'
  final String referenceId;
  final CustomerProfile customerProfile;
  final VoidCallback onPaymentCompleted;

  const _ServiceCheckoutScreen({
    required this.screenTitle,
    required this.serviceTitle,
    required this.serviceSubtitle,
    required this.initialBaseAmount,
    required this.orderType,
    required this.serviceKind,
    required this.referenceId,
    required this.customerProfile,
    required this.onPaymentCompleted,
  });

  @override
  State<_ServiceCheckoutScreen> createState() => _ServiceCheckoutScreenState();
}

class _ServiceCheckoutScreenState extends State<_ServiceCheckoutScreen> {
  final _db = Supabase.instance.client;
  final _customAmountCtrl = TextEditingController();
  final _cliqAliasCtrl = TextEditingController();

  // 'visa' | 'apple_pay' | 'google_pay' | 'cliq' | 'cash'
  String _selectedMethod = 'visa';
  bool _processing = false;

  bool get _needsManualAmount => widget.initialBaseAmount <= 0;

  double get _baseAmount {
    if (!_needsManualAmount) return widget.initialBaseAmount;
    return double.tryParse(_customAmountCtrl.text.trim()) ?? 0.0;
  }

  @override
  void dispose() {
    _customAmountCtrl.dispose();
    _cliqAliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final baseAmount = _baseAmount;
    if (baseAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال قيمة الفاتورة الصحيحة قبل المتابعة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedMethod == 'cliq' &&
        PayTabsPaymentService.cliqRtpApiEnabled &&
        _cliqAliasCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'يرجى إدخال معرّف CliQ الخاص بك (Alias أو رقم الهاتف) لاستلام طلب الدفع'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final feeRate = AppSubscriptionCatalog.customerFeeRate(
      widget.customerProfile.subscriptionPlan,
    );
    final customerFee =
        double.parse((baseAmount * feeRate).toStringAsFixed(2));
    final totalToPay =
        double.parse((baseAmount + customerFee).toStringAsFixed(2));

    setState(() => _processing = true);
    try {
      final paymentTitle =
          '${widget.screenTitle} #${widget.referenceId.substring(0, 6)}';
      final payService = PayTabsPaymentService();

      if (_selectedMethod == 'visa') {
        final ok = await payService.payWithCardRedirect(
          context: context,
          amount: totalToPay,
          title: paymentTitle,
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          email: widget.customerProfile.email,
          phone: widget.customerProfile.phone,
          name: widget.customerProfile.fullName,
        );
        if (!ok) return;
      } else if (_selectedMethod == 'apple_pay') {
        final ok = await payService.payWithApplePayApi(
          context: context,
          amount: totalToPay,
          title: paymentTitle,
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          email: widget.customerProfile.email,
          phone: widget.customerProfile.phone,
          name: widget.customerProfile.fullName,
        );
        if (!ok) return;
      } else if (_selectedMethod == 'google_pay') {
        final ok = await payService.payWithGooglePayApi(
          context: context,
          amount: totalToPay,
          title: paymentTitle,
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          email: widget.customerProfile.email,
          phone: widget.customerProfile.phone,
          name: widget.customerProfile.fullName,
        );
        if (!ok) return;
      } else if (_selectedMethod == 'cliq') {
        final ok = await payService.payWithCliqRequestToPay(
          context: context,
          amount: totalToPay,
          title: paymentTitle,
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          customerCliqAlias: _cliqAliasCtrl.text.trim(),
          email: widget.customerProfile.email,
          phone: widget.customerProfile.phone,
          name: widget.customerProfile.fullName,
        );
        if (!ok) return;
      }

      // تنفيذ الدفع وتحديث الفاتورة ومحفظة مقدم الخدمة والذمم والإشعار عبر RPC
      await _db.rpc('complete_service_invoice_payment', params: {
        'p_service_kind': widget.serviceKind,
        'p_reference_id': widget.referenceId,
        'p_gross_amount': baseAmount,
        'p_payment_method': _selectedMethod,
        'p_cliq_ref':
            _selectedMethod == 'cliq' ? _cliqAliasCtrl.text.trim() : null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('تم إتمام دفع الفاتورة وربطها بمحفظة مقدم الخدمة بنجاح ✓'),
        ),
      );
      widget.onPaymentCompleted();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String _submitButtonLabel(double totalToPay) {
    final amt = totalToPay.toStringAsFixed(2);
    return switch (_selectedMethod) {
      'visa' => 'الدفع عبر MEPS ($amt د.أ)',
      'apple_pay' => 'الدفع عبر Apple Pay ($amt د.أ)',
      'google_pay' => 'الدفع عبر Google Pay ($amt د.أ)',
      'cliq' => 'إرسال طلب دفع CliQ ($amt د.أ)',
      _ => 'تأكيد الدفع نقداً ($amt د.أ)',
    };
  }

  @override
  Widget build(BuildContext context) {
    final baseAmount = _baseAmount;
    final feeRate = AppSubscriptionCatalog.customerFeeRate(
      widget.customerProfile.subscriptionPlan,
    );
    final customerFee =
        double.parse((baseAmount * feeRate).toStringAsFixed(2));
    final totalToPay =
        double.parse((baseAmount + customerFee).toStringAsFixed(2));
    final isPro = feeRate == 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.screenTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تفاصيل الفاتورة',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.serviceTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.serviceSubtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (_needsManualAmount) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _customAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'أدخل قيمة الفاتورة المتفق عليها (د.أ)',
                            prefixIcon: const Icon(
                              Icons.payments_outlined,
                              color: AppColors.orange,
                            ),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      _row(
                        'قيمة الخدمة (قبل العمولة)',
                        '${baseAmount.toStringAsFixed(2)} د.أ',
                      ),
                      const SizedBox(height: 10),
                      _row(
                        isPro
                            ? 'عمولة التطبيق (عضوية برو)'
                            : 'عمولة الخدمة (2% - المجانية)',
                        isPro
                            ? '0.00 د.أ (معفى)'
                            : '${customerFee.toStringAsFixed(2)} د.أ',
                        valueColor:
                            isPro ? AppColors.success : AppColors.orange,
                      ),
                      const Divider(height: 24),
                      _row(
                        'الإجمالي المطلوب للدفع',
                        '${totalToPay.toStringAsFixed(2)} د.أ',
                        isBold: true,
                        valueColor: AppColors.navy,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (!isPro)
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      animatedRoute(
                        CustomerSubscriptionsScreen(
                          currentPlanCode:
                              widget.customerProfile.subscriptionPlan,
                          onSubscribed: widget.onPaymentCompleted,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.orange),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.workspace_premium, color: AppColors.orange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'اشترك بباقة البرو بـ 1.95 د.أ/شهر وألغِ عمولة الـ 2% مع خصومات على القطع والخدمات!',
                            style: TextStyle(
                              color: AppColors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppColors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'اختر وسيلة الدفع',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // 1) Visa / Mastercard (MEPS)
              _methodTile(
                code: 'visa',
                leading: Icon(
                  Icons.credit_card,
                  color:
                      _selectedMethod == 'visa' ? AppColors.orange : AppColors.navy,
                  size: 26,
                ),
                title: 'Visa / Mastercard (MEPS)',
                subtitle:
                    'دفع إلكتروني فوري — يُضاف الصافي مباشرة لمحفظة مقدم الخدمة',
              ),
              const SizedBox(height: 8),

              // 2) Apple Pay (API)
              _methodTile(
                code: 'apple_pay',
                enabled: PayTabsPaymentService.applePayApiEnabled,
                leading: Icon(
                  Icons.apple,
                  color: PayTabsPaymentService.applePayApiEnabled
                      ? (_selectedMethod == 'apple_pay'
                          ? AppColors.orange
                          : Colors.black)
                      : AppColors.textSecondary,
                  size: 28,
                ),
                title: 'Apple Pay',
                subtitle: PayTabsPaymentService.applePayApiEnabled
                    ? 'دفع فوري وآمن عبر Apple Pay'
                    : 'قريباً — بانتظار تفعيل الربط البنكي',
                disabledMessage:
                    'خدمة Apple Pay قيد الربط حالياً، يرجى استخدام Visa / Mastercard أو الدفع نقداً',
              ),
              const SizedBox(height: 8),

              // 3) Google Pay (API) مع الشعار الرسمي بـ 4 ألوان
              _methodTile(
                code: 'google_pay',
                enabled: PayTabsPaymentService.googlePayApiEnabled,
                leading: const GooglePayLogo(size: 20),
                title: 'Google Pay',
                subtitle: PayTabsPaymentService.googlePayApiEnabled
                    ? 'دفع فوري وآمن عبر Google Pay'
                    : 'قريباً — بانتظار تفعيل الربط البنكي',
                disabledMessage:
                    'خدمة Google Pay قيد الربط حالياً، يرجى استخدام Visa / Mastercard أو الدفع نقداً',
              ),
              const SizedBox(height: 8),

              // 4) CliQ Request to Pay (API)
              _methodTile(
                code: 'cliq',
                enabled: PayTabsPaymentService.cliqRtpApiEnabled,
                leading: Icon(
                  Icons.account_balance,
                  color: PayTabsPaymentService.cliqRtpApiEnabled
                      ? (_selectedMethod == 'cliq'
                          ? AppColors.orange
                          : AppColors.navy)
                      : AppColors.textSecondary,
                  size: 26,
                ),
                title: 'CliQ · كليك (Request to Pay)',
                subtitle: PayTabsPaymentService.cliqRtpApiEnabled
                    ? 'طلب دفع فوري مباشر على تطبيق بنكك'
                    : 'قريباً — بانتظار تفعيل ربط Request to Pay',
                disabledMessage:
                    'خدمة CliQ (Request to Pay) قيد الربط البنكي حالياً، يرجى استخدام Visa / Mastercard أو الدفع نقداً',
              ),

              if (_selectedMethod == 'cliq' &&
                  PayTabsPaymentService.cliqRtpApiEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أدخل معرّف CliQ الخاص بك لإرسال طلب دفع بمبلغ ${totalToPay.toStringAsFixed(2)} د.أ مباشرة إلى تطبيق بنكك:',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cliqAliasCtrl,
                        decoration: InputDecoration(
                          hintText: 'الاسم المستعار (Alias) أو رقم الهاتف',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // 5) الدفع نقداً (متاح للزبائن في فاتورة الورشة والطوارئ فقط)
              _methodTile(
                code: 'cash',
                leading: Icon(
                  Icons.payments_outlined,
                  color: _selectedMethod == 'cash'
                      ? AppColors.orange
                      : AppColors.navy,
                  size: 26,
                ),
                title: 'الدفع نقداً (كاش)',
                subtitle:
                    'ادفع مباشرة لمقدم الخدمة وتُحتسب عمولة المنصة تلقائياً على محفظته',
              ),
              const SizedBox(height: 22),
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
                  onPressed: _processing ? null : _submitPayment,
                  child: _processing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _submitButtonLabel(totalToPay),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodTile({
    required String code,
    required Widget leading,
    required String title,
    required String subtitle,
    bool enabled = true,
    String? disabledMessage,
  }) {
    final selected = enabled && _selectedMethod == code;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (enabled) {
          setState(() => _selectedMethod = code);
        } else if (disabledMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(disabledMessage)),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: !enabled
              ? AppColors.background
              : (selected ? AppColors.orangeLight : AppColors.surface),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.placeholder,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'قريباً',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              )
            else
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.orange : AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String label,
    String val, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          val,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w800 : FontWeight.bold,
            fontSize: isBold ? 17 : 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}