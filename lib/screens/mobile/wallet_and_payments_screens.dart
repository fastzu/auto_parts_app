import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'workshop_checkout_screen.dart';

/// عرض السياسات الكاملة للتطبيق (شروط المستخدم، شروط المزود، سياسة الـ 24 ساعة، خصوصية Apple، سياسة الموقع بنمط أوبر)
/// مترجمة بالكامل للغتين العربية والإنجليزية حسب لغة التطبيق
void showAppLegalPoliciesSheet(BuildContext context) {
  final loc = AppLocaleService.instance;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) {
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.policy_rounded, color: AppColors.navy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.tr(
                          'الشروط والأحكام وسياسة الخصوصية — غيارك',
                          'Terms, Refund & Privacy Policy — Ghiyarak',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(18),
                  children: [
                    _policyCard(
                      icon: Icons.person_outline,
                      title: loc.tr(
                        '1. شروط وأحكام المستخدم العادي',
                        '1. Regular User Terms & Conditions',
                      ),
                      body: loc.tr(
                        '• يلتزم المستخدم بتقديم بيانات دقيقة للمركبة والموقع عند طلب خدمات الصيانة أو الطوارئ أو شراء القطع.\n'
                        '• تسعيرة خدمات الطوارئ والونش تعتمد على عرض السعر المباشر من المزود، وللمستخدم كامل الحرية بقبول العرض أو رفضه ليبحث التطبيق تلقائياً عن مزود آخر.\n'
                        '• ممنوع إلغاء الطلب أو الفاتورة أو الدفع نهائياً بعد قيام الورشة أو المزود بإصدار الفاتورة النهائية.\n'
                        '• يظهر شريط التتبع المباشر (البروجرس) لمواعيد الورشة المحجوزة مسبقاً قبل الموعد بساعة واحدة فقط.\n'
                        '• يلتزم المستخدم بتقييم مقدم الخدمة بمصداقية بعد إتمام الدفع واستلام المركبة.',
                        '• Users must provide accurate vehicle and pickup details when booking workshops, roadside assistance, or purchasing parts.\n'
                        '• Roadside mechanic & towing pricing is quote-based: providers send a direct price quote, and users may accept or decline (automatically searching for another available provider).\n'
                        '• Once a workshop or roadside provider issues the final invoice, order and payment cancellation is strictly prohibited.\n'
                        '• For future/next-day workshop appointments, the live progress tracker activates 1 hour prior to the scheduled appointment slot.\n'
                        '• Users are invited to submit honest star ratings and reviews after completing payment.',
                      ),
                    ),
                    _policyCard(
                      icon: Icons.handyman_outlined,
                      title: loc.tr(
                        '2. شروط المزودين (ورش، ميكانيكي، ونش، تجار) وسياسة الغرامات',
                        '2. Provider Terms, Workshop Capacity Lock & Penalties',
                      ),
                      body: loc.tr(
                        '• قفل سعة الورشة: لا يمكن لصاحب الورشة قبول طلبات أو مواعيد جديدة بمجرد امتلاء السعة القصوى للورشة بالطلبات النشطة حتى يتم إنهاء الصيانة وإصدار الفاتورة رسمياً.\n'
                        '• سياسة منع التلاعب والإلغاءات المتكررة: في حال تجاوز عدد الطلبات الملغية من قبل المزود عدد الطلبات المكتملة والمفوترة، يُصدر النظام تلقائياً تنبيهاً وإنذاراً رسمياً على حساب المزود مع فرض غرامة مالية تُضاف تلقائياً إلى ذمم العمولة.\n'
                        '• يلتزم المزود بتقديم عروض أسعار واضحة وعادلة وإصدار الفاتورة فور الانتهاء من العمل.\n'
                        '• تتم مراجعة طلبات سحب الرصيد البنكي (IBAN أو CliQ) وتحويلها بعد التحقق من عدم وجود ذمم عمولات مستحقة.',
                        '• Workshop Capacity Lock: Workshops cannot accept new active bookings once their max car capacity is full until active jobs are finished and billed.\n'
                        '• Anti-Manipulation & Cancellation Penalty: If a provider’s cancelled orders exceed completed billed orders, the system automatically issues an account warning and adds a financial penalty to pending commission dues.\n'
                        '• Providers must submit transparent quotes and issue final invoices promptly upon job completion.\n'
                        '• Wallet payout requests (Bank IBAN or CliQ) are verified and settled after checking pending commission balances.',
                      ),
                    ),
                    _policyCard(
                      icon: Icons.currency_exchange_rounded,
                      title: loc.tr(
                        '3. سياسة استرداد قيمة الباقات (Refund Policy)',
                        '3. Subscription Refund Policy (24 Hours Only)',
                      ),
                      body: loc.tr(
                        '• يحق للمستخدم أو المزود طلب استرداد كامل قيمة الاشتراك المدفوع (Refund) خلال 24 ساعة فقط من وقت تفعيل الاشتراك.\n'
                        '• بعد مرور 24 ساعة من وقت الاشتراك، لا يمكن استرداد قيمة الباقة ويستمر الاشتراك فعالاً حتى نهاية مدته.\n'
                        '• عند الموافقة على طلب الاسترداد خلال الـ 24 ساعة، يتم إلغاء مزايا الباقة وإعادة الحساب للباقة المجانية ورد المبلغ عبر نفس وسيلة الدفع.',
                        '• Customers and providers may request a full refund of any paid subscription within 24 hours of activation ONLY.\n'
                        '• After 24 hours have elapsed from subscription purchase, fees are non-refundable and benefits remain active until expiration.\n'
                        '• Approved 24-hour refunds revert the account to the Free plan and return funds via the original payment method.',
                      ),
                    ),
                    _policyCard(
                      icon: Icons.privacy_tip_outlined,
                      title: loc.tr(
                        '4. سياسة الخصوصية (متوافقة مع متطلبات Apple App Store)',
                        '4. Privacy Policy (Apple App Store Compliant)',
                      ),
                      body: loc.tr(
                        '• البيانات التي نجمعها: الاسم، رقم الهاتف، البريد الإلكتروني، تفاصيل المركبة، وموقعك الجغرافي أثناء استخدام الخدمة فقط، بالإضافة إلى صور القطع أو الورشة التي تختار رفعها.\n'
                        '• استخدام البيانات: تُستخدم البيانات حصراً لتنفيذ الطلبات، ربطك بأقرب ورشة أو ونش، إرسال إشعارات حالة طلباتك، وتوثيق الفواتير والمدفوعات.\n'
                        '• عدم البيع لطرف ثالث: لا نقوم ببيع أو تأجير بياناتك الشخصية لأي جهات إعلانية أو أطراف ثالثة.\n'
                        '• حق حذف الحساب نهائياً (Apple Guideline 5.1.1(v)): يمكنك حذف حسابك وبياناتك الشخصية نهائياً في أي وقت من داخل شاشة "الملف الشخصي" بشرط تسوية أي ذمم مالية مستحقة.\n'
                        '• التواصل بشأن الخصوصية: ${EnvConfig.supportEmail}',
                        '• Data We Collect: Name, phone number, email address, vehicle details, active location when using roadside/workshop services, and photos you voluntarily upload.\n'
                        '• Purpose of Processing: Data is used strictly to fulfill orders, match you with nearby workshops/towing, send real-time job notifications, and verify invoices/payments.\n'
                        '• No Third-Party Data Sale: We never sell or rent your personal data to brokers or third-party advertisers.\n'
                        '• In-App Account Deletion (Apple Guideline 5.1.1(v)): You can permanently delete your account and personal data anytime from your Profile screen, provided no unpaid financial balance exists.\n'
                        '• Privacy Contact: ${EnvConfig.supportEmail}',
                      ),
                    ),
                    _policyCard(
                      icon: Icons.my_location_rounded,
                      title: loc.tr(
                        '5. سياسة الموقع الجغرافي (نمط أوبر — بدون تخزين سجل تاريخي)',
                        '5. Location Policy (Uber-Style Zero-History Architecture)',
                      ),
                      body: loc.tr(
                        '• لا يقوم تطبيق غيارك بتخزين سجل تاريخي لتحركات السائقين أو المستخدمين على قاعدة البيانات.\n'
                        '• يتم تحديث الإحداثيات الحالية فقط عبر استبدال الموقع السابق بالموقع الجديد لحظياً (In-Place Update) أثناء وجود طلب نشط أو تفعيل حالة "متاح" للمزود.\n'
                        '• يُستخدم الموقع حصراً لحساب المسافة لأقرب ميكانيكي أو ونش، وإظهار حركة المزود على الخريطة أثناء توجهه إليك، وإشعار الورشة بوصولك.',
                        '• Ghiyarak does NOT store historical GPS breadcrumbs or location logs for drivers or customers.\n'
                        '• Coordinates are overwritten in-place (replacing the previous coordinate with the latest one) strictly while an order is active or while a provider is toggled Online.\n'
                        '• Location is used solely to match the nearest provider, show live provider arrival on the map, and confirm arrival at workshops.',
                      ),
                    ),
                    _policyCard(
                      icon: Icons.verified_user_outlined,
                      title: loc.tr(
                        '6. أمان المدفوعات والتحقق الخادمي',
                        '6. Payment Security & Server-Side Verification',
                      ),
                      body: loc.tr(
                        '• تتم معالجة بطاقات Visa و Mastercard عبر بوابة MEPS المعتمدة بتشفير كامل دون حفظ أرقام البطاقات داخل التطبيق.\n'
                        '• لا يُعتمد أي دفع إلكتروني ولا تُفعّل أي باقة أو فاتورة إلا بعد التحقق الرسمي المباشر من خادم بوابة الدفع.\n'
                        '• حوالات CliQ تخضع للمراجعة المالية قبل التفعيل النهائي.',
                        '• Visa & Mastercard transactions are processed through MEPS with full encryption; card details are never stored in the app.\n'
                        '• No subscription or invoice is marked paid unless verified server-side against payment gateway records.\n'
                        '• CliQ transfers undergo financial review before final confirmation.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _policyCard({
  required IconData icon,
  required String title,
  required String body,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.navy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.65,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/// شاشة محفظة المزود + طلب سحب رصيد بنكي / CliQ (متطابقة 100% مع توقيع RPC)
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

  Future<void> _openWithdrawDialog() async {
    final amountCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final ibanCtrl = TextEditingController();
    final holderCtrl =
        TextEditingController(text: widget.profile.fullName ?? '');
    String method = 'cliq';
    bool submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(_loc.tr('طلب سحب رصيد من المحفظة', 'Request Payout')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: _loc.tr('طريقة التحويل', 'Payout Method'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'cliq',
                      child: Text(_loc.tr('حوالة CliQ فورية', 'CliQ Alias')),
                    ),
                    DropdownMenuItem(
                      value: 'bank_iban',
                      child:
                          Text(_loc.tr('حساب بنكي (IBAN)', 'Bank Transfer IBAN')),
                    ),
                  ],
                  onChanged: submitting
                      ? null
                      : (v) => setS(() => method = v ?? 'cliq'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  enabled: !submitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _loc.tr('المبلغ المطلوب (د.أ)', 'Amount (JOD)'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankCtrl,
                  enabled: !submitting,
                  decoration: InputDecoration(
                    labelText: _loc.tr('اسم البنك', 'Bank Name'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ibanCtrl,
                  enabled: !submitting,
                  decoration: InputDecoration(
                    labelText: method == 'cliq'
                        ? _loc.tr('اسم معرّف CliQ أو رقم الهاتف',
                            'CliQ Alias or Mobile')
                        : 'IBAN',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holderCtrl,
                  enabled: !submitting,
                  decoration: InputDecoration(
                    labelText: _loc.tr('اسم صاحب الحساب', 'Account Holder Name'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: Text(_loc.tr('إلغاء', 'Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final amt =
                          double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                      if (amt <= 0 ||
                          ibanCtrl.text.trim().isEmpty ||
                          holderCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red,
                            content: Text(_loc.tr(
                              'يرجى تعبئة جميع الحقول المطلوبة بشكل صحيح',
                              'Please fill in all required payout fields',
                            )),
                          ),
                        );
                        return;
                      }
                      setS(() => submitting = true);
                      try {
                        await _db.rpc('request_wallet_withdrawal', params: {
                          'p_amount': amt,
                          'p_payout_method': method,
                          'p_iban_or_alias': ibanCtrl.text.trim(),
                          'p_bank_name': bankCtrl.text.trim().isEmpty
                              ? 'Jordan Bank'
                              : bankCtrl.text.trim(),
                          'p_account_holder': holderCtrl.text.trim(),
                        });
                        widget.onRefreshProfile();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.success,
                              content: Text(_loc.tr(
                                'تم إرسال طلب السحب بنجاح ✓ قيد المراجعة البنكية',
                                'Payout request submitted ✓ Pending review',
                              )),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setS(() => submitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red,
                              content: Text('$e'),
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
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_loc.tr('تأكيد السحب', 'Submit Payout')),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    bankCtrl.dispose();
    ibanCtrl.dispose();
    holderCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (p.warningsCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loc.tr(
                      'تنبيه: يوجد (${p.warningsCount}) إنذار على حسابك بسبب الإلغاءات المتكررة.',
                      'Warning: You have (${p.warningsCount}) account warnings due to high cancellation rate.',
                    ),
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _loc.tr('الرصيد المتاح للسحب', 'Available Balance'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '${p.walletBalance.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (p.pendingCommissionDebt > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${_loc.tr("ذمم عمولات/غرامات مستحقة", "Pending Dues")}: ${p.pendingCommissionDebt.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                  style: const TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _openWithdrawDialog,
                  icon: const Icon(Icons.account_balance_rounded),
                  label: Text(_loc.tr(
                    'سحب الأرباح (بنك / CliQ)',
                    'Withdraw Earnings (Bank / CliQ)',
                  )),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _loc.tr('طلبات السحب الأخيرة', 'Recent Payout Requests'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('withdrawal_requests')
              .stream(primaryKey: ['id'])
              .eq('provider_id', p.id)
              .order('created_at', ascending: false),
          builder: (_, snap) {
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _loc.tr('لا توجد طلبات سحب سابقة', 'No payout requests yet'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              );
            }
            return Column(
              children: rows.map((w) {
                final st = (w['status'] as String?) ?? 'pending';
                final amt = (w['amount'] as num?)?.toDouble() ?? 0.0;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      st == 'paid'
                          ? Icons.check_circle
                          : (st == 'rejected'
                              ? Icons.cancel
                              : Icons.hourglass_top),
                      color: st == 'paid'
                          ? AppColors.success
                          : (st == 'rejected' ? Colors.red : AppColors.orange),
                    ),
                    title: Text(
                      '${amt.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")} · ${w['payout_method'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                        '${w['bank_name'] ?? ''} · ${w['iban_or_alias'] ?? ''}'),
                    trailing: Text(
                      st,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          _loc.tr('سجل حركات المحفظة', 'Wallet Transactions'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('wallet_transactions')
              .stream(primaryKey: ['id'])
              .eq('provider_id', p.id)
              .order('created_at', ascending: false),
          builder: (_, snap) {
            final txs = (snap.data ?? [])
                .map(DbWalletTransaction.fromMap)
                .toList();
            if (txs.isEmpty) {
              return Text(
                _loc.tr('لا توجد حركات مالية بعد', 'No transactions yet'),
                style: const TextStyle(color: AppColors.textSecondary),
              );
            }
            return Column(
              children: txs.map((t) {
                final isPenalty = t.transactionType == 'cancellation_penalty';
                return Card(
                  child: ListTile(
                    title: Text(
                      isPenalty
                          ? _loc.tr('غرامة إلغاءات متكررة',
                              'Cancellation Penalty')
                          : '${t.transactionType} · ${t.paymentMethod}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isPenalty ? Colors.red : AppColors.navy,
                      ),
                    ),
                    subtitle: Text(
                      '${_loc.tr("الإجمالي", "Gross")}: ${t.grossAmount.toStringAsFixed(2)} · ${_loc.tr("العمولة", "Fee")}: ${t.commissionAmount.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '${isPenalty ? "-" : "+"}${t.netAmount.abs().toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isPenalty ? Colors.red : AppColors.success,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

/// شاشة فواتير ومدفوعات العميل (دفع موحّد بدون إلغاء بعد الإصدار)
class CustomerPaymentsHistoryScreen extends StatelessWidget {
  final CustomerProfile profile;
  const CustomerPaymentsHistoryScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final loc = AppLocaleService.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('فواتيري ومدفوعاتي', 'My Invoices & Payments')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            loc.tr('فواتير الورش بانتظار الدفع', 'Unpaid Workshop Invoices'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: db
                .from('workshop_appointments')
                .stream(primaryKey: ['id'])
                .eq('user_id', profile.id)
                .order('created_at', ascending: false),
            builder: (_, snap) {
              final unpaid = (snap.data ?? [])
                  .map(DbWorkshopAppointment.fromMap)
                  .where((a) =>
                      a.totalAmount > 0 &&
                      a.paymentStatus != 'paid' &&
                      a.status != 'cancelled')
                  .toList();
              if (unpaid.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    loc.tr('لا توجد فواتير ورش غير مدفوعة',
                        'No unpaid workshop invoices'),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return Column(
                children: unpaid.map((a) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const Icon(Icons.build_circle,
                          color: AppColors.orange),
                      title: Text(
                        a.serviceDescription ??
                            loc.tr('فاتورة ورشة', 'Workshop Invoice'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${a.appointmentDate} · ${a.totalAmount.toStringAsFixed(2)} ${loc.tr("د.أ", "JOD")}',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          animatedRoute(
                            WorkshopCheckoutScreen(
                              appointment: a,
                              customerProfile: profile,
                              onPaymentCompleted: () {},
                            ),
                          ),
                        ),
                        child: Text(loc.tr('ادفع الآن', 'Pay Now')),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            loc.tr('فواتير الطوارئ والونش بانتظار الدفع',
                'Unpaid Roadside & Towing Invoices'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: db
                .from('mechanic_requests')
                .stream(primaryKey: ['id'])
                .eq('user_id', profile.id)
                .order('created_at', ascending: false),
            builder: (_, snap) {
              final unpaid = (snap.data ?? [])
                  .map(DbMechanicRequest.fromMap)
                  .where((r) =>
                      r.totalAmount > 0 &&
                      r.paymentStatus != 'paid' &&
                      r.status != 'cancelled' &&
                      r.status != 'quote_sent' &&
                      r.status != 'pending')
                  .toList();
              if (unpaid.isEmpty) {
                return Text(
                  loc.tr('لا توجد فواتير طوارئ غير مدفوعة',
                      'No unpaid emergency invoices'),
                  style: const TextStyle(color: AppColors.textSecondary),
                );
              }
              return Column(
                children: unpaid.map((r) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(
                        r.serviceType == 'winch'
                            ? Icons.local_shipping
                            : Icons.car_crash,
                        color: AppColors.orange,
                      ),
                      title: Text(
                        r.description ?? loc.tr('فاتورة طوارئ', 'Roadside Bill'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${r.carDetails} · ${r.totalAmount.toStringAsFixed(2)} ${loc.tr("د.أ", "JOD")}',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          animatedRoute(
                            EmergencyCheckoutScreen(
                              request: r,
                              customerProfile: profile,
                              onPaymentCompleted: () {},
                            ),
                          ),
                        ),
                        child: Text(loc.tr('ادفع الآن', 'Pay Now')),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// شاشة الملف الشخصي: تعديل البيانات + تغيير موقع الورشة GPS/خريطة + Refund خلال 24 ساعة + حذف الحساب نهائياً
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
  final _locationService = LocationService();

  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.profile.fullName ?? '');
  late final TextEditingController _phoneCtrl =
      TextEditingController(text: widget.profile.phone ?? '');
  late final TextEditingController _addressCtrl =
      TextEditingController(text: widget.profile.workshopAddress ?? '');

  late double? _workshopLat = widget.profile.workshopLatitude;
  late double? _workshopLng = widget.profile.workshopLongitude;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await _db.from('customers').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (widget.profile.role == 'mechanic') ...{
          'workshop_address': _addressCtrl.text.trim(),
          'workshop_latitude': _workshopLat,
          'workshop_longitude': _workshopLng,
        },
      }).eq('id', widget.profile.id);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(_loc.tr(
                'تم حفظ بيانات الملف الشخصي بنجاح ✓', 'Profile saved ✓')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickWorkshopLocationOnMap() async {
    LatLng selected = LatLng(
      _workshopLat ?? 31.9539,
      _workshopLng ?? 35.9106,
    );
    final mapCtrl = MapController();

    final picked = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loc.tr(
                          'اضغط على الخريطة لتحديد موقع الورشة الجديد',
                          'Tap map to choose new workshop location',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.my_location,
                          color: AppColors.orange),
                      onPressed: () async {
                        final res = await _locationService.getCurrentLocation();
                        setS(() => selected = res.coordinates);
                        mapCtrl.move(selected, 15.5);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FlutterMap(
                  mapController: mapCtrl,
                  options: MapOptions(
                    initialCenter: selected,
                    initialZoom: 14.5,
                    onTap: (_, pos) => setS(() => selected = pos),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.autoparts.ghiyarak',
                      retinaMode: true,
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: selected,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_on,
                          color: AppColors.orange,
                          size: 42,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, selected),
                    child: Text(_loc.tr(
                        'تأكيد موقع الورشة الجديد', 'Confirm Workshop Location')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked != null) {
      final addr = await _locationService.getAddressFromLatLng(picked);
      if (mounted) {
        setState(() {
          _workshopLat = picked.latitude;
          _workshopLng = picked.longitude;
          _addressCtrl.text = addr;
        });
      }
    }
  }

  Future<void> _requestSubscriptionRefund() async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_loc.tr(
          'طلب استرداد الباقة (خلال 24 ساعة فقط)',
          'Subscription Refund (Within 24h Only)',
        )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _loc.tr(
                'يمكنك استرداد قيمة الباقة خلال 24 ساعة فقط من وقت الاشتراك.',
                'Refunds are eligible within 24 hours of subscription activation only.',
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: _loc.tr('سبب طلب الاسترداد', 'Reason for refund'),
              ),
            ),
          ],
        ),
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
            child: Text(_loc.tr('إرسال الطلب', 'Submit Refund')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _db.rpc('request_subscription_refund', params: {
          'p_reason': reasonCtrl.text.trim(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.success,
              content: Text(_loc.tr(
                'تم استلام طلب الاسترداد بنجاح ✓ ستتم مراجعته من الإدارة.',
                'Refund request received ✓ Pending admin approval.',
              )),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('$e')),
          );
        }
      }
    }
    reasonCtrl.dispose();
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _loc.tr('حذف الحساب نهائياً', 'Delete Account Permanently'),
          style: const TextStyle(color: Colors.red),
        ),
        content: Text(_loc.tr(
          'هل أنت متأكد من حذف حسابك وبياناتك الشخصية نهائياً؟ لا يمكن التراجع عن هذا الإجراء.',
          'Are you sure you want to permanently delete your account and personal data? This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_loc.tr('تراجع', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_loc.tr('نعم، احذف حسابي', 'Yes, Delete Account')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _db.rpc('delete_my_account');
        await _db.auth.signOut();
        widget.onSignedOut?.call();
        if (mounted) {
          Navigator.popUntil(context, (r) => r.isFirst);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('$e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return ValueListenableBuilder<String>(
      valueListenable: _loc.langCode,
      builder: (_, __, ___) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('الملف الشخصي', 'My Profile')),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: _loc.tr('الاسم الكامل', 'Full Name'),
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                decoration: InputDecoration(
                  labelText: _loc.tr('رقم الهاتف', 'Phone Number'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (p.role == 'mechanic') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    labelText: _loc.tr('عنوان الورشة', 'Workshop Address'),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.navy),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _pickWorkshopLocationOnMap,
                  icon: const Icon(Icons.map_rounded, color: AppColors.navy),
                  label: Text(
                    _loc.tr(
                      'تغيير موقع الورشة على الخريطة (GPS)',
                      'Change Workshop Location on Map (GPS)',
                    ),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
              const SizedBox(height: 18),
              if (p.subscriptionPlan != 'free')
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.currency_exchange,
                        color: AppColors.orange),
                    title: Text(
                      _loc.tr('طلب استرداد الاشتراك (خلال 24 ساعة)',
                          'Request Subscription Refund (24h)'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _loc.tr('الباقة الحالية: ${p.subscriptionPlan}',
                          'Current plan: ${p.subscriptionPlan}'),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                    onTap: _requestSubscriptionRefund,
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.policy_outlined,
                      color: AppColors.navy),
                  title: Text(
                    _loc.tr('الشروط والأحكام وسياسة الخصوصية',
                        'Terms & Privacy Policy'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () => showAppLegalPoliciesSheet(context),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: _confirmDeleteAccount,
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(
                  _loc.tr('حذف الحساب نهائياً', 'Delete Account Permanently'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// شاشة الدعم الفني والسياسات القانونية
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    return ValueListenableBuilder<String>(
      valueListenable: loc.langCode,
      builder: (_, __, ___) {
        return Scaffold(
          appBar: AppBar(
            title: Text(loc.tr('الدعم الفني — غيارك', 'Support — Ghiyarak')),
          ),
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
                        'We are here 24/7 to help with any questions or technical support',
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
                  title: Text(
                    loc.tr('الاتصال الهاتفي', 'Phone Call'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(EnvConfig.supportPhone),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () =>
                      launchUrl(Uri.parse('tel:${EnvConfig.supportPhone}')),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.chat, color: AppColors.success),
                  title: Text(
                    loc.tr('واتساب الدعم الفني', 'WhatsApp Support'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('+${EnvConfig.supportWhatsapp}'),
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
                  title: Text(
                    loc.tr('البريد الإلكتروني', 'Email'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(EnvConfig.supportEmail),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                  onTap: () => launchUrl(
                    Uri.parse(
                      'mailto:${EnvConfig.supportEmail}?subject=Ghiyarak Support',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.policy_rounded, color: AppColors.orange),
                  title: Text(
                    loc.tr(
                      'الشروط والأحكام وسياسة الخصوصية والاسترجاع',
                      'Terms, Refund & Privacy Policy',
                    ),
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