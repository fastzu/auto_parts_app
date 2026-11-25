import 'package:flutter/foundation.dart';

class EnvConfig {
  // للإنتاج والنشر: مرّر المفاتيح عبر --dart-define
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nsdymdqrlvbhvurwptvq.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zZHltZHFybHZiaHZ1cndwdHZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNTQzOTcsImV4cCI6MjEwODkzMDM5N30.IVrWoj0WcapQn9cQS4NYlqKtZI8c4VCq3dPg3BwF0zY',
  );

  // معرّفات Google AdMob
  static const String admobAndroidBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String admobIosBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );

  // إعدادات الدفع (الأردن - دينار أردني)
  static const String paymentCountryCode = String.fromEnvironment(
    'PAYMENT_COUNTRY_CODE',
    defaultValue: 'JO',
  );
  static const String paymentCurrencyCode = String.fromEnvironment(
    'PAYMENT_CURRENCY_CODE',
    defaultValue: 'JOD',
  );

  // إعدادات Apple Pay (تُفعّل تلقائياً عند تمرير APPLE_PAY_MERCHANT_ID)
  static const String applePayMerchantId = String.fromEnvironment(
    'APPLE_PAY_MERCHANT_ID',
    defaultValue: '',
  );
  static bool get applePayEnabled => applePayMerchantId.isNotEmpty;

  // إعدادات Google Pay (تُفعّل تلقائياً عند تمرير GOOGLE_PAY_MERCHANT_ID)
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
  static bool get googlePayEnabled => googlePayMerchantId.isNotEmpty;

  static const String supportPhone = '0790322555';
  static const String supportWhatsapp = '962790322555';
  static const String supportEmail = 'support@ghayarakjo.com';

  // مفاتيح التحكم من لوحة السوبر أدمن (منفصلة تماماً)
  static final ValueNotifier<bool> paymentsEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> subscriptionsEnabled =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> winchEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> adsEnabled = ValueNotifier<bool>(true);
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