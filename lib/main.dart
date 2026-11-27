import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/env_config.dart';
import 'models/db_models.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/mobile/mobile_shell.dart';
import 'services/app_locale_service.dart';
import 'theme/app_theme.dart';
import 'widgets/animations.dart';
import 'widgets/app_top_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode && const bool.fromEnvironment('ZAP_PROXY')) {
    HttpOverrides.global = _ZapHttpOverrides();
  }

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  runApp(const AutoPartsSupabaseApp());
}

class _ZapHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'PROXY 127.0.0.1:8080';
    client.badCertificateCallback = (_, __, ___) => true;
    return client;
  }
}

class AutoPartsSupabaseApp extends StatelessWidget {
  const AutoPartsSupabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocaleService.instance.langCode,
      builder: (_, lang, __) {
        final isArabic = lang == 'ar';
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: isArabic ? 'غيارك' : 'Ghiyarak',
          theme: AppTheme.lightTheme,
          builder: (context, child) => Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: _TopToastScaffoldMessenger(child: child!),
          ),
          home: const RoleRouterGate(),
        );
      },
    );
  }
}

/// يعترض جميع رسائل SnackBar في التطبيق بالكامل ويعرضها من الأعلى بتصميم AppTopToast
class _TopToastScaffoldMessenger extends ScaffoldMessenger {
  const _TopToastScaffoldMessenger({required super.child});

  @override
  ScaffoldMessengerState createState() => _TopToastScaffoldMessengerState();
}

class _TopToastScaffoldMessengerState extends ScaffoldMessengerState {
  static String _extractText(Widget? widget) {
    if (widget == null) return '';
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText() ?? '';
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is Flex) {
      return widget.children
          .map(_extractText)
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
    }
    if (widget is Wrap) {
      return widget.children
          .map(_extractText)
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
    }
    if (widget is Container) {
      return _extractText(widget.child);
    }
    if (widget is SingleChildRenderObjectWidget) {
      return _extractText(widget.child);
    }
    if (widget is ProxyWidget) {
      return _extractText(widget.child);
    }
    return '';
  }

  static AppToastType _detectType(Color? bg, String message) {
    final lower = message.toLowerCase();
    if (bg == Colors.red ||
        bg == Colors.redAccent ||
        (bg != null && bg.r > 0.65 && bg.g < 0.35 && bg.b < 0.35) ||
        message.contains('فشل') ||
        message.contains('تعذر') ||
        message.contains('خطأ') ||
        message.contains('غير صحيح') ||
        message.contains('ممنوع') ||
        message.contains('حظر') ||
        lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('invalid')) {
      return AppToastType.error;
    }
    if (bg == AppColors.success ||
        bg == Colors.green ||
        (bg != null && bg.g > 0.45 && bg.r < 0.35) ||
        message.contains('بنجاح') ||
        message.contains('✓') ||
        message.contains('تم حفظ') ||
        message.contains('تم تحديث') ||
        message.contains('تم حذف') ||
        message.contains('تم إرسال') ||
        lower.contains('success') ||
        lower.contains('saved')) {
      return AppToastType.success;
    }
    if (bg == AppColors.orange ||
        bg == Colors.orange ||
        bg == Colors.amber ||
        message.contains('يرجى') ||
        message.contains('تنبيه') ||
        message.contains('تحذير') ||
        lower.contains('please') ||
        lower.contains('warning')) {
      return AppToastType.warning;
    }
    return AppToastType.info;
  }

  static String _defaultTitle(AppToastType type) {
    final loc = AppLocaleService.instance;
    return switch (type) {
      AppToastType.success => loc.tr('تمت العملية بنجاح', 'Success'),
      AppToastType.error => loc.tr('تعذر إتمام العملية', 'Error'),
      AppToastType.warning => loc.tr('تنبيه', 'Notice'),
      _ => loc.tr('إشعار', 'Info'),
    };
  }

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final message = _extractText(snackBar.content).trim();
    if (message.isNotEmpty) {
      final type = _detectType(snackBar.backgroundColor, message);
      AppTopToast.show(
        title: _defaultTitle(type),
        message: message,
        type: type,
        context: context,
        duration: snackBar.duration.inMilliseconds > 500
            ? snackBar.duration
            : const Duration(seconds: 3),
      );
    }

    return super.showSnackBar(
      const SnackBar(
        content: SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 1),
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  }
}

class RoleRouterGate extends StatefulWidget {
  const RoleRouterGate({super.key});

  @override
  State<RoleRouterGate> createState() => _RoleRouterGateState();
}

