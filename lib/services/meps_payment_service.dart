import 'package:supabase_flutter/supabase_flutter.dart';

class MepsPaymentService {
  final SupabaseClient _client = Supabase.instance.client;

  /// ينشئ جلسة دفع MEPS عبر Supabase Edge Function ويُرجع رابط صفحة الدفع (Checkout URL)
  Future<String?> createCheckoutSession({
    required double amountJod,
    required String orderId,
    required String description,
  }) async {
    final res = await _client.functions.invoke(
      'meps-create-session',
      body: {
        'amount': amountJod.toStringAsFixed(2),
        'currency': 'JOD',
        'orderId': orderId,
        'description': description,
      },
    );

    if (res.status == 200 && res.data != null) {
      return res.data['checkoutUrl'] as String?;
    }
    return null;
  }
}