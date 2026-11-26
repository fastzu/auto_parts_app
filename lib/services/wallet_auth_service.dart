import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

class WalletAuthService {
  WalletAuthService._();
  static final WalletAuthService instance = WalletAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> authenticate([Object? contextOrReason]) async {
    if (kIsWeb) return true;
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.iOS && platform != TargetPlatform.android) {
      return true;
    }

    final String reason =
        (contextOrReason is String && contextOrReason.trim().isNotEmpty)
            ? contextOrReason
            : 'تأكيد الهوية عبر Face ID أو البصمة لفتح المحفظة';

    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      if (!isSupported && !canCheckBiometrics) {
        return true;
      }

      final availableBiometrics = await _auth.getAvailableBiometrics();
      final hasBiometrics = availableBiometrics.isNotEmpty;

      // 1) تشغيل Face ID / Touch ID / البصمة أولاً
      if (hasBiometrics) {
        try {
          final bioOk = await _auth.authenticate(
            localizedReason: reason,
            biometricOnly: true,
            persistAcrossBackgrounding: true,
          );
          if (bioOk) return true;
        } on LocalAuthException catch (e) {
          if (e.code == LocalAuthExceptionCode.userCanceled ||
              e.code == LocalAuthExceptionCode.systemCanceled) {
            return false;
          }
        } catch (_) {}
      }

      // 2) خيار Passcode كبديل عند الحاجة
      return await _auth.authenticate(
        localizedReason: 'أدخل رمز قفل الجهاز لفتح المحفظة المالية',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      if (e.code == LocalAuthExceptionCode.userCanceled ||
          e.code == LocalAuthExceptionCode.systemCanceled) {
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateForWallet(BuildContext context) async {
    final ok = await authenticate();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب تأكيد الهوية لفتح المحفظة المالية'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return ok;
  }
}