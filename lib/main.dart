import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env_config.dart';
import 'models/db_models.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/mobile/mobile_shell.dart';
import 'services/app_locale_service.dart';
import 'services/notifications_service.dart';
import 'theme/app_theme.dart';
import 'widgets/animations.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  try {
    await NotificationsService.instance.init();
  } catch (_) {}

  runApp(const AutoPartsSupabaseApp());
}

class AutoPartsSupabaseApp extends StatelessWidget {
  const AutoPartsSupabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocaleService.instance.langCode,
      builder: (context, lang, _) {
        final isEn = lang == 'en';
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: isEn ? 'Ghiyarak' : 'غيارك',
          theme: AppTheme.lightTheme,
          builder: (context, child) => Directionality(
            textDirection: isEn ? TextDirection.ltr : TextDirection.rtl,
            child: child!,
          ),
          home: const RoleRouterGate(),
        );
      },
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

  @override
  void initState() {
    super.initState();
    _loadSession();
    _authSub = _db.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        unawaited(NotificationsService.instance.stopRealtimeListener());
      }
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
    try {
      final rows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', [
        'enable_payments',
        'enable_subscriptions',
        'enable_winch',
        'enable_ads',
      ]);
      for (final row in rows) {
        final key = row['key'];
        final isOn = row['value'] == 'true';
        if (key == 'enable_payments') {
          EnvConfig.paymentsEnabled.value = isOn;
        } else if (key == 'enable_subscriptions') {
          EnvConfig.subscriptionsEnabled.value = isOn;
        } else if (key == 'enable_winch') {
          EnvConfig.winchEnabled.value = isOn;
        } else if (key == 'enable_ads') {
          EnvConfig.adsEnabled.value = isOn;
        }
      }
    } catch (_) {}

    CustomerProfile? loadedProfile;
    bool needsCompletion = false;
    final user = _db.auth.currentUser;
    if (user != null) {
      final data =
          await _db.from('customers').select().eq('id', user.id).maybeSingle();
      if (data != null) {
        loadedProfile = CustomerProfile.fromMap(data);
      } else {
        needsCompletion = true;
      }
      unawaited(
        NotificationsService.instance
            .startRealtimeListener(user.id)
            .catchError((_) {}),
      );
    } else {
      unawaited(
        NotificationsService.instance
            .stopRealtimeListener()
            .catchError((_) {}),
      );
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
          : _needsOAuthCompletion
              ? CompleteOAuthProfileScreen(
                  key: const ValueKey('oauth_complete'),
                  onCompleted: _loadSession,
                )
              : ListenableBuilder(
                  key: const ValueKey('app'),
                  listenable: Listenable.merge([
                    EnvConfig.paymentsEnabled,
                    EnvConfig.subscriptionsEnabled,
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