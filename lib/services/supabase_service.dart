import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/db_models.dart';

class SupabaseService {
  final SupabaseClient _db = Supabase.instance.client;

  User? get currentAuthUser => _db.auth.currentUser;

  // ---------------- المصادقة وحساب العميل ----------------
  Future<CustomerProfile?> fetchMyProfile() async {
    final uid = currentAuthUser?.id;
    if (uid == null) return null;
    final data =
        await _db.from('customers').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return CustomerProfile.fromMap(data);
  }

  Future<CustomerProfile> signUpWithProfile({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role, // 'user', 'mechanic', 'towing', 'admin'
  }) async {
    final res = await _db.auth.signUp(email: email, password: password);
    final user = res.user!;
    final profileMap = {
      'id': user.id,
      'email': email,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'is_admin': role == 'admin',
      'subscription_plan': 'free',
      'commission_rate': 0.15,
    };
    await _db.from('customers').upsert(profileMap);
    return CustomerProfile.fromMap(profileMap);
  }

  Future<CustomerProfile?> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email, password: password);
    return fetchMyProfile();
  }

  Future<void> signOut() => _db.auth.signOut();

  // ---------------- الإعلانات وقطع الغيار ----------------
  Future<List<Map<String, dynamic>>> fetchActiveAds() async {
    return await _db.from('advertisements').select().eq('is_active', true);
  }

  Future<List<DbProduct>> fetchProducts(
      {String? category, String? search}) async {
    var query = _db
        .from('products')
        .select()
        .eq('is_hidden', false)
        .eq('is_sold', false);
    if (category != null && category != 'الكل') {
      query = query.eq('main_category', category);
    }
    final rows = await query.order('created_at', ascending: false);
    final list = rows.map<DbProduct>((r) => DbProduct.fromMap(r)).toList();
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      return list
          .where((p) =>
              p.title.toLowerCase().contains(q) ||
              (p.chassisNumber?.toLowerCase().contains(q) ?? false) ||
              p.carName.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // ---------------- شراء قطعة وتسجيل الأرباح والخصم التلقائي للعمولة ----------------
  Future<void> createPartOrder({
    required DbProduct product,
    required String paymentMethod, // 'visa' | 'apple_pay' | 'google_pay' | 'cash'
    double consumerFee = 0.0,
  }) async {
    final buyerId = currentAuthUser!.id;
    final sellerData = await _db
        .from('customers')
        .select('commission_rate, wallet_balance, pending_commission_debt')
        .eq('id', product.userId)
        .single();

    final double commRate =
        (sellerData['commission_rate'] as num?)?.toDouble() ?? 0.15;
    final double partPrice = product.price;
    final double sellerCommission =
        double.parse((partPrice * commRate).toStringAsFixed(2));
    final double sellerNet =
        double.parse((partPrice - sellerCommission).toStringAsFixed(2));
    final double totalPaid =
        double.parse((partPrice + consumerFee).toStringAsFixed(2));

    // 1) إدراج في part_orders
    final order = await _db.from('part_orders').insert({
      'product_id': product.id,
      'seller_id': product.userId,
      'buyer_id': buyerId,
      'part_price': partPrice,
      'consumer_fee': consumerFee,
      'total_paid': totalPaid,
      'seller_commission': sellerCommission,
      'seller_net_amount': sellerNet,
      'payment_method': paymentMethod,
      'status': paymentMethod == 'cash' ? 'pending' : 'paid',
    }).select().single();

    // 2) تسجيل الحركة المالية في wallet_transactions (قبل وبعد العمولة)
    await _db.from('wallet_transactions').insert({
      'provider_id': product.userId,
      'customer_id': buyerId,
      'reference_id': order['id'],
      'transaction_type': 'part_order',
      'payment_method': paymentMethod,
      'gross_amount': partPrice,
      'commission_rate': commRate,
      'commission_amount': sellerCommission,
      'net_amount': sellerNet,
      'status': 'completed',
    });

    // 3) تحديث رصيد المحفظة / ذمة العمولة
    final currentWallet =
        (sellerData['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    final currentDebt =
        (sellerData['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;

    if (paymentMethod == 'cash') {
      await _db.from('customers').update({
        'pending_commission_debt':
            double.parse((currentDebt + sellerCommission).toStringAsFixed(2)),
      }).eq('id', product.userId);
    } else {
      final autoDeduct = currentDebt > 0
          ? (sellerNet < currentDebt ? sellerNet : currentDebt)
          : 0.0;
      final creditWallet =
          double.parse((sellerNet - autoDeduct).toStringAsFixed(2));
      final newDebt =
          double.parse((currentDebt - autoDeduct).toStringAsFixed(2));

      await _db.from('customers').update({
        'wallet_balance':
            double.parse((currentWallet + creditWallet).toStringAsFixed(2)),
        'pending_commission_debt': newDebt < 0 ? 0.0 : newDebt,
      }).eq('id', product.userId);

      if (autoDeduct > 0) {
        await _db.from('wallet_transactions').insert({
          'provider_id': product.userId,
          'customer_id': product.userId,
          'reference_id': order['id'],
          'transaction_type': 'commission_auto_deduct',
          'payment_method': paymentMethod,
          'gross_amount': autoDeduct,
          'commission_rate': 1.0,
          'commission_amount': autoDeduct,
          'net_amount': -autoDeduct,
          'status': 'completed',
        });
      }
    }
  }

  // ---------------- طلبات الطوارئ (الونش والميكانيكي) بالبث المباشر ----------------
  Future<void> createEmergencyRequest({
    required String serviceType, // 'winch' | 'mechanic'
    required String carDetails,
    required String phone,
    required String problemDescription,
    required double pickupLat,
    required double pickupLng,
    required String address,
    required double totalAmount,
    required double commissionAmount,
    required String estimatedTime,
  }) async {
    await _db.from('mechanic_requests').insert({
      'user_id': currentAuthUser!.id,
      'service_type': serviceType,
      'car_details': carDetails,
      'phone': phone,
      'description': problemDescription,
      'latitude': pickupLat,
      'longitude': pickupLng,
      'pickup_latitude': pickupLat,
      'pickup_longitude': pickupLng,
      'dropoff_address': address,
      'total_amount': totalAmount,
      'commission_amount': commissionAmount,
      'estimated_time': estimatedTime,
      'status': 'pending',
      'progress_step': 'pending',
      'payment_status': 'unpaid',
    });
  }

  Stream<List<DbMechanicRequest>> streamEmergencyRequests() {
    return _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DbMechanicRequest.fromMap).toList());
  }

  Future<void> updateEmergencyProgress(DbMechanicRequest req) async {
    final myId = currentAuthUser!.id;
    if (req.status == 'pending') {
      await _db.from('mechanic_requests').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
        'mechanic_id': myId,
      }).eq('id', req.id);
    } else if (req.status == 'accepted') {
      await _db.from('mechanic_requests').update({
        'status': 'completed',
        'progress_step': 'completed',
        'payment_status': 'paid',
      }).eq('id', req.id);

      final net = req.totalAmount - req.commissionAmount;
      final rate =
          req.totalAmount > 0 ? (req.commissionAmount / req.totalAmount) : 0.15;
      await _db.from('wallet_transactions').insert({
        'provider_id': myId,
        'customer_id': req.userId,
        'reference_id': req.id,
        'transaction_type': 'emergency_${req.serviceType}',
        'payment_method': 'cash',
        'gross_amount': req.totalAmount,
        'commission_rate': rate,
        'commission_amount': req.commissionAmount,
        'net_amount': net,
        'status': 'completed',
      });

      // إضافة العمولة المستحقة لطلب الكاش على ذمة المزود
      final me = await _db
          .from('customers')
          .select('pending_commission_debt')
          .eq('id', myId)
          .maybeSingle();
      final currentDebt =
          (me?['pending_commission_debt'] as num?)?.toDouble() ?? 0.0;
      await _db.from('customers').update({
        'pending_commission_debt':
            double.parse((currentDebt + req.commissionAmount).toStringAsFixed(2)),
      }).eq('id', myId);
    }
  }

  // ---------------- حجوزات الورشة ----------------
  Future<List<CustomerProfile>> fetchWorkshops() async {
    final rows = await _db.from('customers').select().eq('role', 'mechanic');
    return rows
        .map<CustomerProfile>((r) => CustomerProfile.fromMap(r))
        .toList();
  }

  Future<void> createWorkshopAppointment({
    required String workshopId,
    required String date,
    required String time,
    required String description,
  }) async {
    await _db.from('workshop_appointments').insert({
      'user_id': currentAuthUser!.id,
      'workshop_id': workshopId,
      'appointment_date': date,
      'appointment_time': time,
      'service_description': description,
      'status': 'pending',
      'progress_step': 'pending',
    });
  }

  Stream<List<DbWorkshopAppointment>> streamWorkshopAppointments() {
    return _db
        .from('workshop_appointments')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DbWorkshopAppointment.fromMap).toList());
  }

  // ---------------- المحفظة والعضويات و CliQ ----------------
  Stream<List<DbWalletTransaction>> streamMyWalletTransactions() {
    final uid = currentAuthUser!.id;
    return _db
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('provider_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DbWalletTransaction.fromMap).toList());
  }

  Future<void> submitSubscriptionRequest({
    required String planName,
    required String paymentMethod, // 'cliq' | 'visa'
    required String amount,
    String? cliqReference,
  }) async {
    final user = currentAuthUser!;
    await _db.from('subscription_requests').insert({
      'user_id': user.id,
      'plan_name': planName,
      'payment_method': paymentMethod,
      'amount': amount,
      'status': 'pending',
    });

    if (paymentMethod == 'cliq' && cliqReference != null) {
      await _db.from('cliq_requests').insert({
        'user_id': user.id,
        'user_email': user.email,
        'transaction_ref': cliqReference,
        'status': 'pending',
      });
    }
  }

  // ---------------- السوبر أدمن: الإعدادات، التجار، واعتماد الطلبات ----------------
  Future<Map<String, String>> fetchSystemSettings() async {
    final rows = await _db.from('system_settings').select();
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> upsertSystemSetting(String key, String value) async {
    await _db.from('system_settings').upsert({
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<CustomerProfile>> fetchAllMerchants() async {
    final rows = await _db
        .from('customers')
        .select()
        .inFilter('role', ['mechanic', 'towing']);
    return rows
        .map<CustomerProfile>((r) => CustomerProfile.fromMap(r))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPendingSubscriptions() async {
    return await _db
        .from('subscription_requests')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: false);
  }

  Future<void> approveSubscriptionRequest({
    required String requestId,
    required String userId,
    required String planName,
    required double newCommissionRate,
  }) async {
    await _db
        .from('subscription_requests')
        .update({'status': 'approved'}).eq('id', requestId);
    await _db.from('customers').update({
      'subscription_plan': planName,
      'commission_rate': newCommissionRate,
      'subscription_expires_at':
          DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    }).eq('id', userId);
  }
}