import 'package:flutter/foundation.dart';

class EnvConfig {
  // للإنتاج والنشر: مرّر المفاتيح عبر:
  // flutter build apk/ipa --release --obfuscate --split-debug-info=build/symbols \
  //   --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  //   --dart-define=SUPABASE_ANON_KEY=eyJ...
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nsdymdqrlvbhvurwptvq.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zZHltZHFybHZiaHZ1cndwdHZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNTQzOTcsImV4cCI6MjEwODkzMDM5N30.IVrWoj0WcapQn9cQS4NYlqKtZI8c4VCq3dPg3BwF0zY',
  );

  // =========================================================================
  // إعدادات Apple Pay & Google Pay (جاهزة للتفعيل فور الاشتراك بحساب المطور)
  // بعد الحصول على Merchant ID من Apple Developer و Google Pay Business Console:
  // 1) غيّر applePayEnabled إلى true وضع APPLE_PAY_MERCHANT_ID الحقيقي
  // 2) غيّر googlePayEnabled إلى true وضع GOOGLE_PAY_MERCHANT_ID الحقيقي
  // =========================================================================
  static const bool applePayEnabled = bool.fromEnvironment(
    'APPLE_PAY_ENABLED',
    defaultValue: false,
  );
  static const String applePayMerchantId = String.fromEnvironment(
    'APPLE_PAY_MERCHANT_ID',
    defaultValue: 'merchant.com.autoparts.ghyarak',
  );

  static const bool googlePayEnabled = bool.fromEnvironment(
    'GOOGLE_PAY_ENABLED',
    defaultValue: false,
  );
  static const String googlePayMerchantId = String.fromEnvironment(
    'GOOGLE_PAY_MERCHANT_ID',
    defaultValue: 'BCR2DN4TXXXXXXXX',
  );
  static const String googlePayGateway = String.fromEnvironment(
    'GOOGLE_PAY_GATEWAY',
    defaultValue: 'mpgs', // بوابة MEPS / PayTabs
  );
  static const String googlePayGatewayMerchantId = String.fromEnvironment(
    'GOOGLE_PAY_GATEWAY_MERCHANT_ID',
    defaultValue: 'MEPS_MERCHANT_ID',
  );

  static const String paymentCountryCode = 'JO';
  static const String paymentCurrencyCode = 'JOD';

  // تفعيل إرسال Push خارجي عبر APNs / FCM بعد الاشتراك بحساب Apple Developer
  static const bool remotePushEnabled = bool.fromEnvironment(
    'REMOTE_PUSH_ENABLED',
    defaultValue: false,
  );

  // معرّفات Google AdMob (الافتراضي Test IDs الرسمية من Google — بدّلها بمعرّفاتك عند النشر عبر dart-define)
  static const String admobAndroidBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String admobIosBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );

  static const String supportPhone = '0790322555';
  static const String supportWhatsapp = '962790322555';
  static const String supportEmail = 'support@ghayarakjo.com';

  static final ValueNotifier<bool> paymentsEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> winchEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> adsEnabled = ValueNotifier<bool>(true);
}

/// كاش خفيف بالذاكرة للبيانات العامة قليلة التغيير (Speed Engineer)
class AppMemoryCache {
  AppMemoryCache._();
  static final Map<String, ({Object? data, DateTime expiresAt})> _store = {};

  static T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  static void set<T>(
    String key,
    T value, {
    Duration ttl = const Duration(seconds: 90),
  }) {
    _store[key] = (data: value, expiresAt: DateTime.now().add(ttl));
  }

  static void invalidate(String key) => _store.remove(key);
  static void clear() => _store.clear();
}