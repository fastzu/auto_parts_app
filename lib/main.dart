import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env_config.dart';
import 'models/db_models.dart';
import 'screens/mobile/mobile_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  runApp(const AutoPartsSupabaseApp());
}

class AutoPartsSupabaseApp extends StatelessWidget {
  const AutoPartsSupabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'أوتو بارتس برو',
      theme: AppTheme.lightTheme,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
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
  CustomerProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() => _loading = true);

    try {
      final rows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', ['enable_payments', 'enable_winch']);
      for (final row in rows) {
        if (row['key'] == 'enable_payments') {
          EnvConfig.paymentsEnabled.value = row['value'] == 'true';
        } else if (row['key'] == 'enable_winch') {
          EnvConfig.winchEnabled.value = row['value'] == 'true';
        }
      }
    } catch (_) {}

    final user = _db.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _profile = null;
          _loading = false;
        });
      }
      return;
    }

    final data = await _db.from('customers').select().eq('id', user.id).maybeSingle();
    if (mounted) {
      setState(() {
        _profile = data != null ? CustomerProfile.fromMap(data) : null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        EnvConfig.paymentsEnabled,
        EnvConfig.winchEnabled,
      ]),
      builder: (context, _) {
        return LiveMobileShell(
          profile: _profile,
          onRefreshProfile: _loadSession,
          onSignedOut: _loadSession,
        );
      },
    );
  }
}