class _RoleRouterGateState extends State<RoleRouterGate> {
  final _db = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<Map<String, dynamic>>>? _settingsSub;
  CustomerProfile? _profile;
  bool _dataLoaded = false;
  bool _splashAnimationDone = false;
  bool _needsOAuthCompletion = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
    _listenToSystemSettings();
    _authSub = _db.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut) {
        _loadSession();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  void _applySettingsRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final key = row['key']?.toString();
      final val = row['value']?.toString();
      if (key == 'enable_payments') {
        EnvConfig.paymentsEnabled.value = val == 'true';
      } else if (key == 'enable_subscriptions') {
        EnvConfig.subscriptionsEnabled.value = val == 'true';
      } else if (key == 'enable_winch') {
        EnvConfig.winchEnabled.value = val == 'true';
      } else if (key == 'enable_ads') {
        EnvConfig.adsEnabled.value = val != 'false';
      } else if (key == 'maintenance_mode') {
        EnvConfig.maintenanceMode.value = val == 'true';
      }
    }
  }

  /// استماع فوري Realtime لإعدادات النظام — بمجرد تفعيل وضع الصيانة يُقفل التطبيق فوراً للجميع ما عدا الأدمن
  void _listenToSystemSettings() {
    _settingsSub?.cancel();
    try {
      _settingsSub = _db
          .from('system_settings')
          .stream(primaryKey: ['key'])
          .listen(
            (rows) => _applySettingsRows(rows),
            onError: (_) {},
          );
    } catch (_) {}
  }

  Future<void> _loadSystemSettingsOnce() async {
    try {
      final rows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', [
        'enable_payments',
        'enable_subscriptions',
        'enable_winch',
        'enable_ads',
        'maintenance_mode',
      ]);
      _applySettingsRows(List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _loadSession() async {
    await _loadSystemSettingsOnce();
    CustomerProfile? loadedProfile;
    bool needsCompletion = false;
    final user = _db.auth.currentUser;
    if (user != null) {
      try {
        final data = await _db
            .from('customers')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (data != null) {
          if (data['is_deleted'] == true) {
            await _db.auth.signOut();
            loadedProfile = null;
          } else {
            loadedProfile = CustomerProfile.fromMap(data);
          }
        } else {
          needsCompletion = true;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _profile = loadedProfile;
        _needsOAuthCompletion = needsCompletion;
        _dataLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSplash = !_splashAnimationDone || !_dataLoaded;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: showSplash
          ? GhiyarakAnimatedSplash(
              key: const ValueKey('splash'),
              onCompleted: () {
                if (mounted) {
                  setState(() => _splashAnimationDone = true);
                }
              },
            )
          : ListenableBuilder(
              key: const ValueKey('app_gate'),
              listenable: Listenable.merge([
                EnvConfig.paymentsEnabled,
                EnvConfig.subscriptionsEnabled,
                EnvConfig.winchEnabled,
                EnvConfig.adsEnabled,
                EnvConfig.maintenanceMode,
              ]),
              builder: (context, _) {
                final isAdmin = _profile != null &&
                    (_profile!.isAdmin || _profile!.role == 'admin');

                // قفل التطبيق بالكامل عند تفعيل وضع الصيانة لجميع المستخدمين ما عدا الأدمن
                if (EnvConfig.maintenanceMode.value && !isAdmin) {
                  return _MaintenanceLockScreen(
                    isLoggedIn: _profile != null,
                    onRefresh: _loadSession,
                    onAdminLogin: () async {
                      if (_profile != null) {
                        await _db.auth.signOut();
                      }
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        animatedRoute(
                          LoginScreen(onAuthenticated: _loadSession),
                        ),
                      );
                    },
                  );
                }

                if (_needsOAuthCompletion) {
                  return CompleteOAuthProfileScreen(
                    key: const ValueKey('oauth_complete'),
                    onCompleted: _loadSession,
                  );
                }

                return LiveMobileShell(
                  profile: _profile,
                  onRefreshProfile: _loadSession,
                  onSignedOut: _loadSession,
                );
              },
            ),
    );
  }
}

class _MaintenanceLockScreen extends StatefulWidget {
  final bool isLoggedIn;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onAdminLogin;

  const _MaintenanceLockScreen({
    required this.isLoggedIn,
    required this.onRefresh,
    required this.onAdminLogin,
  });

  @override
  State<_MaintenanceLockScreen> createState() => _MaintenanceLockScreenState();
}

class _MaintenanceLockScreenState extends State<_MaintenanceLockScreen> {
  bool _checking = false;

  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openWhatsappSupport() async {
    final uri = Uri.parse(
      'https://wa.me/${EnvConfig.supportWhatsapp}?text=${Uri.encodeComponent('مرحباً فريق غيارك، أستفسر عن حالة صيانة التطبيق.')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocaleService.instance;
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const GhiyarakLogo(size: 68),
                const SizedBox(height: 22),
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.orange.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.build_circle_outlined,
                    color: AppColors.orange,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  loc.tr('التطبيق تحت الصيانة حالياً', 'App Under Maintenance'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  loc.tr(
                    'نقوم حالياً بإجراء تحديثات وصيانة مجدولة لتحسين جودة خدمات غيارك وتأمينها.\nسنعود للعمل خلال وقت قصير، شكراً لصبركم.',
                    'We are currently performing scheduled maintenance to improve Ghiyarak.\nWe will be back shortly. Thank you for your patience.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _checking ? null : _recheck,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      loc.tr('تحديث الحالة', 'Check Again'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _openWhatsappSupport,
                    icon: const Icon(Icons.support_agent),
                    label: Text(
                      loc.tr('تواصل مع الدعم الفني', 'Contact Support'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: widget.onAdminLogin,
                  icon: Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                  label: Text(
                    widget.isLoggedIn
                        ? loc.tr(
                            'تسجيل خروج / دخول كإدارة',
                            'Switch to Admin Account',
                          )
                        : loc.tr('دخول الإدارة', 'Admin Sign In'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12.5,
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
}