import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../services/app_locale_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

typedef PickedMedia = ({String name, Uint8List bytes});
const String _oauthRedirectUrl = 'com.autoparts.app://login-callback';

String _resolveOAuthRedirectUrl() => kIsWeb ? Uri.base.origin : _oauthRedirectUrl;

LaunchMode _resolveOAuthLaunchMode() =>
    kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;

bool _isProviderRole(String role) =>
    role == 'merchant' || role == 'mechanic' || role == 'towing';

String _roleArabicTitle(String role) {
  final loc = AppLocaleService.instance;
  return switch (role) {
    'merchant' => loc.tr('تاجر قطع غيار', 'Auto Parts Merchant'),
    'mechanic' => loc.tr('ميكانيكي / صاحب ورشة', 'Mechanic / Workshop Owner'),
    'towing' => EnvConfig.winchEnabled.value
        ? loc.tr('صاحب ونش طوارئ', 'Towing / Winch Owner')
        : loc.tr('مقدم خدمة طوارئ', 'Roadside Service Provider'),
    _ => loc.tr('مستخدم', 'Customer'),
  };
}

class _AuthLangToggleButton extends StatelessWidget {
  const _AuthLangToggleButton();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    return ValueListenableBuilder<String>(
      valueListenable: loc.langCode,
      builder: (_, __, ___) {
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              backgroundColor: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
            onPressed: () => loc.toggleLanguage(),
            icon: const Icon(Icons.language, size: 17, color: AppColors.orange),
            label: Text(
              loc.isEnglish ? 'عربي' : 'EN',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}

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

/// حفظ بيانات المستخدم مع توثيق العقد بسلاسة (مع حماية في حال لم يُشغَّل SQL العقد بعد)
Future<void> _upsertCustomerRecord(
  SupabaseClient db,
  Map<String, dynamic> payload,
) async {
  try {
    await db.from('customers').upsert(payload);
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST204' &&
        (e.message.contains('contract_accepted') ||
            e.message.contains('contract_accepted_at'))) {
      final fallback = Map<String, dynamic>.from(payload)
        ..remove('contract_accepted')
        ..remove('contract_accepted_at');
      await db.from('customers').upsert(fallback);
    } else {
      rethrow;
    }
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const LoginScreen({super.key, required this.onAuthenticated});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loc = AppLocaleService.instance;
  String _loginMode = 'phone';
  final _identifierCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _hintText => switch (_loginMode) {
        'phone' => _loc.tr('رقم الهاتف (مثال: 0790000000)', 'Phone number (e.g. 0790000000)'),
        'username' => _loc.tr('اسم المستخدم (username)', 'Username'),
        _ => _loc.tr('البريد الإلكتروني', 'Email address'),
      };

  Future<void> _login() async {
    final input = _identifierCtrl.text.trim();
    if (input.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى إدخال بيانات الدخول وكلمة المرور',
            'Please enter your login credentials and password',
          )),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final emailToUse = _loginMode == 'email'
          ? input
          : await db.rpc('get_email_for_login', params: {'identifier': input})
              as String?;
      if (emailToUse == null || emailToUse.isEmpty) {
        throw Exception(_loc.tr(
          'لا يوجد حساب مسجل بهذه البيانات',
          'No account found with these credentials',
        ));
      }
      await db.auth
          .signInWithPassword(email: emailToUse, password: _passCtrl.text);
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('فشل الدخول: $e', 'Sign in failed: $e')),
            backgroundColor: Colors.red,
          ),
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
        redirectTo: _resolveOAuthRedirectUrl(),
        authScreenLaunchMode: _resolveOAuthLaunchMode(),
      );
      if (!kIsWeb && mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('تعذر تسجيل الدخول: $e', 'Could not sign in: $e')),
            backgroundColor: Colors.red,
          ),
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
    return ListenableBuilder(
      listenable: Listenable.merge([_loc.langCode, EnvConfig.winchEnabled]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('تسجيل الدخول — غيارك', 'Sign In — Ghiyarak')),
            actions: const [_AuthLangToggleButton()],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Center(child: GhiyarakLogo(size: 64)),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        _loc.tr('مرحباً بعودتك إلى غيارك', 'Welcome back to Ghiyarak'),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
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
                          _modeBtn(_loc.tr('رقم الهاتف', 'Phone'), 'phone'),
                          _modeBtn(_loc.tr('اسم المستخدم', 'Username'), 'username'),
                          _modeBtn(_loc.tr('الإيميل', 'Email'), 'email'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _identifierCtrl,
                      keyboardType: _loginMode == 'phone'
                          ? TextInputType.phone
                          : TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: _hintText,
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _loc.tr('كلمة المرور', 'Password'),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                            context, animatedRoute(const ForgotPasswordScreen())),
                        child: Text(
                          _loc.tr('نسيت كلمة المرور؟', 'Forgot password?'),
                          style: const TextStyle(
                              color: AppColors.orange, fontWeight: FontWeight.bold),
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
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(
                                _loc.tr('دخول', 'Sign In'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            _loc.tr('أو الدخول السريع عبر', 'Or continue with'),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _loading
                          ? null
                          : () => _oauthSignIn(OAuthProvider.google),
                      icon: const GoogleLogoIcon(size: 20),
                      label: Text(
                        _loc.tr('المتابعة باستخدام Google', 'Continue with Google'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _loading
                          ? null
                          : () => _oauthSignIn(OAuthProvider.apple),
                      icon: const Icon(Icons.apple, size: 22),
                      label: Text(
                        _loc.tr('المتابعة باستخدام Apple', 'Continue with Apple'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        animatedRoute(
                            SignUpScreen(onAuthenticated: widget.onAuthenticated)),
                      ),
                      child: Text(
                        _loc.tr(
                          'ليس لديك حساب؟ إنشاء حساب جديد',
                          'Don\'t have an account? Create one',
                        ),
                        style: const TextStyle(
                            color: AppColors.navy, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
  State<CompleteOAuthProfileScreen> createState() =>
      _CompleteOAuthProfileScreenState();
}

class _CompleteOAuthProfileScreenState
    extends State<CompleteOAuthProfileScreen> {
  final _db = Supabase.instance.client;
  final _loc = AppLocaleService.instance;
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _role = 'user';
  bool _hasTowing = false;
  bool _contractAccepted = false;
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
    final showWinch = EnvConfig.winchEnabled.value;
    final username = _usernameCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (username.isEmpty || name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى إدخال اسم المستخدم والاسم الكامل ورقم الهاتف',
            'Please enter username, full name, and phone number',
          )),
        ),
      );
      return;
    }

    if (_isProviderRole(_role) && !_contractAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى قراءة عقد الشراكة والتعهد بدفع العمولات والموافقة عليه قبل المتابعة',
            'Please read and accept the partnership & commission agreement before continuing',
          )),
          backgroundColor: Colors.red,
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
            SnackBar(
              content: Text(_loc.tr(
                'اسم المستخدم أو رقم الهاتف مسجل مسبقاً لحساب آخر',
                'Username or phone number is already registered to another account',
              )),
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
            country: _loc.tr('الأردن', 'Jordan'),
            age: null,
            password: '',
            hasTowing: showWinch ? _hasTowing : false,
            contractAccepted: _contractAccepted,
            onCompleted: widget.onCompleted,
          )),
        );
        return;
      }

      final safeRole = (!showWinch && _role == 'towing') ? 'user' : _role;
      final defaultLimit = await _fetchDefaultPostLimit(_db);
      final isProvider = _isProviderRole(safeRole);
      await _upsertCustomerRecord(_db, {
        'id': user.id,
        'username': username,
        'full_name': name,
        'email': user.email,
        'phone': phone,
        'country': 'الأردن',
        'role': safeRole,
        'max_posts_limit': defaultLimit,
        'subscription_plan': 'free',
        'commission_rate': 0.15,
        if (isProvider) 'contract_accepted': true,
        if (isProvider)
          'contract_accepted_at': DateTime.now().toIso8601String(),
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
    return ListenableBuilder(
      listenable: Listenable.merge([_loc.langCode, EnvConfig.winchEnabled]),
      builder: (context, _) {
        final showWinch = EnvConfig.winchEnabled.value;
        if (!showWinch && _role == 'towing') {
          _role = 'user';
        }
        final roles = [
          ('user', _loc.tr('مستخدم عادي', 'Customer'), Icons.person_outline),
          ('merchant', _loc.tr('تاجر قطع', 'Parts Merchant'), Icons.storefront_outlined),
          if (showWinch)
            ('towing', _loc.tr('صاحب ونش', 'Winch / Towing'), Icons.local_shipping_outlined),
          ('mechanic', _loc.tr('ميكانيكي / ورشة', 'Mechanic / Workshop'), Icons.build_outlined),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('إكمال بيانات الحساب', 'Complete Your Profile')),
            actions: [
              const _AuthLangToggleButton(),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await _db.auth.signOut();
                  widget.onCompleted();
                },
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _loc.tr(
                      'أهلاً بك! أكمل بياناتك لمتابعة استخدام غيارك',
                      'Welcome! Complete your details to continue using Ghiyarak',
                    ),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        onTap: () => setState(() {
                          if (_role != r.$1) {
                            _role = r.$1;
                            _contractAccepted = false;
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: active ? AppColors.navy : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: active ? AppColors.navy : AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(r.$3,
                                  color: active ? Colors.white : AppColors.textPrimary,
                                  size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  r.$2,
                                  style: TextStyle(
                                    color:
                                        active ? Colors.white : AppColors.textPrimary,
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
                    decoration: InputDecoration(
                      labelText: _loc.tr(
                        'اسم المستخدم (username) - لا يتكرر',
                        'Username (unique)',
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: _loc.tr(
                        'الاسم الكامل / اسم النشاط',
                        'Full Name / Business Name',
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: _loc.tr('رقم الهاتف - لا يتكرر', 'Phone Number (unique)'),
                      filled: true,
                      fillColor: AppColors.surface,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  if (_role == 'mechanic' && showWinch) ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      title: Text(_loc.tr('هل لديك ونش؟', 'Do you have a winch?')),
                      value: _hasTowing,
                      onChanged: (v) => setState(() => _hasTowing = v),
                    ),
                  ],
                  if (_isProviderRole(_role)) ...[
                    const SizedBox(height: 16),
                    _ProviderContractCard(
                      role: _role,
                      accepted: _contractAccepted,
                      onChanged: (v) => setState(() => _contractAccepted = v),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_role == 'mechanic'
                            ? _loc.tr('التالي: معلومات الورشة', 'Next: Workshop Info')
                            : _loc.tr('حفظ والدخول', 'Save & Continue')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
  final _loc = AppLocaleService.instance;
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
    final input = _identifierCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _securityAlert = _loc.tr(
            'يرجى إدخال الإيميل أو رقم الهاتف أو اسم المستخدم',
            'Please enter your email, phone number, or username',
          ));
      return;
    }
    setState(() {
      _loading = true;
      _securityAlert = null;
    });
    try {
      final email = input.contains('@')
          ? input
          : await _db.rpc('get_email_for_login', params: {'identifier': input})
              as String?;
      if (email == null || email.isEmpty) {
        setState(() => _securityAlert = _loc.tr(
              'تنبيه: لم يتم العثور على أي حساب مسجل بهذه البيانات.',
              'Alert: No registered account found with these details.',
            ));
        return;
      }
      await _db.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _resolvedEmail = email;
          _codeSent = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'تم إرسال رمز الأمان إلى: $email',
              'Security code sent to: $email',
            )),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _securityAlert = _loc.tr(
              'تعذر إرسال رمز الأمان: $e',
              'Failed to send security code: $e',
            ));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyAndResetPassword() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      _showSecurityWarning(_loc.tr(
        'رمز الأمان ناقص! يرجى إدخال كود الأمان المرسل لبريدك بشكل صحيح.',
        'Incomplete security code! Please enter the 6-digit code sent to your email.',
      ));
      return;
    }
    if (_newPassCtrl.text.length < 6 ||
        _newPassCtrl.text != _confirmPassCtrl.text) {
      _showSecurityWarning(_loc.tr(
        'تأكد من كتابة كلمة مرور من 6 أحرف على الأقل وتطابقها.',
        'Please enter a password of at least 6 characters and make sure both match.',
      ));
      return;
    }
    setState(() {
      _loading = true;
      _securityAlert = null;
    });
    try {
      await _db.auth.verifyOTP(
          email: _resolvedEmail!, token: code, type: OtpType.recovery);
      await _db.auth.updateUser(UserAttributes(password: _newPassCtrl.text));
      await _db.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'تم تغيير كلمة المرور بنجاح!',
              'Password updated successfully!',
            )),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } on AuthException {
      _showSecurityWarning(_loc.tr(
        'تنبيه أمني: كود الأمان المدخل خاطئ أو منتهي الصلاحية! تم إيقاف التغيير لحماية حسابك.',
        'Security Alert: The code is invalid or expired! Operation cancelled to protect your account.',
      ));
    } catch (e) {
      _showSecurityWarning(_loc.tr(
        'تنبيه أمني: فشل التحقق ($e).',
        'Security Alert: Verification failed ($e).',
      ));
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
        title: Row(
          children: [
            const Icon(Icons.security, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              _loc.tr('تنبيه أمني', 'Security Alert'),
              style: const TextStyle(
                  color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(msg),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: Text(_loc.tr('حسناً', 'OK')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _loc.langCode,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('استعادة كلمة المرور', 'Reset Password')),
            actions: const [_AuthLangToggleButton()],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
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
                        style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                  if (!_codeSent) ...[
                    TextField(
                      controller: _identifierCtrl,
                      decoration: InputDecoration(
                        labelText: _loc.tr(
                          'الإيميل / رقم الهاتف / اسم المستخدم',
                          'Email / Phone Number / Username',
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
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
                      child: Text(_loc.tr('إرسال رمز الأمان', 'Send Security Code')),
                    ),
                  ] else ...[
                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _loc.tr('رمز الأمان (OTP)', 'Security Code (OTP)'),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPassCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _loc.tr('كلمة المرور الجديدة', 'New Password'),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPassCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _loc.tr('تأكيد كلمة المرور', 'Confirm Password'),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
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
                      child: Text(_loc.tr(
                        'تأكيد الرمز وتغيير كلمة المرور',
                        'Verify Code & Update Password',
                      )),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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
  final _loc = AppLocaleService.instance;
  String _selectedRole = 'user';
  bool _hasTowing = false;
  bool _isOwnerDriver = true;
  bool _contractAccepted = false;

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
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
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

  Future<String> _uploadMedia(
      PickedMedia media, String folder, String uid) async {
    final safe = media.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$folder/$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await Supabase.instance.client.storage.from('app_media').uploadBinary(
          path,
          media.bytes,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return Supabase.instance.client.storage
        .from('app_media')
        .getPublicUrl(path);
  }

  Future<void> _oauthSignUp(OAuthProvider provider) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: _resolveOAuthRedirectUrl(),
        authScreenLaunchMode: _resolveOAuthLaunchMode(),
      );
      if (!kIsWeb && mounted) {
        Navigator.popUntil(context, (r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('خطأ: $e', 'Error: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitStep1() async {
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
        SnackBar(
          content: Text(_loc.tr(
            'يرجى تعبئة اسم المستخدم، الاسم الكامل، الهاتف، الإيميل وكلمة المرور',
            'Please fill in username, full name, phone, email, and password (6+ chars)',
          )),
        ),
      );
      return;
    }

    if (_isProviderRole(_selectedRole) && !_contractAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى قراءة عقد الشراكة والتعهد بدفع العمولات والموافقة عليه قبل إنشاء الحساب',
            'Please read and accept the partnership & commission agreement before signing up',
          )),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (showWinch && _selectedRole == 'towing') {
      if (_driverLicenseFile == null ||
          _winchLicenseFile == null ||
          _winchPlateCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'يرجى رفع رخصة السائق ورخصة الونش وكتابة نمرة الونش',
              'Please upload driver license, winch license, and enter the winch plate number',
            )),
          ),
        );
        return;
      }
      if (!_isOwnerDriver &&
          (_driverNameCtrl.text.trim().isEmpty ||
              _driverPhoneCtrl.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr(
              'يرجى إدخال اسم سائق الونش ورقم هاتفه',
              'Please enter the winch driver\'s name and phone number',
            )),
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(checkMsg), backgroundColor: Colors.red));
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
            contractAccepted: _contractAccepted,
            onCompleted: widget.onAuthenticated,
          )),
        );
        return;
      }

      final safeRole =
          (!showWinch && _selectedRole == 'towing') ? 'user' : _selectedRole;
      final defaultLimit = await _fetchDefaultPostLimit(db);
      final authRes = await db.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'display_name': fullName,
          'username': username,
          'phone': phone,
          'role': safeRole,
        },
      );
      final uid = authRes.user!.id;

      String? driverUrl;
      String? winchUrl;
      if (showWinch && safeRole == 'towing') {
        driverUrl = await _uploadMedia(_driverLicenseFile!, 'licenses', uid);
        winchUrl = await _uploadMedia(_winchLicenseFile!, 'licenses', uid);
      }

      final isProvider = _isProviderRole(safeRole);
      await _upsertCustomerRecord(db, {
        'id': uid,
        'username': username,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'country': _countryCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()),
        'role': safeRole,
        'has_towing': showWinch && safeRole == 'towing',
        'is_owner_winch_driver':
            (showWinch && safeRole == 'towing') ? _isOwnerDriver : true,
        'winch_driver_name':
            (showWinch && safeRole == 'towing' && !_isOwnerDriver)
                ? _driverNameCtrl.text.trim()
                : null,
        'winch_driver_phone':
            (showWinch && safeRole == 'towing' && !_isOwnerDriver)
                ? _driverPhoneCtrl.text.trim()
                : null,
        'winch_plate_number': (showWinch && safeRole == 'towing')
            ? _winchPlateCtrl.text.trim()
            : null,
        'driver_license_url': driverUrl,
        'winch_license_url': winchUrl,
        'max_posts_limit': defaultLimit,
        'subscription_plan': 'free',
        'commission_rate': 0.15,
        if (isProvider) 'contract_accepted': true,
        if (isProvider)
          'contract_accepted_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.popUntil(context, (r) => r.isFirst);
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('خطأ بالتسجيل: $e', 'Registration error: $e')),
            backgroundColor: Colors.red,
          ),
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
    return ListenableBuilder(
      listenable: Listenable.merge([_loc.langCode, EnvConfig.winchEnabled]),
      builder: (context, _) {
        final showWinch = EnvConfig.winchEnabled.value;
        if (!showWinch && _selectedRole == 'towing') {
          _selectedRole = 'user';
        }
        final roles = [
          ('user', _loc.tr('مستخدم عادي', 'Customer'), Icons.person_outline),
          ('merchant', _loc.tr('تاجر قطع', 'Parts Merchant'), Icons.storefront_outlined),
          if (showWinch)
            ('towing', _loc.tr('صاحب ونش', 'Winch / Towing'), Icons.local_shipping_outlined),
          ('mechanic', _loc.tr('ميكانيكي / ورشة', 'Mechanic / Workshop'), Icons.build_outlined),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('إنشاء حساب جديد — غيارك', 'Create Account — Ghiyarak')),
            actions: const [_AuthLangToggleButton()],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _loading
                              ? null
                              : () => _oauthSignUp(OAuthProvider.google),
                          icon: const GoogleLogoIcon(size: 18),
                          label: Text(
                            _loc.tr('تسجيل بـ Google', 'Sign up with Google'),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
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
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _loading
                              ? null
                              : () => _oauthSignUp(OAuthProvider.apple),
                          icon: const Icon(Icons.apple, size: 20),
                          label: Text(
                            _loc.tr('تسجيل بـ Apple', 'Sign up with Apple'),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    _loc.tr(
                      'أو اختر نوع الحساب وأدخل بياناتك',
                      'Or choose your account type and enter your details',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
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
                        onTap: () => setState(() {
                          if (_selectedRole != r.$1) {
                            _selectedRole = r.$1;
                            _contractAccepted = false;
                          }
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: active ? AppColors.navy : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: active ? AppColors.navy : AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(r.$3,
                                  color: active ? Colors.white : AppColors.textPrimary,
                                  size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  r.$2,
                                  style: TextStyle(
                                    color:
                                        active ? Colors.white : AppColors.textPrimary,
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
                  _field(
                    _usernameCtrl,
                    _loc.tr('اسم المستخدم (username) - لا يتكرر', 'Username (unique)'),
                  ),
                  _field(
                    _nameCtrl,
                    _loc.tr('الاسم الكامل / اسم النشاط', 'Full Name / Business Name'),
                  ),
                  _field(
                    _phoneCtrl,
                    _loc.tr('رقم الهاتف - لا يتكرر', 'Phone Number (unique)'),
                    type: TextInputType.phone,
                  ),
                  _field(
                    _emailCtrl,
                    _loc.tr('البريد الإلكتروني - لا يتكرر', 'Email Address (unique)'),
                    type: TextInputType.emailAddress,
                  ),
                  Row(
                    children: [
                      Expanded(child: _field(_countryCtrl, _loc.tr('الدولة', 'Country'))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          _ageCtrl,
                          _loc.tr('العمر (اختياري)', 'Age (optional)'),
                          type: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  _field(
                    _passCtrl,
                    _loc.tr('كلمة المرور (6 أحرف على الأقل)', 'Password (min 6 characters)'),
                    obscure: true,
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
                          Text(
                            _loc.tr('هل لديك ونش؟', 'Do you have a winch?'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: Center(child: Text(_loc.tr('نعم', 'Yes'))),
                                  selected: _hasTowing,
                                  selectedColor: AppColors.orangeLight,
                                  onSelected: (_) => setState(() => _hasTowing = true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ChoiceChip(
                                  label: Center(child: Text(_loc.tr('لا', 'No'))),
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
                  if (_selectedRole == 'towing' && showWinch) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _loc.tr(
                          'هل سائق الونش هو نفسه صاحب الحساب؟',
                          'Is the winch driver the account owner?',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      value: _isOwnerDriver,
                      activeTrackColor: AppColors.orange,
                      onChanged: (v) => setState(() => _isOwnerDriver = v),
                    ),
                    if (!_isOwnerDriver) ...[
                      _field(
                        _driverNameCtrl,
                        _loc.tr('اسم سائق الونش (إجباري)', 'Winch Driver Name (required)'),
                      ),
                      _field(
                        _driverPhoneCtrl,
                        _loc.tr('رقم هاتف سائق الونش (إجباري)', 'Winch Driver Phone (required)'),
                        type: TextInputType.phone,
                      ),
                    ],
                    _field(
                      _winchPlateCtrl,
                      _loc.tr('نمرة الونش (إجباري)', 'Winch Plate Number (required)'),
                    ),
                    _UploadTile(
                      title: _loc.tr('صورة رخصة السائق (إجباري)', 'Driver License Photo (required)'),
                      media: _driverLicenseFile,
                      onTap: () => _pickImage(true),
                    ),
                    const SizedBox(height: 10),
                    _UploadTile(
                      title: _loc.tr('صورة رخصة الونش (إجباري)', 'Winch License Photo (required)'),
                      media: _winchLicenseFile,
                      onTap: () => _pickImage(false),
                    ),
                  ],
                  if (_isProviderRole(_selectedRole)) ...[
                    const SizedBox(height: 16),
                    _ProviderContractCard(
                      role: _selectedRole,
                      accepted: _contractAccepted,
                      onChanged: (v) => setState(() => _contractAccepted = v),
                    ),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _loading ? null : _submitStep1,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _selectedRole == 'mechanic'
                                ? _loc.tr('التالي: معلومات الورشة', 'Next: Workshop Info')
                                : _loc.tr('إنشاء الحساب', 'Create Account'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
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
  final bool contractAccepted;
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
    this.contractAccepted = true,
    required this.onCompleted,
  });

  @override
  State<WorkshopSetupScreen> createState() => _WorkshopSetupScreenState();
}

class _WorkshopSetupScreenState extends State<WorkshopSetupScreen> {
  final _loc = AppLocaleService.instance;
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
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
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
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return Supabase.instance.client.storage
        .from('app_media')
        .getPublicUrl(path);
  }

  Future<void> _finishRegistration() async {
    final effectiveHasTowing = widget.hasTowing && EnvConfig.winchEnabled.value;
    final cap = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
    if (!_locationConfirmed ||
        _workshopImage == null ||
        _streetCtrl.text.trim().isEmpty ||
        cap <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'جميع حقول الورشة إجبارية ما عدا رقم المبنى',
            'All workshop fields are required except building number',
          )),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }
    if (effectiveHasTowing &&
        (_driverLicense == null ||
            _winchLicense == null ||
            _winchPlateCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.tr(
            'يرجى رفع صورة رخصة السائق ورخصة الونش وكتابة نمرة الونش',
            'Please upload driver license, winch license, and enter the winch plate number',
          )),
        ),
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
      if (effectiveHasTowing) {
        driverUrl = await _upload(_driverLicense!, 'licenses', uid);
        winchUrl = await _upload(_winchLicense!, 'licenses', uid);
      }

      if (!mounted) {
        return;
      }
      await _upsertCustomerRecord(db, {
        'id': uid,
        'username': widget.username,
        'full_name': widget.fullName,
        'email': widget.email,
        'phone': widget.phone,
        'country': widget.country,
        'age': widget.age,
        'role': 'mechanic',
        'has_towing': effectiveHasTowing,
        'workshop_latitude': _workshopLatLng.latitude,
        'workshop_longitude': _workshopLatLng.longitude,
        'workshop_address': _workshopAddress,
        'street_name': _streetCtrl.text.trim(),
        'building_number': _buildingCtrl.text.trim().isEmpty
            ? null
            : _buildingCtrl.text.trim(),
        'workshop_image_url': workshopUrl,
        'max_car_capacity': cap,
        'opening_hours':
            '${_openTime.format(context)} - ${_closeTime.format(context)}',
        'is_owner_winch_driver': effectiveHasTowing ? _isOwnerDriver : true,
        'winch_driver_name': (effectiveHasTowing && !_isOwnerDriver)
            ? _driverNameCtrl.text.trim()
            : null,
        'winch_driver_phone': (effectiveHasTowing && !_isOwnerDriver)
            ? _driverPhoneCtrl.text.trim()
            : null,
        'winch_plate_number':
            effectiveHasTowing ? _winchPlateCtrl.text.trim() : null,
        'driver_license_url': driverUrl,
        'winch_license_url': winchUrl,
        'max_posts_limit': defaultLimit,
        'subscription_plan': 'free',
        'commission_rate': 0.15,
        'contract_accepted': widget.contractAccepted,
        'contract_accepted_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.popUntil(context, (r) => r.isFirst);
        widget.onCompleted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.tr('خطأ: $e', 'Error: $e')),
            backgroundColor: Colors.red,
          ),
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
    return ListenableBuilder(
      listenable: Listenable.merge([_loc.langCode, EnvConfig.winchEnabled]),
      builder: (context, _) {
        final effectiveHasTowing = widget.hasTowing && EnvConfig.winchEnabled.value;
        return Scaffold(
          appBar: AppBar(
            title: Text(_loc.tr('معلومات الورشة', 'Workshop Details')),
            actions: const [_AuthLangToggleButton()],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _loc.tr(
                      'موقع الورشة على الخريطة (إجباري)',
                      'Workshop location on map (required)',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                                final addr =
                                    await _locationService.getAddressFromLatLng(latLng);
                                if (mounted) {
                                  setState(() => _workshopAddress = addr);
                                }
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.autoparts.app',
                              ),
                              MarkerLayer(markers: [
                                Marker(
                                  point: _workshopLatLng,
                                  width: 44,
                                  height: 44,
                                  child: const Icon(Icons.location_on,
                                      color: AppColors.orange, size: 40),
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
                    _workshopAddress.isEmpty
                        ? _loc.tr(
                            'اضغط على الخريطة لتحديد الموقع',
                            'Tap on the map to set workshop location',
                          )
                        : _workshopAddress,
                    style:
                        const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  _UploadTile(
                    title: _loc.tr(
                      'صورة واجهة الورشة (إجباري)',
                      'Workshop Front Photo (required)',
                    ),
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
                    decoration: InputDecoration(
                      labelText: _loc.tr('اسم الشارع (إجباري)', 'Street Name (required)'),
                      filled: true,
                      fillColor: AppColors.surface,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _buildingCtrl,
                    decoration: InputDecoration(
                      labelText: _loc.tr('رقم المبنى (اختياري)', 'Building Number (optional)'),
                      filled: true,
                      fillColor: AppColors.surface,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _capacityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _loc.tr(
                        'كم سيارة تتسع الورشة باليوم؟ (إجباري)',
                        'Daily car capacity (required)',
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _loc.tr('ساعات الدوام (إجباري)', 'Working Hours (required)'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickClock(true),
                          icon: const Icon(Icons.access_time, color: AppColors.navy),
                          label: Text(_loc.tr(
                            'يفتح: ${_openTime.format(context)}',
                            'Opens: ${_openTime.format(context)}',
                          )),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickClock(false),
                          icon: const Icon(Icons.access_time_filled,
                              color: AppColors.orange),
                          label: Text(_loc.tr(
                            'يسكر: ${_closeTime.format(context)}',
                            'Closes: ${_closeTime.format(context)}',
                          )),
                        ),
                      ),
                    ],
                  ),
                  if (effectiveHasTowing) ...[
                    const Divider(height: 28),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _loc.tr(
                          'هل سائق الونش هو نفسه صاحب الحساب؟',
                          'Is the winch driver the account owner?',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      value: _isOwnerDriver,
                      activeTrackColor: AppColors.orange,
                      onChanged: (v) => setState(() => _isOwnerDriver = v),
                    ),
                    if (!_isOwnerDriver) ...[
                      TextField(
                        controller: _driverNameCtrl,
                        decoration: InputDecoration(
                          labelText: _loc.tr(
                            'اسم سائق الونش (إجباري)',
                            'Winch Driver Name (required)',
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _driverPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: _loc.tr(
                            'رقم هاتف سائق الونش (إجباري)',
                            'Winch Driver Phone (required)',
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _winchPlateCtrl,
                      decoration: InputDecoration(
                        labelText: _loc.tr(
                          'نمرة الونش (إجباري)',
                          'Winch Plate Number (required)',
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _UploadTile(
                      title: _loc.tr(
                        'صورة رخصة السائق (إجباري)',
                        'Driver License Photo (required)',
                      ),
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
                      title: _loc.tr(
                        'صورة رخصة الونش (إجباري)',
                        'Winch License Photo (required)',
                      ),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _saving ? null : _finishRegistration,
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _loc.tr('إتمام التسجيل', 'Complete Registration'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// بطاقة عقد الشراكة والتعهد القانوني الإلزامي لمقدمي الخدمات
class _ProviderContractCard extends StatelessWidget {
  final String role;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _ProviderContractCard({
    required this.role,
    required this.accepted,
    required this.onChanged,
  });

  List<(String, String)> _clauses(bool showWinch) {
    final loc = AppLocaleService.instance;
    return [
      (
        loc.tr(
          '1. الالتزام بسداد العمولات المستحقة',
          '1. Commission Settlement Commitment',
        ),
        showWinch
            ? loc.tr(
                'يتعهد الطرف الثاني (مقدم الخدمة) بسداد عمولة تطبيق غيارك المستحقة عن كافة الطلبات والمواعيد وطلبات الطوارئ والونش التي تتم عبر التطبيق — بما فيها العمولات المترتبة على الدفع النقدي (الكاش) المسجلة كذمم مالية في المحفظة — وفق النسبة المعتمدة لباقته الاشتراكية وفي المواعيد المحددة دون تأخير.',
                'The service provider commits to paying Ghiyarak\'s due commissions on all orders, appointments, roadside emergency, and towing requests completed via the app — including cash commissions recorded in the wallet — according to their subscription rate without delay.',
              )
            : loc.tr(
                'يتعهد الطرف الثاني (مقدم الخدمة) بسداد عمولة تطبيق غيارك المستحقة عن كافة الطلبات والمواعيد وطلبات الطوارئ التي تتم عبر التطبيق — بما فيها العمولات المترتبة على الدفع النقدي (الكاش) المسجلة كذمم مالية في المحفظة — وفق النسبة المعتمدة لباقته الاشتراكية وفي المواعيد المحددة دون تأخير.',
                'The service provider commits to paying Ghiyarak\'s due commissions on all orders, appointments, and roadside emergency requests completed via the app — including cash commissions recorded in the wallet — according to their subscription rate without delay.',
              ),
      ),
      (
        loc.tr(
          '2. صدق البيانات والأسعار والتراخيص',
          '2. Accuracy of Data, Pricing & Licenses',
        ),
        loc.tr(
          'يقر مقدم الخدمة بصحة كافة البيانات والمستندات والتراخيص والأسعار المعلنة، ويلتزم بعدم نشر إعلانات وهمية أو مضللة أو قطع غير مطابقة للوصف.',
          'The service provider confirms that all submitted details, documents, licenses, and listed prices are accurate and agrees not to publish misleading listings or non-matching parts.',
        ),
      ),
      (
        loc.tr(
          '3. حظر التحايل أو تجاوز المنصة',
          '3. Anti-Circumvention Policy',
        ),
        loc.tr(
          'يحظر تماماً التلاعب أو الإلغاء الصوري للطلبات أو الاتفاق الجانبي مع العملاء بغرض التهرب من احتساب عمولة تطبيق غيارك المستحقة.',
          'Fake cancellations or off-platform agreements with customers to avoid Ghiyarak\'s commission fees are strictly prohibited.',
        ),
      ),
      (
        loc.tr(
          '4. جودة الخدمة والمسؤولية المهنية',
          '4. Service Quality & Professional Responsibility',
        ),
        showWinch
            ? loc.tr(
                'يلتزم مقدم الخدمة بتقديم خدماته بمهنية عالية والالتزام بالمواعيد والأسعار المتفق عليها مع العميل داخل التطبيق، ويتحمل المسؤولية القانونية الكاملة عن جودة القطع وأعمال الصيانة أو السحب.',
                'The service provider commits to high professional standards, honoring agreed schedules and prices in the app, and bears full legal responsibility for parts quality, repairs, and towing services.',
              )
            : loc.tr(
                'يلتزم مقدم الخدمة بتقديم خدماته بمهنية عالية والالتزام بالمواعيد والأسعار المتفق عليها مع العميل داخل التطبيق، ويتحمل المسؤولية القانونية الكاملة عن جودة القطع وأعمال الصيانة.',
                'The service provider commits to high professional standards, honoring agreed schedules and prices in the app, and bears full legal responsibility for parts quality and repair services.',
              ),
      ),
      (
        loc.tr(
          '5. حق التعليق والمساءلة القانونية',
          '5. Suspension Rights & Legal Accountability',
        ),
        loc.tr(
          'يحق لإدارة تطبيق غيارك تعليق أو إيقاف الحساب فوراً عند التأخر في سداد الذمم المالية أو مخالفة أي بند من بنود هذا العقد، مع احتفاظها الكامل بحقها في المطالبة بالعمولات والمستحقات وفق القوانين والأنظمة المعمول بها في المملكة الأردنية الهاشمية.',
          'Ghiyarak reserves the right to immediately suspend or terminate the account for overdue balances or breach of this agreement, while retaining full legal rights to claim due commissions under the laws of the Hashemite Kingdom of Jordan.',
        ),
      ),
    ];
  }

  void _openFullContractDialog(BuildContext context, List<(String, String)> clauses) {
    final loc = AppLocaleService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.gavel_rounded, color: AppColors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc.tr(
                  'عقد الشراكة والتعهد (${_roleArabicTitle(role)})',
                  'Partnership Agreement (${_roleArabicTitle(role)})',
                ),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: clauses
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.$2,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.tr('إغلاق', 'Close')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              onChanged(true);
              Navigator.pop(ctx);
            },
            child: Text(loc.tr('أوافق وأتعهد بالالتزام', 'I Agree & Commit')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    final showWinch = EnvConfig.winchEnabled.value;
    final clauses = _clauses(showWinch);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accepted ? AppColors.success : AppColors.orange,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel_rounded,
                    color: AppColors.orange, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.tr(
                          'عقد الشراكة والتعهد القانوني — غيارك',
                          'Legal Partnership Agreement — Ghiyarak',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        loc.tr(
                          'صفة الشريك: ${_roleArabicTitle(role)}',
                          'Partner Role: ${_roleArabicTitle(role)}',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openFullContractDialog(context, clauses),
                  child: Text(
                    loc.tr('قراءة كاملة', 'Read Full'),
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 175,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: AppColors.background),
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.separated(
                itemCount: clauses.length,
                separatorBuilder: (_, __) => const Divider(height: 14),
                itemBuilder: (_, i) {
                  final c = clauses[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.$1,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.$2,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          CheckboxListTile(
            value: accepted,
            activeColor: AppColors.success,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            onChanged: (v) => onChanged(v ?? false),
            title: Text(
              loc.tr(
                'أقرّ وأتعهد رسمياً بقراءة هذا العقد والالتزام الكامل بدفع كافة العمولات المستحقة وبجميع شروط وأحكام تطبيق غيارك.',
                'I officially acknowledge reading this agreement and commit to paying all due commissions and complying with Ghiyarak\'s terms.',
              ),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
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
  const _UploadTile(
      {required this.title, required this.media, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: media != null ? AppColors.success : AppColors.border),
        ),
        child: Row(
          children: [
            if (media != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(media!.bytes,
                    width: 48, height: 48, fit: BoxFit.cover),
              )
            else
              const Icon(Icons.add_a_photo_outlined, color: AppColors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                media != null
                    ? '$title (${loc.tr('تم الرفع', 'Uploaded')})'
                    : title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              media != null ? Icons.check_circle : Icons.upload,
              color:
                  media != null ? AppColors.success : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}