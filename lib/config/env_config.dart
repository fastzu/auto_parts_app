import 'package:flutter/foundation.dart';

class EnvConfig {
  static const String supabaseUrl = 'https://nsdymdqrlvbhvurwptvq.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zZHltZHFybHZiaHZ1cndwdHZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNTQzOTcsImV4cCI6MjEwODkzMDM5N30.IVrWoj0WcapQn9cQS4NYlqKtZI8c4VCq3dPg3BwF0zY';

  static const String supportPhone = '0790322555';
  static const String supportWhatsapp = '962790322555';
  static const String supportEmail = 'customerservice@ghyarak.com';

  static final ValueNotifier<bool> paymentsEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> winchEnabled = ValueNotifier<bool>(false);
}
