import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/app_locale_service.dart';
import '../../services/notifications_service.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'customer_subscriptions_screen.dart';

/// شاشة دفع فاتورة الورشة (موحدة مع طرق الدفع الرسمية في التطبيق)
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
      providerId: appointment.workshopId,
      customerProfile: customerProfile,
      onPaymentCompleted: onPaymentCompleted,
    );
  }
}

/// شاشة دفع فاتورة الطوارئ والونش (موحدة مع طرق الدفع الرسمية في التطبيق)
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
      providerId: request.mechanicId,
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
  final String? providerId;
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
    required this.providerId,
    required this.customerProfile,
    required this.onPaymentCompleted,
  });

  @override
  State<_ServiceCheckoutScreen> createState() => _ServiceCheckoutScreenState();
}

class _ServiceCheckoutScreenState extends State<_ServiceCheckoutScreen> {
  final _db = Supabase.instance.client;
  final _loc = AppLocaleService.instance;
  final _customAmountCtrl = TextEditingController();
  final _cliqRefCtrl = TextEditingController();

  String _selectedMethod = 'visa'; // موحّد: 'visa' | 'cliq'
  String _cliqAlias = 'GHYARAK';
  bool _processing = false;

  bool get _needsManualAmount => widget.initialBaseAmount <= 0;

  double get _baseAmount {
    if (!_needsManualAmount) return widget.initialBaseAmount;
    return double.tryParse(_customAmountCtrl.text.trim()) ?? 0.0;
  }

  @override
  void initState() {
    super.initState();
    _loadCliqAlias();
  }

