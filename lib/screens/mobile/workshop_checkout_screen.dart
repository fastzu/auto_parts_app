import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'customer_subscriptions_screen.dart';

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
          '${appointment.appointmentDate} · ${appointment.appointmentTime}',
      initialBaseAmount: appointment.totalAmount,
      orderType: 'wrk',
      serviceKind: 'workshop',
      referenceId: appointment.id,
      customerProfile: customerProfile,
      onPaymentCompleted: onPaymentCompleted,
    );
  }
}

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
          : (isWinch ? 'خدمة سحب ونش طوارئ' : 'خدمة ميكانيكي طوارئ'),
      serviceSubtitle: request.carDetails.isNotEmpty
          ? 'المركبة: ${request.carDetails}'
          : 'طلب طوارئ #${request.id.substring(0, 6)}',
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
  final String orderType;
  final String serviceKind;
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
  final _cliqRefCtrl = TextEditingController();

  String _selectedMethod = 'visa'; // 'visa' | 'apple_pay' | 'google_pay' | 'cliq' | 'cash'
  String _cliqAlias = 'GHAYARAKJO';
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
        const SnackBar(
          content: Text('يرجى إدخال قيمة الفاتورة الصحيحة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedMethod == 'cliq' && _cliqRefCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال رقم مرجع حوالة CliQ أو اسم المحوّل'),
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
      final isOnlineGateway = _selectedMethod == 'visa' ||
          _selectedMethod == 'apple_pay' ||
          _selectedMethod == 'google_pay';

      if (isOnlineGateway) {
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

      // تمرير 'visa' للوسائل الإلكترونية حتى يضيف الـ RPC الصافي مباشرة إلى محفظة المزود
      final rpcMethod = isOnlineGateway ? 'visa' : _selectedMethod;

      await _db.rpc('complete_service_invoice_payment', params: {
        'p_service_kind': widget.serviceKind,
        'p_reference_id': widget.referenceId,
        'p_gross_amount': baseAmount,
        'p_payment_method': rpcMethod,
        'p_cliq_ref':
            _selectedMethod == 'cliq' ? _cliqRefCtrl.text.trim() : null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('تم إتمام الدفع بنجاح ✓'),
        ),
      );
      widget.onPaymentCompleted();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إتمام الدفع: $e'),
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

    return Scaffold(
      appBar: AppBar(title: Text(widget.screenTitle)),
      body: ListView(
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
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'قيمة الفاتورة (د.أ)',
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
                    'قيمة الخدمة',
                    '${baseAmount.toStringAsFixed(2)} د.أ',
                  ),
                  const SizedBox(height: 10),
                  _row(
                    isPro ? 'عمولة التطبيق (Pro)' : 'عمولة الخدمة (2%)',
                    isPro
                        ? '0.00 د.أ'
                        : '${customerFee.toStringAsFixed(2)} د.أ',
                    valueColor: isPro ? AppColors.success : AppColors.orange,
                  ),
                  const Divider(height: 24),
                  _row(
                    'الإجمالي للدفع',
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
                      currentPlanCode: widget.customerProfile.subscriptionPlan,
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
                        'اشترك بباقة Pro بـ 1.95 د.أ/شهر وألغِ عمولة الـ 2%',
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
            'وسيلة الدفع',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _methodTile(
            code: 'visa',
            leading: Icon(
              Icons.credit_card,
              color:
                  _selectedMethod == 'visa' ? AppColors.orange : AppColors.navy,
              size: 26,
            ),
            title: 'Visa / Mastercard',
          ),
          const SizedBox(height: 8),
          _methodTile(
            code: 'apple_pay',
            leading: const Icon(Icons.apple, color: Colors.black, size: 28),
            title: 'Apple Pay',
          ),
          const SizedBox(height: 8),
          _methodTile(
            code: 'google_pay',
            leading: const GooglePayLogo(height: 26),
            title: 'Google Pay',
          ),
          const SizedBox(height: 8),
          _methodTile(
            code: 'cliq',
            leading: Icon(
              Icons.account_balance,
              color:
                  _selectedMethod == 'cliq' ? AppColors.orange : AppColors.navy,
              size: 24,
            ),
            title: 'CliQ ($_cliqAlias)',
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
              child: TextField(
                controller: _cliqRefCtrl,
                decoration: InputDecoration(
                  hintText: 'رقم مرجع الحوالة أو اسم المحوّل',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _methodTile(
            code: 'cash',
            leading: Icon(
              Icons.payments_outlined,
              color: _selectedMethod == 'cash'
                  ? AppColors.orange
                  : AppColors.success,
              size: 24,
            ),
            title: 'Cash (نقداً)',
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
                      'تأكيد الدفع (${totalToPay.toStringAsFixed(2)} د.أ)',
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
  }

  Widget _methodTile({
    required String code,
    required Widget leading,
    required String title,
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
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
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