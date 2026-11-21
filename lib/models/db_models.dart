class CustomerProfile {
  final String id;
  final String? username;
  final String? fullName;
  final String? email;
  final String? phone;
  final String role;
  final bool isAdmin;
  final bool hasTowing;
  final bool isAvailable;
  final double? latitude;
  final double? longitude;
  final double? workshopLatitude;
  final double? workshopLongitude;
  final String? workshopAddress;
  final String? streetName;
  final String? buildingNumber;
  final String? workshopImageUrl;
  final String? winchPlateNumber;
  final int maxCarCapacity;
  final String openingHours;
  final String subscriptionPlan;
  final double commissionRate;
  final bool isTrustedMerchant;
  final double walletBalance;
  final double pendingCommissionDebt;
  final bool isOwnerWinchDriver;
  final String? winchDriverName;
  final String? winchDriverPhone;
  final DateTime? subscriptionExpiresAt;
  final double ratingAvg;
  final int ratingCount;

  CustomerProfile({
    required this.id,
    this.username,
    this.fullName,
    this.email,
    this.phone,
    this.role = 'user',
    this.isAdmin = false,
    this.hasTowing = false,
    this.isAvailable = true,
    this.latitude,
    this.longitude,
    this.workshopLatitude,
    this.workshopLongitude,
    this.workshopAddress,
    this.streetName,
    this.buildingNumber,
    this.workshopImageUrl,
    this.winchPlateNumber,
    this.maxCarCapacity = 5,
    this.openingHours = '08:00 ص - 08:00 م',
    this.subscriptionPlan = 'free',
    this.commissionRate = 0.15,
    this.isTrustedMerchant = false,
    this.walletBalance = 0.0,
    this.pendingCommissionDebt = 0.0,
    this.isOwnerWinchDriver = true,
    this.winchDriverName,
    this.winchDriverPhone,
    this.subscriptionExpiresAt,
    this.ratingAvg = 0.0,
    this.ratingCount = 0,
  });
  int get seoBoostTier {
    if (subscriptionExpiresAt != null &&
        subscriptionExpiresAt!.isBefore(DateTime.now())) {
      return 0;
    }
    return switch (subscriptionPlan) {
      'provider_12m' => 3,
      'provider_6m' => 2,
      'provider_3m' => 1,
      _ => 0,
    };
  }

  factory CustomerProfile.fromMap(Map<String, dynamic> map) {
    return CustomerProfile(
      id: map['id'] as String,
      username: map['username'] as String?,
      fullName: map['full_name'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      role: (map['role'] as String?) ?? 'user',
      isAdmin: (map['is_admin'] as bool?) ?? false,
      hasTowing: (map['has_towing'] as bool?) ?? false,
      isAvailable: (map['is_available'] as bool?) ?? true,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      workshopLatitude: (map['workshop_latitude'] as num?)?.toDouble(),
      workshopLongitude: (map['workshop_longitude'] as num?)?.toDouble(),
      workshopAddress: map['workshop_address'] as String?,
      streetName: map['street_name'] as String?,
      buildingNumber: map['building_number'] as String?,
      workshopImageUrl: map['workshop_image_url'] as String?,
      winchPlateNumber: map['winch_plate_number'] as String?,
      maxCarCapacity: (map['max_car_capacity'] as int?) ?? 5,
      openingHours: (map['opening_hours'] as String?) ?? '08:00 ص - 08:00 م',
      subscriptionPlan: (map['subscription_plan'] as String?) ?? 'free',
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0.15,
      isTrustedMerchant: (map['is_trusted_merchant'] as bool?) ?? false,
      walletBalance: (map['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      pendingCommissionDebt:
          (map['pending_commission_debt'] as num?)?.toDouble() ?? 0.0,
      isOwnerWinchDriver: (map['is_owner_winch_driver'] as bool?) ?? true,
      winchDriverName: map['winch_driver_name'] as String?,
      winchDriverPhone: map['winch_driver_phone'] as String?,
      subscriptionExpiresAt: map['subscription_expires_at'] != null
          ? DateTime.tryParse(map['subscription_expires_at'].toString())
          : null,
      ratingAvg: (map['rating_avg'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (map['rating_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DbProduct {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String mainCategory;
  final String subCategory;
  final String? chassisNumber;
  final String carModel;
  final String carName;
  final List<String> images;
  final double price;
  final int quantity;
  final bool isSold;
  final bool isHidden;
  final int viewsCount;
  final int clicksCount;
  final int salesCount;

  DbProduct({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.mainCategory,
    required this.subCategory,
    this.chassisNumber,
    required this.carModel,
    required this.carName,
    required this.images,
    required this.price,
    this.quantity = 1,
    this.isSold = false,
    this.isHidden = false,
    this.viewsCount = 0,
    this.clicksCount = 0,
    this.salesCount = 0,
  });

  factory DbProduct.fromMap(Map<String, dynamic> map) {
    return DbProduct(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      mainCategory: (map['main_category'] as String?) ?? '',
      subCategory: (map['sub_category'] as String?) ?? '',
      chassisNumber: map['chassis_number'] as String?,
      carModel: (map['car_model'] as String?) ?? '',
      carName: (map['car_name'] as String?) ?? '',
      images: List<String>.from(map['images'] ?? []),
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as int?) ?? 1,
      isSold: (map['is_sold'] as bool?) ?? false,
      isHidden: (map['is_hidden'] as bool?) ?? false,
      viewsCount: (map['views_count'] as int?) ?? 0,
      clicksCount: (map['clicks_count'] as int?) ?? 0,
      salesCount: (map['sales_count'] as int?) ?? 0,
    );
  }
}

class DbMechanicRequest {
  final String id;
  final String? userId;
  final String? mechanicId;
  final String serviceType;
  final String carDetails;
  final String? phone;
  final String? description;
  final String status;
  final String progressStep;
  final double totalAmount;
  final double commissionAmount;
  final String paymentStatus;
  final double? latitude;
  final double? longitude;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropoffLatitude;
  final double? dropoffLongitude;
  final String? dropoffAddress;
  final String? estimatedTime;
  final bool broadcastAll;

  DbMechanicRequest({
    required this.id,
    this.userId,
    this.mechanicId,
    required this.serviceType,
    required this.carDetails,
    this.phone,
    this.description,
    required this.status,
    required this.progressStep,
    required this.totalAmount,
    required this.commissionAmount,
    required this.paymentStatus,
    this.latitude,
    this.longitude,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropoffLatitude,
    this.dropoffLongitude,
    this.dropoffAddress,
    this.estimatedTime,
    this.broadcastAll = false,
  });

  factory DbMechanicRequest.fromMap(Map<String, dynamic> map) {
    return DbMechanicRequest(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      mechanicId: map['mechanic_id'] as String?,
      serviceType: (map['service_type'] as String?) ?? 'winch',
      carDetails: (map['car_details'] as String?) ?? '',
      phone: map['phone'] as String?,
      description: map['description'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      progressStep: (map['progress_step'] as String?) ?? 'pending',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      commissionAmount: (map['commission_amount'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: (map['payment_status'] as String?) ?? 'unpaid',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      pickupLatitude: (map['pickup_latitude'] as num?)?.toDouble() ??
          (map['latitude'] as num?)?.toDouble(),
      pickupLongitude: (map['pickup_longitude'] as num?)?.toDouble() ??
          (map['longitude'] as num?)?.toDouble(),
      dropoffLatitude: (map['dropoff_latitude'] as num?)?.toDouble(),
      dropoffLongitude: (map['dropoff_longitude'] as num?)?.toDouble(),
      dropoffAddress: map['dropoff_address'] as String?,
      estimatedTime: map['estimated_time'] as String?,
      broadcastAll: (map['broadcast_all'] as bool?) ?? false,
    );
  }
}

class DbWalletTransaction {
  final String id;
  final String? providerId;
  final String? customerId;
  final String? referenceId;
  final String transactionType;
  final String paymentMethod;
  final double grossAmount;
  final double commissionRate;
  final double commissionAmount;
  final double netAmount;
  final String status;
  final DateTime createdAt;

  DbWalletTransaction({
    required this.id,
    this.providerId,
    this.customerId,
    this.referenceId,
    required this.transactionType,
    required this.paymentMethod,
    required this.grossAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.netAmount,
    required this.status,
    required this.createdAt,
  });

  factory DbWalletTransaction.fromMap(Map<String, dynamic> map) {
    return DbWalletTransaction(
      id: map['id'] as String,
      providerId: map['provider_id'] as String?,
      customerId: map['customer_id'] as String?,
      referenceId: map['reference_id'] as String?,
      transactionType: (map['transaction_type'] as String?) ?? 'order',
      paymentMethod: (map['payment_method'] as String?) ?? 'visa',
      grossAmount: (map['gross_amount'] as num?)?.toDouble() ?? 0.0,
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0.0,
      commissionAmount: (map['commission_amount'] as num?)?.toDouble() ?? 0.0,
      netAmount: (map['net_amount'] as num?)?.toDouble() ?? 0.0,
      status: (map['status'] as String?) ?? 'completed',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class DbWorkshopAppointment {
  final String id;
  final String? userId;
  final String? workshopId;
  final String appointmentDate;
  final String appointmentTime;
  final String? serviceDescription;
  final String status;
  final String progressStep;
  final double totalAmount;
  final double platformCommission;
  final String paymentMethod;
  final String paymentStatus;

  DbWorkshopAppointment({
    required this.id,
    this.userId,
    this.workshopId,
    required this.appointmentDate,
    required this.appointmentTime,
    this.serviceDescription,
    required this.status,
    required this.progressStep,
    required this.totalAmount,
    required this.platformCommission,
    required this.paymentMethod,
    this.paymentStatus = 'unpaid',
  });

  factory DbWorkshopAppointment.fromMap(Map<String, dynamic> map) {
    return DbWorkshopAppointment(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      workshopId: map['workshop_id'] as String?,
      appointmentDate: (map['appointment_date'] as String?) ?? '',
      appointmentTime: (map['appointment_time'] as String?) ?? '',
      serviceDescription: map['service_description'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      progressStep: (map['progress_step'] as String?) ?? 'pending',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      platformCommission:
          (map['platform_commission'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (map['payment_method'] as String?) ?? 'cash',
      paymentStatus: (map['payment_status'] as String?) ?? 'unpaid',
    );
  }
}

class DbDiscount {
  final String id;
  final String title;
  final String code;
  final String? description;
  final double discountPercent;
  final String targetRole;
  final String targetCategory;
  final bool isActive;
  final DateTime? expiresAt;

  DbDiscount({
    required this.id,
    required this.title,
    required this.code,
    this.description,
    required this.discountPercent,
    this.targetRole = 'all',
    this.targetCategory = 'الكل',
    this.isActive = true,
    this.expiresAt,
  });

  factory DbDiscount.fromMap(Map<String, dynamic> map) {
    return DbDiscount(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      description: map['description'] as String?,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0.0,
      targetRole: (map['target_role'] as String?) ?? 'all',
      targetCategory: (map['target_category'] as String?) ?? 'الكل',
      isActive: (map['is_active'] as bool?) ?? true,
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'] as String)
          : null,
    );
  }
}