  @override
  void dispose() {
    _customAmountCtrl.dispose();
    _cliqRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCliqAlias() async {
    try {
      final row = await _db
          .from('system_settings')
          .select('value')
          .eq('key', 'cliq_alias')
          .maybeSingle();
      final val = (row?['value'] as String?)?.trim();
      if (val != null && val.isNotEmpty && mounted) {
        setState(() => _cliqAlias = val);
      }
    } catch (_) {}
  }

  Future<void> _submitPayment() async {
    final baseAmount = _baseAmount;
    if (baseAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى إدخال قيمة الفاتورة الصحيحة قبل المتابعة',
            'Please enter a valid invoice amount',
          )),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedMethod == 'cliq' && _cliqRefCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى إدخال رقم مرجع حوالة CliQ أو اسم المحوّل',
            'Please enter your CliQ transfer reference or sender name',
          )),
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
      if (_selectedMethod == 'visa') {
        final ok = await PayTabsPaymentService().payWithCardRedirect(
          context: context,
          amount: totalToPay,
          title:
              '${widget.screenTitle} #${widget.referenceId.substring(0, 6)}',
          orderType: widget.orderType,
          referenceId: widget.referenceId,
          email: widget.customerProfile.email,
          phone: widget.customerProfile.phone,
          name: widget.customerProfile.fullName,
        );
        if (!ok) return;
      }

      await _db.rpc('complete_service_invoice_payment', params: {
        'p_service_kind': widget.serviceKind,
        'p_reference_id': widget.referenceId,
        'p_gross_amount': baseAmount,
        'p_payment_method': _selectedMethod,
        'p_cliq_ref':
            _selectedMethod == 'cliq' ? _cliqRefCtrl.text.trim() : null,
      });

      // إشعار الطرفين بإتمام الدفع
      if (widget.providerId != null && widget.providerId!.isNotEmpty) {
        await NotificationsService.instance.sendNotification(
          targetUserId: widget.providerId!,
          title: _loc.tr('تم دفع الفاتورة بنجاح ✓', 'Invoice Paid ✓'),
          body: _loc.tr(
            'قام الزبون بدفع فاتورة بقيمة ${baseAmount.toStringAsFixed(2)} د.أ (${_selectedMethod.toUpperCase()}).',
            'Customer paid ${baseAmount.toStringAsFixed(2)} JOD via ${_selectedMethod.toUpperCase()}.',
          ),
          type: 'payment_completed',
          referenceId: widget.referenceId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            _selectedMethod == 'cliq'
                ? _loc.tr(
                    'تم إرسال بيانات حوالة CliQ وتأكيد الفاتورة ✓',
                    'CliQ transfer submitted & invoice confirmed ✓',
                  )
                : _loc.tr(
                    'تم إتمام الدفع وربط المبلغ بمحفظة مقدم الخدمة بنجاح ✓',
                    'Payment completed successfully ✓',
                  ),
          ),
        ),
      );
      widget.onPaymentCompleted();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('تعذر إتمام الدفع: $e', 'Payment failed: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
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

    return ListenableBuilder(
      listenable: _loc.langCode,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.screenTitle)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // تنبيه عدم إمكانية إلغاء الفاتورة النهائية
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.navy.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: AppColors.navy, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loc.tr(
                          'فاتورة نهائية معتمدة — لا يمكن إلغاء الطلب بعد إصدار الفاتورة.',
                          'Finalized invoice — orders cannot be cancelled once invoiced.',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

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
                      Text(
                        _loc.tr('تفاصيل الفاتورة', 'Invoice Summary'),
                        style: const TextStyle(
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
                            labelText: _loc.tr(
                              'أدخل قيمة الفاتورة المتفق عليها (د.أ)',
                              'Enter agreed invoice amount (JOD)',
                            ),
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
                        _loc.tr('قيمة الخدمة (قبل العمولة)', 'Service Subtotal'),
                        '${baseAmount.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                      ),
                      const SizedBox(height: 10),
                      _row(
                        isPro
                            ? _loc.tr('عمولة التطبيق (عضوية برو)',
                                'Platform Fee (Pro)')
                            : _loc.tr('عمولة الخدمة (2% - المجانية)',
                                'Service Fee (2%)'),
                        isPro
                            ? _loc.tr('0.00 د.أ (معفى)', '0.00 JOD (Waived)')
                            : '${customerFee.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                        valueColor:
                            isPro ? AppColors.success : AppColors.orange,
                      ),
                      const Divider(height: 24),
                      _row(
                        _loc.tr('الإجمالي المطلوب للدفع', 'Total Due'),
                        '${totalToPay.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
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
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium,
                            color: AppColors.orange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _loc.tr(
                              'اشترك بباقة البرو بـ 1.95 د.أ/شهر وألغِ عمولة الـ 2% مع خصومات على القطع والخدمات!',
                              'Upgrade to Pro (1.95 JOD/mo) for 0% service fee and exclusive discounts!',
                            ),
                            style: const TextStyle(
                              color: AppColors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppColors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                _loc.tr('اختر وسيلة الدفع الموحدة', 'Select Payment Method'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // 1) Visa / Mastercard (MEPS)
              _methodTile(
                code: 'visa',
                icon: Icons.credit_card,
                title: 'Visa / Mastercard (MEPS)',
                subtitle: _loc.tr(
                  'الدفع الإلكتروني الآمن عبر بوابة MEPS',
                  'Secure online card payment via MEPS',
                ),
              ),
              const SizedBox(height: 8),

              // 2) CliQ
              _methodTile(
                code: 'cliq',
                icon: Icons.account_balance_wallet_outlined,
                title: _loc.tr(
                  'CliQ · كليك (تحويل فوري)',
                  'CliQ (Instant Bank Transfer)',
                ),
                subtitle: _loc.tr(
                  'حوّل على معرّف: $_cliqAlias وأدخل رقم المرجع',
                  'Transfer to alias: $_cliqAlias and enter reference',
                ),
              ),
              if (_selectedMethod == 'cliq') ...[
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
                        _loc.tr(
                          'حوّل مبلغ ${totalToPay.toStringAsFixed(2)} د.أ على معرّف CliQ: $_cliqAlias ثم أدخل رقم المرجع:',
                          'Transfer ${totalToPay.toStringAsFixed(2)} JOD to CliQ alias $_cliqAlias and enter reference:',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cliqRefCtrl,
                        decoration: InputDecoration(
                          hintText: _loc.tr(
                            'رقم مرجع الحوالة أو اسم المحوّل',
                            'Transfer reference or sender name',
                          ),
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

              // 3) Apple Pay (قريباً — موحد مع PayTabsPaymentService)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_loc.tr(
                        'خدمة Apple Pay قيد التفعيل، يرجى استخدام Visa / Mastercard أو CliQ',
                        'Apple Pay is coming soon — please use Visa / Mastercard or CliQ',
                      )),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.apple,
                          color: AppColors.textSecondary, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Apple Pay',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              _loc.tr('سيتم تفعيل الخدمة قريباً', 'Coming soon'),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.placeholder,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _loc.tr('قريباً', 'Soon'),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
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
                          _selectedMethod == 'visa'
                              ? _loc.tr(
                                  'الدفع عبر MEPS (${totalToPay.toStringAsFixed(2)} د.أ)',
                                  'Pay via MEPS (${totalToPay.toStringAsFixed(2)} JOD)',
                                )
                              : _loc.tr(
                                  'تأكيد إرسال حوالة CliQ (${totalToPay.toStringAsFixed(2)} د.أ)',
                                  'Confirm CliQ Transfer (${totalToPay.toStringAsFixed(2)} JOD)',
                                ),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _methodTile({
    required String code,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedMethod == code;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedMethod = code),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeLight : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.orange : AppColors.navy,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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