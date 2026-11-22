import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env_config.dart';
import 'models/db_models.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/mobile/mobile_shell.dart';
import 'services/notifications_service.dart';
import 'theme/app_theme.dart';
import 'widgets/animations.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  // تهيئة إشعارات الهاتف الفورية (Android & iOS) قبل تشغيل التطبيق
  await NotificationsService.instance.initLocalNotifications();

  runApp(const AutoPartsSupabaseApp());
}

class AutoPartsSupabaseApp extends StatelessWidget {
  const AutoPartsSupabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'غيارك',
      theme: AppTheme.lightTheme,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final currentFocus = FocusManager.instance.primaryFocus;
            if (currentFocus != null && !currentFocus.hasPrimaryFocus) {
              currentFocus.unfocus();
            } else {
              currentFocus?.unfocus();
            }
          },
          child: child!,
        ),
      ),
      home: const RoleRouterGate(),
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
  CustomerProfile? _profile;
  bool _dataLoaded = false;
  bool _splashAnimationDone = false;
  bool _needsOAuthCompletion = false;
  bool _maintenanceMode = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
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
    super.dispose();
  }

  Future<void> _loadSession() async {
    bool maintenance = false;
    try {
      final rows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', [
            'enable_payments',
            'enable_winch',
            'maintenance_mode',
            'enable_ads',
          ]);
      for (final row in rows) {
        final key = row['key'] as String?;
        final val = row['value'] as String?;
        if (key == 'enable_payments') {
          EnvConfig.paymentsEnabled.value = val == 'true';
        } else if (key == 'enable_winch') {
          EnvConfig.winchEnabled.value = val == 'true';
        } else if (key == 'enable_ads') {
          EnvConfig.adsEnabled.value = val != 'false';
        } else if (key == 'maintenance_mode') {
          maintenance = val == 'true';
        }
      }
    } catch (_) {}

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
          loadedProfile = CustomerProfile.fromMap(data);
        } else {
          needsCompletion = true;
        }
      } catch (_) {}
      NotificationsService.instance.startGlobalListener();
    } else {
      NotificationsService.instance.stopGlobalListener();
    }

    if (mounted) {
      setState(() {
        _profile = loadedProfile;
        _needsOAuthCompletion = needsCompletion;
        _maintenanceMode = maintenance;
        _dataLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSplash = !_splashAnimationDone || !_dataLoaded;
    final isAdmin =
        _profile != null && (_profile!.isAdmin || _profile!.role == 'admin');

    if (!showSplash && _maintenanceMode && !isAdmin) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GhiyarakLogo(size: 74),
                const SizedBox(height: 18),
                const Text(
                  'التطبيق قيد الصيانة والتحديث',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'نعمل حالياً على تحسين خدمات غيارك، سنعود خلال دقائق.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _loadSession,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
          : _needsOAuthCompletion
              ? CompleteOAuthProfileScreen(
                  key: const ValueKey('oauth_complete'),
                  onCompleted: _loadSession,
                )
              : ListenableBuilder(
                  key: const ValueKey('app'),
                  listenable: Listenable.merge([
                    EnvConfig.paymentsEnabled,
                    EnvConfig.winchEnabled,
                    EnvConfig.adsEnabled,
                  ]),
                  builder: (context, _) {
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