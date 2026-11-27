import 'package:flutter/foundation.dart';

class EnvConfig {
  // مرتبط الآن عبر Cloudflare Proxy للحماية من الاختراقات وهجمات DDoS
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://api.ghayarakjo.com',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String admobAndroidBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111', // Test ID
  );

  static const String admobIosBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716', // Test ID
  );

  // بيانات الدعم الفني (static const لقبولها داخل const Text في كل الشاشات)
  static const String supportPhone = '0790322555';
  static const String supportWhatsapp = '962790322555';
  static const String supportEmail = 'support@ghayarakjo.com';

  // إعدادات Apple Pay و Google Pay (تُفعّل لاحقاً عبر dart-define عند تفعيل حساب المطور وبوابة الدفع)
  static const bool applePayEnabled = bool.fromEnvironment(
    'APPLE_PAY_ENABLED',
    defaultValue: false,
  );
  static const String applePayMerchantId = String.fromEnvironment(
    'APPLE_PAY_MERCHANT_ID',
    defaultValue: 'merchant.com.ghiyarak.jo',
  );
  static const bool googlePayEnabled = bool.fromEnvironment(
    'GOOGLE_PAY_ENABLED',
    defaultValue: false,
  );
  static const String googlePayMerchantId = String.fromEnvironment(
    'GOOGLE_PAY_MERCHANT_ID',
    defaultValue: '',
  );
  static const String googlePayGateway = String.fromEnvironment(
    'GOOGLE_PAY_GATEWAY',
    defaultValue: 'mpgs',
  );
  static const String googlePayGatewayMerchantId = String.fromEnvironment(
    'GOOGLE_PAY_GATEWAY_MERCHANT_ID',
    defaultValue: '',
  );
  static const String paymentCountryCode = String.fromEnvironment(
    'PAYMENT_COUNTRY_CODE',
    defaultValue: 'JO',
  );
  static const String paymentCurrencyCode = String.fromEnvironment(
    'PAYMENT_CURRENCY_CODE',
    defaultValue: 'JOD',
  );

  // مفاتيح التحكم الحية من لوحة الأدمن (منفصلة عن بعضها بالكامل)
  static final ValueNotifier<bool> paymentsEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> subscriptionsEnabled =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> winchEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> adsEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> maintenanceMode = ValueNotifier<bool>(false);
}

/// كاش خفيف بالذاكرة للبيانات العامة قليلة التغيير
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