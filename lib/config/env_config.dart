import 'package:flutter/foundation.dart';

class EnvConfig {
  static const String supabaseUrl = 'https://nsdymdqrlvbhvurwptvq.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zZHltZHFybHZiaHZ1cndwdHZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNTQzOTcsImV4cCI6MjEwODkzMDM5N30.IVrWoj0WcapQn9cQS4NYlqKtZI8c4VCq3dPg3BwF0zY';

  /// false = إخفاء كل شاشات الدفع والمحافظ والاشتراكات
  static final ValueNotifier<bool> paymentsEnabled = ValueNotifier<bool>(false);

  /// false = إخفاء كل ما يتعلق بالونش (التسجيل، الطلب، الداش بورد)
  static final ValueNotifier<bool> winchEnabled = ValueNotifier<bool>(false);
}