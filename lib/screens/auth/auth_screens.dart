import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

typedef PickedMedia = ({String name, Uint8List bytes});
const String _oauthRedirectUrl = 'com.autoparts.app://login-callback';

Future<int> _fetchDefaultPostLimit(SupabaseClient db) async {
  try {
    final row = await db
        .from('system_settings')
        .select('value')
        .eq('key', 'default_max_posts')
        .maybeSingle();
    return int.tryParse((row?['value'] as String?) ?? '5') ?? 5;
  } catch (_) {
    return 5;
  }
}

/// نافذة الشروط والأحكام وسياسة الخصوصية (متطلب Apple App Store Review)
Future<void> showTermsAndPrivacySheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: AppColors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'الشروط والأحكام وسياسة الخصوصية',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: const [
                _LegalSection(
                  title: '1. قبول الشروط واستخدام تطبيق غيارك',
                  body:
                      'بإنشائك حساباً أو استخدامك لتطبيق غيارك (Ghyarak)، فإنك توافق على الالتزام بهذه الشروط والأحكام وبكافة القوانين السارية في المملكة الأردنية الهاشمية. يعمل التطبيق كوسيط تقني يربط بين مالكي المركبات وتجار قطع الغيار والورش ومزودي خدمات الونش.',
                ),
                _LegalSection(
                  title: '2. سياسة الخصوصية والبيانات المجمّعة',
                  body:
                      '• نجمع فقط البيانات اللازمة لتشغيل الخدمة: الاسم، اسم المستخدم، رقم الهاتف، البريد الإلكتروني، وصور القطع أو التراخيص التي ترفعها طوعاً.\n'
                      '• يُستخدم الموقع الجغرافي (GPS) فقط عند طلب مساعدة طارئة أو حجز موعد ورشة لحساب المسافة والتتبع المباشر، ولا يتم بيع بياناتك لأي طرف ثالث.\n'
                      '• يمكنك طلب تعديل بياناتك أو حذف حسابك نهائياً في أي وقت من صفحة (حسابي ← حذف الحساب نهائياً).',
                ),
                _LegalSection(
                  title: '3. التزامات التجار والورش والونشات',
                  body:
                      '• يتحمل التاجر أو الورشة كامل المسؤولية القانونية عن دقة أوصاف القطع وأسعارها وحالتها وجودتها.\n'
                      '• تخضع الباقات والعمولات للسياسة المعلنة داخل التطبيق، وتُحتسب عمولة المنصة بشفافية في محفظة المزود.\n'
                      '• يحق لإدارة غيارك إخفاء أي إعلان مخالف أو إيقاف الحساب في حال التلاعب بالأسعار أو الاحتيال.',
                ),
                _LegalSection(
                  title: '4. سياسة المحتوى والإبلاغ (Zero-Tolerance)',
                  body:
                      '• يُمنع منعاً باتاً نشر أي محتوى مسيء أو مضلل أو مخالف للآداب العامة أو القانون.\n'
                      '• يتيح التطبيق زر (إبلاغ عن محتوى/مستخدم) في جميع الإعلانات والملفات الشخصية، وتلتزم الإدارة بمراجعة البلاغات واتخاذ إجراء خلال 24 ساعة.',
                ),
                _LegalSection(
                  title: '5. المدفوعات والاسترداد والتواصل',
                  body:
                      'تُعالج المدفوعات الإلكترونية عبر بوابات دفع مرخصة وآمنة، ولا يقوم التطبيق بتخزين أرقام بطاقاتك البنكية. لأي استفسار أو شكوى يرجى التواصل معنا عبر:\n'
                      '• البريد الإلكتروني: ${EnvConfig.supportEmail}\n'
                      '• الهاتف / واتساب: ${EnvConfig.supportPhone}',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('فهمت وأغلق', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String body;
  const _LegalSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navy),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const LoginScreen({super.key, required this.onAuthenticated});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _loginMode = 'phone';
  final _identifierCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _loading = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _hintText => switch (_loginMode) {
        'phone' => 'رقم الهاتف (مثال: 0790000000)',
        'username' => 'اسم المستخدم (username)',
        _ => 'البريد الإلكتروني',
      };

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final input = _identifierCtrl.text.trim();
    if (input.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال بيانات الدخول وكلمة المرور')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final emailToUse = _loginMode == 'email'
          ? input
          : await db.rpc('get_email_for_login', params: {'identifier': input}) as String?;
      if (emailToUse == null || emailToUse.isEmpty) {
        throw Exception('لا يوجد حساب مسجل بهذه البيانات');
      }
      await db.auth.signInWithPassword(email: emailToUse, password: _passCtrl.text);
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الدخول: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _oauthSignIn(OAuthProvider provider) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : _oauthRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تسجيل الدخول: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول — غيارك')),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          children: [
            const Center(child: GhiyarakLogo(size: 64)),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                'مرحباً بعودتك إلى غيارك',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _modeBtn('رقم الهاتف', 'phone'),
                  _modeBtn('اسم المستخدم', 'username'),
                  _modeBtn('الإيميل', 'email'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _identifierCtrl,
              keyboardType:
                  _loginMode == 'phone' ? TextInputType.phone : TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: _hintText,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _login();
              },
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    Navigator.push(context, animatedRoute(const ForgotPasswordScreen())),
                child: const Text(
                  'نسيت كلمة المرور؟',
                  style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            BounceTap(
              onTap: _loading ? () {} : _login,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'دخول',
                        style: TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('أو الدخول السريع عبر',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : () => _oauthSignIn(OAuthProvider.google),
              icon: const GoogleLogoIcon(size: 20),
              label: const Text(
                'المتابعة باستخدام Google',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : () => _oauthSignIn(OAuthProvider.apple),
              icon: const Icon(Icons.apple, size: 22),
              label: const Text('المتابعة باستخدام Apple',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                animatedRoute(SignUpScreen(onAuthenticated: widget.onAuthenticated)),
              ),
              child: const Text(
                'ليس لديك حساب؟ إنشاء حساب جديد',
                style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(String label, String key) {
    final active = _loginMode == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _identifierCtrl.clear();
          setState(() => _loginMode = key);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class CompleteOAuthProfileScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  const CompleteOAuthProfileScreen({super.key, required this.onCompleted});

  @override
  State<CompleteOAuthProfileScreen> createState() => _CompleteOAuthProfileScreenState();
}

class _CompleteOAuthProfileScreenState extends State<CompleteOAuthProfileScreen> {
  final _db = Supabase.instance.client;
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _role = 'user';
  bool _hasTowing = false;
  bool _acceptedTerms = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = _db.auth.currentUser;
    _nameCtrl.text = (u?.userMetadata?['full_name'] as String?) ??
        (u?.userMetadata?['name'] as String?) ??
        '';
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final username = _usernameCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (username.isEmpty || name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المستخدم والاسم الكامل ورقم الهاتف')),
      );
      return;
    }
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى الموافقة على الشروط والأحكام وسياسة الخصوصية أولاً'),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final user = _db.auth.currentUser!;
      final existing = await _db
          .from('customers')
          .select('id')
          .or('username.eq.$username,phone.eq.$phone')
          .maybeSingle();
      if (existing != null && existing['id'] != user.id) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اسم المستخدم أو رقم الهاتف مسجل مسبقاً لحساب آخر'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (_role == 'mechanic') {
        if (!mounted) {
          return;
        }
        Navigator.push(
          context,
          animatedRoute(WorkshopSetupScreen(
            existingUserId: user.id,
            username: username,
            fullName: name,
            email: user.email ?? '',
            phone: phone,
            country: 'الأردن',
            age: null,
            password: '',
            hasTowing: EnvConfig.winchEnabled.value ? _hasTowing : false,
            onCompleted: widget.onCompleted,
          )),
        );
        return;
      }

      final defaultLimit = await _fetchDefaultPostLimit(_db);
      await _db.from('customers').upsert({
        'id': user.id,
        'username': username,
        'full_name': name,
        'email': user.email,
        'phone': phone,
        'country': 'الأردن',
        'role': _role,
        'max_posts_limit': defaultLimit,
        'subscription_plan': 'free',
        'commission_rate': 0.15,
        'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
      });
      widget.onCompleted();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showWinch = EnvConfig.winchEnabled.value;
    final roles = [
      ('user', 'مستخدم عادي', Icons.person_outline),
      ('merchant', 'تاجر قطع', Icons.storefront_outlined),
      if (showWinch) ('towing', 'صاحب ونش', Icons.local_shipping_outlined),
      ('mechanic', 'ميكانيكي / ورشة', Icons.build_outlined),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('إكمال بيانات الحساب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _db.auth.signOut();
              widget.onCompleted();
            },
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'أهلاً بك! أكمل بياناتك لمتابعة استخدام غيارك',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.3,
            children: roles.map((r) {
              final active = _role == r.$1;
              return GestureDetector(
                onTap: () => setState(() => _role = r.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.navy : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: active ? AppColors.navy : AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(r.$3, color: active ? Colors.white : AppColors.textPrimary, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          r.$2,
                          style: TextStyle(
                            color: active ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'اسم المستخدم (username) - لا يتكرر',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل / اسم النشاط',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_saving) _save();
            },
            decoration: InputDecoration(
              labelText: 'رقم الهاتف - لا يتكرر',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_role == 'mechanic' && showWinch) ...[
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('هل لديك ونش؟'),
              value: _hasTowing,
              onChanged: (v) => setState(() => _hasTowing = v),
            ),
          ],
          const SizedBox(height: 12),
          _TermsAgreementBox(
            accepted: _acceptedTerms,
            onChanged: (v) => setState(() => _acceptedTerms = v),
            onOpenTerms: () => showTermsAndPrivacySheet(context),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(_role == 'mechanic' ? 'التالي: معلومات الورشة' : 'حفظ والدخول'),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _db = Supabase.instance.client;
  final _identifierCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _resolvedEmail;
  String? _securityAlert;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendRecoveryCode() async {
    FocusScope.of(context).unfocus();
    final input = _identifierCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _securityAlert = 'يرجى إدخال الإيميل أو رقم الهاتف أو اسم المستخدم');
      return;
    }
    setState(() {
      _loading = true;
      _securityAlert = null;
    });
    try {
      final email = input.contains('@')
          ? input
          : await _db.rpc('get_email_for_login', params: {'identifier': input}) as String?;
      if (email == null || email.isEmpty) {
        setState(() => _securityAlert = 'تنبيه: لم يتم العثور على أي حساب مسجل بهذه البيانات.');
        return;
      }
      await _db.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _resolvedEmail = email;
          _codeSent = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال رمز الأمان إلى: $email'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _securityAlert = 'تعذر إرسال رمز الأمان: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyAndResetPassword() async {
    FocusScope.of(context).unfocus();
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      _showSecurityWarning('رمز الأمان ناقص! يرجى إدخال كود الأمان المرسل لبريدك بشكل صحيح.');
      return;
    }
    if (_newPassCtrl.text.length < 6 || _newPassCtrl.text != _confirmPassCtrl.text) {
      _showSecurityWarning('تأكد من كتابة كلمة مرور من 6 أحرف على الأقل وتطابقها.');
      return;
    }
    setState(() {
      _loading = true;
      _securityAlert = null;
    });
    try {
      await _db.auth.verifyOTP(email: _resolvedEmail!, token: code, type: OtpType.recovery);
      await _db.auth.updateUser(UserAttributes(password: _newPassCtrl.text));
      await _db.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تغيير كلمة المرور بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } on AuthException {
      _showSecurityWarning(
          'تنبيه أمني: كود الأمان المدخل خاطئ أو منتهي الصلاحية! تم إيقاف التغيير لحماية حسابك.');
    } catch (e) {
      _showSecurityWarning('تنبيه أمني: فشل التحقق ($e).');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showSecurityWarning(String msg) {
    if (!mounted) {
      return;
    }
    setState(() => _securityAlert = msg);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.red),
            SizedBox(width: 8),
            Text('تنبيه أمني', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(msg),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          if (_securityAlert != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                _securityAlert!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          if (!_codeSent) ...[
            TextField(
              controller: _identifierCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _sendRecoveryCode();
              },
              decoration: InputDecoration(
                labelText: 'الإيميل / رقم الهاتف / اسم المستخدم',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _loading ? null : _sendRecoveryCode,
              child: const Text('إرسال رمز الأمان'),
            ),
          ] else ...[
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'رمز الأمان (OTP)',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPassCtrl,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPassCtrl,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _verifyAndResetPassword();
              },
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _loading ? null : _verifyAndResetPassword,
              child: const Text('تأكيد الرمز وتغيير كلمة المرور'),
            ),
          ],
        ],
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const SignUpScreen({super.key, required this.onAuthenticated});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  String _selectedRole = 'user';
  bool _hasTowing = false;
  bool _isOwnerDriver = true;
  bool _acceptedTerms = false;
  bool _obscurePass = true;

  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'الأردن');
  final _ageCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _winchPlateCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _driverPhoneCtrl = TextEditingController();

  PickedMedia? _driverLicenseFile;
  PickedMedia? _winchLicenseFile;
  bool _loading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _countryCtrl.dispose();
    _ageCtrl.dispose();
    _passCtrl.dispose();
    _winchPlateCtrl.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isDriverLicense) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 72,
    );
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      if (isDriverLicense) {
        _driverLicenseFile = (name: picked.name, bytes: bytes);
      } else {
        _winchLicenseFile = (name: picked.name, bytes: bytes);
      }
    });
  }

  Future<String> _uploadMedia(PickedMedia media, String folder, String uid) async {
    final safe = media.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$folder/$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await Supabase.instance.client.storage.from('app_media').uploadBinary(
          path,
          media.bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return Supabase.instance.client.storage.from('app_media').getPublicUrl(path);
  }

  Future<void> _oauthSignUp(OAuthProvider provider) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : _oauthRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (mounted) {
        Navigator.popUntil(context, (r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitStep1() async {
    FocusScope.of(context).unfocus();
    final showWinch = EnvConfig.winchEnabled.value;
    final username = _usernameCtrl.text.trim();
    final fullName = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (username.isEmpty ||
        fullName.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى تعبئة اسم المستخدم، الاسم الكامل، الهاتف، الإيميل وكلمة المرور')),
      );
      return;
    }

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى الموافقة على الشروط والأحكام وسياسة الخصوصية لإتمام التسجيل'),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }

    if (showWinch && _selectedRole == 'towing') {
      if (_driverLicenseFile == null ||
          _winchLicenseFile == null ||
          _winchPlateCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى رفع رخصة السائق ورخصة الونش وكتابة نمرة الونش')),
        );
        return;
      }
      if (!_isOwnerDriver &&
          (_driverNameCtrl.text.trim().isEmpty || _driverPhoneCtrl.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال اسم سائق الونش ورقم هاتفه')),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final checkMsg = await db.rpc('check_account_availability', params: {
        'p_email': email,
        'p_phone': phone,
        'p_username': username,
      }) as String;
      if (checkMsg != 'OK') {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(checkMsg), backgroundColor: Colors.red));
        }
        return;
      }

      if (_selectedRole == 'mechanic') {
        if (!mounted) {
          return;
        }
        Navigator.push(
          context,
          animatedRoute(WorkshopSetupScreen(
            username: username,
            fullName: fullName,
            email: email,
            phone: phone,
            country: _countryCtrl.text.trim(),
            age: int.tryParse(_ageCtrl.text.trim()),
            password: password,
            hasTowing: showWinch ? _hasTowing : false,
            onCompleted: widget.onAuthenticated,
          )),
        );
        return;
      }

      final defaultLimit = await _fetchDefaultPostLimit(db);
      final authRes = await db.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'display_name': fullName,
          'username': username,
          'phone': phone,
          'role': _selectedRole,
        },
      );
      final uid = authRes.user!.id;

      String? driverUrl;
      String? winchUrl;
      if (showWinch && _selectedRole == 'towing') {
        driverUrl = await _uploadMedia(_driverLicenseFile!, 'licenses', uid);
        winchUrl = await _uploadMedia(_winchLicenseFile!, 'licenses', uid);
      }

      await db.from('customers').upsert({
        'id': uid,
        'username': username,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'country': _countryCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()),
        'role': _selectedRole,
        'has_towing': showWinch && _selectedRole == 'towing',
        'is_owner_winch_driver': (showWinch && _selectedRole == 'towing') ? _isOwnerDriver : true,
        'winch_driver_name': (showWinch && _selectedRole == 'towing' && !_isOwnerDriver)
            ? _driverNameCtrl.text.trim()
            : null,
        'winch_driver_phone': (showWinch && _selectedRole == 'towing' && !_isOwnerDriver)
            ? _driverPhoneCtrl.text.trim()
            : null,
        'winch_plate_number':
            (showWinch && _selectedRole == 'towing') ? _winchPlateCtrl.text.trim() : null,
        'driver_license_url': driverUrl,
        'winch_license_url': winchUrl,
        'max_posts_limit': defaultLimit,
        'subscription_plan': 'free',
        'commission_rate': 0.15,
        'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        Navigator.popUntil(context, (r) => r.isFirst);
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ بالتسجيل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showWinch = EnvConfig.winchEnabled.value;
    if (!showWinch && _selectedRole == 'towing') {
      _selectedRole = 'user';
    }
    final isTowing = _selectedRole == 'towing' && showWinch;
    final roles = [
      ('user', 'مستخدم عادي', Icons.person_outline),
      ('merchant', 'تاجر قطع', Icons.storefront_outlined),
      if (showWinch) ('towing', 'صاحب ونش', Icons.local_shipping_outlined),
      ('mechanic', 'ميكانيكي / ورشة', Icons.build_outlined),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب جديد — غيارك')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : () => _oauthSignUp(OAuthProvider.google),
                  icon: const GoogleLogoIcon(size: 18),
                  label: const Text(
                    'تسجيل بـ Google',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : () => _oauthSignUp(OAuthProvider.apple),
                  icon: const Icon(Icons.apple, size: 20),
                  label: const Text('تسجيل بـ Apple',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text('أو اختر نوع الحساب وأدخل بياناتك',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.3,
            children: roles.map((r) {
              final active = _selectedRole == r.$1;
              return GestureDetector(
                onTap: () => setState(() => _selectedRole = r.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.navy : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: active ? AppColors.navy : AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(r.$3, color: active ? Colors.white : AppColors.textPrimary, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          r.$2,
                          style: TextStyle(
                            color: active ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _field(_usernameCtrl, 'اسم المستخدم (username) - لا يتكرر',
              action: TextInputAction.next),
          _field(_nameCtrl, 'الاسم الكامل / اسم النشاط', action: TextInputAction.next),
          _field(_phoneCtrl, 'رقم الهاتف - لا يتكرر',
              type: TextInputType.phone, action: TextInputAction.next),
          _field(_emailCtrl, 'البريد الإلكتروني - لا يتكرر',
              type: TextInputType.emailAddress, action: TextInputAction.next),
          Row(
            children: [
              Expanded(child: _field(_countryCtrl, 'الدولة', action: TextInputAction.next)),
              const SizedBox(width: 10),
              Expanded(
                child: _field(_ageCtrl, 'العمر (اختياري)',
                    type: TextInputType.number, action: TextInputAction.next),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              textInputAction: isTowing ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) {
                if (!isTowing && !_loading) _submitStep1();
              },
              decoration: InputDecoration(
                labelText: 'كلمة المرور (6 أحرف على الأقل)',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
          ),
          if (_selectedRole == 'mechanic' && showWinch)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('هل لديك ونش؟', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('نعم')),
                          selected: _hasTowing,
                          selectedColor: AppColors.orangeLight,
                          onSelected: (_) => setState(() => _hasTowing = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('لا')),
                          selected: !_hasTowing,
                          selectedColor: AppColors.orangeLight,
                          onSelected: (_) => setState(() => _hasTowing = false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (isTowing) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('هل سائق الونش هو نفسه صاحب الحساب؟',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              value: _isOwnerDriver,
              activeTrackColor: AppColors.orange,
              onChanged: (v) => setState(() => _isOwnerDriver = v),
            ),
            if (!_isOwnerDriver) ...[
              _field(_driverNameCtrl, 'اسم سائق الونش (إجباري)', action: TextInputAction.next),
              _field(_driverPhoneCtrl, 'رقم هاتف سائق الونش (إجباري)',
                  type: TextInputType.phone, action: TextInputAction.next),
            ],
            _field(
              _winchPlateCtrl,
              'نمرة الونش (إجباري)',
              action: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _submitStep1();
              },
            ),
            _UploadTile(
              title: 'صورة رخصة السائق (إجباري)',
              media: _driverLicenseFile,
              onTap: () => _pickImage(true),
            ),
            const SizedBox(height: 10),
            _UploadTile(
              title: 'صورة رخصة الونش (إجباري)',
              media: _winchLicenseFile,
              onTap: () => _pickImage(false),
            ),
          ],
          const SizedBox(height: 14),
          _TermsAgreementBox(
            accepted: _acceptedTerms,
            onChanged: (v) => setState(() => _acceptedTerms = v),
            onOpenTerms: () => showTermsAndPrivacySheet(context),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _loading ? null : _submitStep1,
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    _selectedRole == 'mechanic' ? 'التالي: معلومات الورشة' : 'إنشاء الحساب',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool obscure = false,
    TextInputType? type,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        textInputAction: action,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _TermsAgreementBox extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenTerms;

  const _TermsAgreementBox({
    required this.accepted,
    required this.onChanged,
    required this.onOpenTerms,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accepted ? AppColors.success : AppColors.border),
      ),
      child: Row(
        children: [
          Checkbox(
            value: accepted,
            activeColor: AppColors.orange,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('أوافق على ', style: TextStyle(fontSize: 12.5)),
                GestureDetector(
                  onTap: onOpenTerms,
                  child: const Text(
                    'الشروط والأحكام وسياسة الخصوصية',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.orange,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Text(' لتطبيق غيارك.', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkshopSetupScreen extends StatefulWidget {
  final String? existingUserId;
  final String username;
  final String fullName;
  final String email;
  final String phone;
  final String country;
  final int? age;
  final String password;
  final bool hasTowing;
  final VoidCallback onCompleted;

  const WorkshopSetupScreen({
    super.key,
    this.existingUserId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.country,
    required this.age,
    required this.password,
    required this.hasTowing,
    required this.onCompleted,
  });

  @override
  State<WorkshopSetupScreen> createState() => _WorkshopSetupScreenState();
}

class _WorkshopSetupScreenState extends State<WorkshopSetupScreen> {
  final _locationService = LocationService();
  final _mapCtrl = MapController();
  final _picker = ImagePicker();
  final _streetCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController(text: '5');
  bool _isOwnerDriver = true;
  final _winchPlateCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _driverPhoneCtrl = TextEditingController();
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 20, minute: 0);
  LatLng _workshopLatLng = const LatLng(31.9539, 35.9106);
  String _workshopAddress = '';
  bool _locationConfirmed = false;
  PickedMedia? _workshopImage;
  PickedMedia? _driverLicense;
  PickedMedia? _winchLicense;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _detectGps();
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _capacityCtrl.dispose();
    _winchPlateCtrl.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectGps() async {
    final res = await _locationService.getCurrentLocation();
    if (!mounted) {
      return;
    }
    setState(() {
      _workshopLatLng = res.coordinates;
      _workshopAddress = res.address;
      _locationConfirmed = true;
    });
    _mapCtrl.move(_workshopLatLng, 15);
  }

  Future<void> _pickClock(bool isOpening) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpening ? _openTime : _closeTime,
    );
    if (picked != null) {
      setState(() {
        if (isOpening) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
    }
  }

  Future<PickedMedia?> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 72,
    );
    if (picked == null) {
      return null;
    }
    return (name: picked.name, bytes: await picked.readAsBytes());
  }

  Future<String> _upload(PickedMedia media, String folder, String uid) async {
    final safe = media.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$folder/$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await Supabase.instance.client.storage.from('app_media').uploadBinary(
          path,
          media.bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return Supabase.instance.client.storage.from('app_media').getPublicUrl(path);
  }

  Future<void> _finishRegistration() async {
    FocusScope.of(context).unfocus();
    final cap = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
    if (!_locationConfirmed ||
        _workshopImage == null ||
        _streetCtrl.text.trim().isEmpty ||
        cap <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جميع حقول الورشة إجبارية ما عدا رقم المبنى'),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }
    if (widget.hasTowing &&
        (_driverLicense == null || _winchLicense == null || _winchPlateCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى رفع صورة رخصة السائق ورخصة الونش وكتابة نمرة الونش')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = Supabase.instance.client;
      final defaultLimit = await _fetchDefaultPostLimit(db);
      String uid;
      if (widget.existingUserId != null) {
        uid = widget.existingUserId!;
      } else {
        final authRes = await db.auth.signUp(
          email: widget.email,
          password: widget.password,
          data: {
            'full_name': widget.fullName,
            'display_name': widget.fullName,
            'username': widget.username,
            'phone': widget.phone,
            'role': 'mechanic',
          },
        );
        uid = authRes.user!.id;
      }

      final workshopUrl = await _upload(_workshopImage!, 'workshops', uid);
      String? driverUrl;
      String? winchUrl;
      if (widget.hasTowing) {
        driverUrl = await _upload(_driverLicense!, 'licenses', uid);
        winchUrl = await _upload(_winchLicense!, 'licenses', uid);
      }

      if (!mounted) {
        return;
      }
      await db.from('customers').upsert({
        'id': uid,
        'username': widget.username,
        'full_name': widget.fullName,
        'email': widget.email,
        'phone': widget.phone,
        'country': widget.country,
        'age': widget.age,
        'role': 'mechanic',
        'has_towing': widget.hasTowing,
        'workshop_latitude': _workshopLatLng.latitude,
        'workshop_longitude': _workshopLatLng.longitude,
        'workshop_address': _workshopAddress,
        'street_name': _streetCtrl.text.trim(),
        'building_number': _buildingCtrl.text.trim().isEmpty ? null : _buildingCtrl.text.trim(),
        'workshop_image_url': workshopUrl,
        'max_car_capacity': cap,
        'opening_hours': '${_openTime.format(context)} - ${_closeTime.format(context)}',
        'is_owner_winch_driver': widget.hasTowing ? _isOwnerDriver : true,
        'winch_driver_name':
            (widget.hasTowing && !_isOwnerDriver) ? _driverNameCtrl.text.trim() : null,
        'winch_driver_phone':
            (widget.hasTowing && !_isOwnerDriver) ? _driverPhoneCtrl.text.trim() : null,
        'winch_plate_number': widget.hasTowing ? _winchPlateCtrl.text.trim() : null,
        'driver_license_url': driverUrl,
        'winch_license_url': winchUrl,
        'max_posts_limit': defaultLimit,
        'subscription_plan': 'free',
        'commission_rate': 0.15,
        'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        Navigator.popUntil(context, (r) => r.isFirst);
        widget.onCompleted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معلومات الورشة')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('موقع الورشة على الخريطة (إجباري)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: _workshopLatLng,
                      initialZoom: 14,
                      onTap: (_, latLng) async {
                        setState(() {
                          _workshopLatLng = latLng;
                          _locationConfirmed = true;
                        });
                        final addr = await _locationService.getAddressFromLatLng(latLng);
                        if (mounted) {
                          setState(() => _workshopAddress = addr);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.autoparts.app',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: _workshopLatLng,
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on, color: AppColors.orange, size: 40),
                        ),
                      ]),
                    ],
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: FloatingActionButton.small(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      onPressed: _detectGps,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _workshopAddress.isEmpty ? 'اضغط على الخريطة لتحديد الموقع' : _workshopAddress,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _UploadTile(
            title: 'صورة واجهة الورشة (إجباري)',
            media: _workshopImage,
            onTap: () async {
              final m = await _pickPhoto();
              if (m != null) {
                setState(() => _workshopImage = m);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _streetCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'اسم الشارع (إجباري)',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buildingCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'رقم المبنى (اختياري)',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capacityCtrl,
            keyboardType: TextInputType.number,
            textInputAction: widget.hasTowing ? TextInputAction.next : TextInputAction.done,
            onSubmitted: (_) {
              if (!widget.hasTowing && !_saving) _finishRegistration();
            },
            decoration: InputDecoration(
              labelText: 'كم سيارة تتسع الورشة باليوم؟ (إجباري)',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          const Text('ساعات الدوام (إجباري)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickClock(true),
                  icon: const Icon(Icons.access_time, color: AppColors.navy),
                  label: Text('يفتح: ${_openTime.format(context)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickClock(false),
                  icon: const Icon(Icons.access_time_filled, color: AppColors.orange),
                  label: Text('يسكر: ${_closeTime.format(context)}'),
                ),
              ),
            ],
          ),
          if (widget.hasTowing) ...[
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('هل سائق الونش هو نفسه صاحب الحساب؟',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              value: _isOwnerDriver,
              activeTrackColor: AppColors.orange,
              onChanged: (v) => setState(() => _isOwnerDriver = v),
            ),
            if (!_isOwnerDriver) ...[
              TextField(
                controller: _driverNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'اسم سائق الونش (إجباري)',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _driverPhoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'رقم هاتف سائق الونش (إجباري)',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _winchPlateCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _finishRegistration();
              },
              decoration: InputDecoration(
                labelText: 'نمرة الونش (إجباري)',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            _UploadTile(
              title: 'صورة رخصة السائق (إجباري)',
              media: _driverLicense,
              onTap: () async {
                final m = await _pickPhoto();
                if (m != null) {
                  setState(() => _driverLicense = m);
                }
              },
            ),
            const SizedBox(height: 10),
            _UploadTile(
              title: 'صورة رخصة الونش (إجباري)',
              media: _winchLicense,
              onTap: () async {
                final m = await _pickPhoto();
                if (m != null) {
                  setState(() => _winchLicense = m);
                }
              },
            ),
          ],
          const SizedBox(height: 22),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _finishRegistration,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('إتمام التسجيل', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String title;
  final PickedMedia? media;
  final VoidCallback onTap;
  const _UploadTile({required this.title, required this.media, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: media != null ? AppColors.success : AppColors.border),
        ),
        child: Row(
          children: [
            if (media != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(media!.bytes, width: 48, height: 48, fit: BoxFit.cover),
              )
            else
              const Icon(Icons.add_a_photo_outlined, color: AppColors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                media != null ? '$title (تم الرفع)' : title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              media != null ? Icons.check_circle : Icons.upload,
              color: media != null ? AppColors.success : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}