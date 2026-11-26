import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

class WalletAuthService {
  WalletAuthService._();
  static final WalletAuthService instance = WalletAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> authenticate(BuildContext context) async {
    if (kIsWeb) return true;
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!isSupported && !canCheck) return true;

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'التحقق بالبصمة أو الوجه أو رمز القفل لفتح المحفظة',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return didAuthenticate;
    } on LocalAuthException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر التحقق من قفل الجهاز'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}