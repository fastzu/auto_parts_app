import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../services/paytabs_payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admob_native_banner.dart';
import '../../widgets/animations.dart';
import '../../widgets/home_ad_banner.dart';
import '../../widgets/home_live_progress_banner.dart';
import 'book_workshop_screen.dart';
import 'chat_screen.dart';
import 'parts_catalog_screen.dart';

/// حساب درجة تعزيز الظهور (SEO Boost) حسب باقة التاجر النشطة
int computeSeoBoostTier(String? plan, String? expiresAt) {
  if (plan == null || plan == 'free') return 0;
  if (expiresAt != null && expiresAt.isNotEmpty) {
    final exp = DateTime.tryParse(expiresAt);
    if (exp != null && exp.isBefore(DateTime.now())) return 0;
  }
  return switch (plan) {
    'provider_12m' => 3,
    'provider_6m' => 2,
    'provider_3m' => 1,
    _ => 0,
  };
}

/// حساب أعلى خصم فعّال على منتج (خصم التاجر نفسه أو خصم الأدمن على الصنف أو للمستخدم المعين)
({int percent, double finalPrice, double originalPrice, String? promoCode})
    computeEffectiveProductDiscount({
  required Map<String, dynamic> product,
  required List<Map<String, dynamic>> activeDiscounts,
  required String? viewerRole,
  required String? viewerId,
}) {
  final currentPrice = ((product['price'] as num?) ?? 0).toDouble();
  final merchantDisc = (product['discount_percent'] as int?) ?? 0;
  final rawOriginal = ((product['original_price'] as num?) ?? 0).toDouble();
  final basePrice = (merchantDisc > 0 && rawOriginal > currentPrice)
      ? rawOriginal
      : currentPrice;

  int bestPercent = merchantDisc;
  String? bestCode;

  final mainCat = (product['main_category'] as String? ?? '').trim();
  final subCat = (product['sub_category'] as String? ?? '').trim();

  for (final d in activeDiscounts) {
    final pct = (d['discount_percent'] as int?) ?? 0;
    if (pct <= 0) continue;

    // التحقق من المستخدم أو الفئة المستهدفة
    final targetUid = d['target_user_id'] as String?;
    final targetRole = (d['target_role'] as String?) ?? 'all';
    final roleMatches = targetUid != null
        ? (viewerId != null && targetUid == viewerId)
        : (targetRole == 'all' ||
            (viewerRole != null && targetRole == viewerRole));
    if (!roleMatches) continue;

    // التحقق من الصنف المشمول بالخصم
    final targetCat = (d['target_category'] as String? ?? 'الكل').trim();
    final catMatches = targetCat.isEmpty ||
        targetCat == 'الكل' ||
        mainCat == targetCat ||
        mainCat.contains(targetCat) ||
        subCat.contains(targetCat);
    if (!catMatches) continue;

    if (pct > bestPercent) {
      bestPercent = pct;
      bestCode = d['code'] as String?;
    }
  }

  final finalPrice = bestPercent > 0
      ? double.parse((basePrice * (1 - bestPercent / 100)).toStringAsFixed(2))
      : basePrice;

  return (
    percent: bestPercent,
    finalPrice: finalPrice,
    originalPrice: basePrice,
    promoCode: bestCode,
  );
}

/// نافذة إبلاغ موحدة للمنتجات أو الحسابات (متطلب Apple Guideline 1.2)
Future<void> showContentReportDialog(
  BuildContext context, {
  required String targetType, // 'product' | 'user'
  required String targetId,
  required String targetLabel,
}) async {
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى تسجيل الدخول للإبلاغ عن المحتوى')),
    );
    return;
  }

  final reasons = [
    'سعر وهمي أو مضلل',
    'قطعة غير مطابقة للوصف أو صور مزيفة',
    'احتيال أو تواصل مسيء',
    'محتوى غير لائق أو مخالف',
  ];
  String selectedReason = reasons.first;
  final notesCtrl = TextEditingController();
  bool submitting = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('الإبلاغ عن $targetLabel',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (value) {
                  if (value != null) setD(() => selectedReason = value);
                },
                child: Column(
                  children: reasons
                      .map(
                        (r) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(r, style: const TextStyle(fontSize: 13)),
                          value: r,
                          activeColor: AppColors.orange,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'تفاصيل إضافية (اختياري)',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: submitting
                ? null
                : () async {
                    setD(() => submitting = true);
                    try {
                      final fullReason = notesCtrl.text.trim().isEmpty
                          ? selectedReason
                          : '$selectedReason — ${notesCtrl.text.trim()}';
                      await db.from('content_reports').insert({
                        'reporter_id': uid,
                        'target_type': targetType,
                        'target_id': targetId,
                        'reason': fullReason,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'تم استلام بلاغك، ستقوم الإدارة بمراجعته خلال 24 ساعة ✓'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      setD(() => submitting = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('تعذر إرسال البلاغ: $e'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('إرسال البلاغ'),
          ),
        ],
      ),
    ),
  );
  notesCtrl.dispose();
}

class LiveStoreHomeScreen extends StatefulWidget {
  final CustomerProfile? profile;
  final VoidCallback onOpenDrawer;

  const LiveStoreHomeScreen(
      {super.key, required this.profile, required this.onOpenDrawer});

  @override
  State<LiveStoreHomeScreen> createState() => _LiveStoreHomeScreenState();
}

class _LiveStoreHomeScreenState extends State<LiveStoreHomeScreen> {
  final _db = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _selectedCat = 'الكل';

  String _selectedBrand = JordanCarsCatalog.brands.first;
  String _selectedModel =
      JordanCarsCatalog.brandsAndModels[JordanCarsCatalog.brands.first]!.first;
  String _selectedYear = 'جميع الموديلات';
  bool _filterByCar = false;

  static const int _pageSize = 20;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _activeDiscounts = [];
  final Map<String, Map<String, dynamic>> _sellerMeta = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  List<String> get _cats => ['الكل', ...CarPartsCatalogAZ.mainCategories];

  String get _selectedCarLabel {
    if (!_filterByCar) return 'جميع السيارات';
    final cleanBrand = _selectedBrand.split(' ').first;
    if (_selectedYear == 'جميع الموديلات') return '$cleanBrand $_selectedModel';
    return '$cleanBrand $_selectedModel $_selectedYear';
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _hasMore = true;
    });
    await Future.wait([
      _fetchActiveDiscounts(),
      _fetchProductsPage(reset: true),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchActiveDiscounts() async {
    try {
      final rows = await _db
          .from('discounts')
          .select()
          .eq('is_active', true)
          .order('discount_percent', ascending: false)
          .limit(40);
      final now = DateTime.now();
      final valid = List<Map<String, dynamic>>.from(rows).where((d) {
        final expStr = d['expires_at'] as String?;
        if (expStr == null || expStr.isEmpty) return true;
        final exp = DateTime.tryParse(expStr);
        return exp == null || exp.isAfter(now);
      }).toList();
      _activeDiscounts = valid;
    } catch (_) {}
  }

  Future<void> _fetchProductsPage({required bool reset}) async {
    if (_loadingMore && !reset) return;
    if (!reset) setState(() => _loadingMore = true);

    try {
      final offset = reset ? 0 : _products.length;
      var query = _db
          .from('products')
          .select()
          .eq('is_hidden', false)
          .eq('is_sold', false);

      if (_selectedCat != 'الكل') {
        query = query.or(
            'main_category.ilike.%$_selectedCat%,sub_category.ilike.%$_selectedCat%');
      }
      if (_filterByCar) {
        final cleanBrand = _selectedBrand.split(' ').first;
        query = query
            .ilike('car_name', '%$cleanBrand%')
            .ilike('car_name', '%$_selectedModel%');
      }
      final q = _search.trim();
      if (q.isNotEmpty) {
        query = query.or(
          'title.ilike.%$q%,car_name.ilike.%$q%,sub_category.ilike.%$q%,chassis_number.ilike.%$q%',
        );
      }

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final list = List<Map<String, dynamic>>.from(rows);

      // فلتر سنة الصنع محلياً إن لزم
      final yearFiltered = (!_filterByCar || _selectedYear == 'جميع الموديلات')
          ? list
          : list.where((p) {
              final pYear = (p['car_model'] ?? '').toString();
              return pYear == 'جميع الموديلات' || pYear.contains(_selectedYear);
            }).toList();

      await _loadSellerMetaBatch(yearFiltered);

      if (!mounted) return;
      setState(() {
        if (reset) {
          _products = yearFiltered;
        } else {
          _products.addAll(yearFiltered);
        }
        _hasMore = list.length >= _pageSize;
        _sortBySeoBoost(_products);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadSellerMetaBatch(List<Map<String, dynamic>> items) async {
    final missingIds = items
        .map((p) => p['user_id'] as String?)
        .where((id) => id != null && !_sellerMeta.containsKey(id))
        .cast<String>()
        .toSet()
        .toList();
    if (missingIds.isEmpty) return;

    try {
      final sellers = await _db
          .from('customers')
          .select(
              'id, rating_avg, rating_count, is_trusted_merchant, subscription_plan, subscription_expires_at')
          .inFilter('id', missingIds);
      for (final s in sellers) {
        _sellerMeta[s['id'] as String] = Map<String, dynamic>.from(s);
      }
    } catch (_) {}
  }

  void _sortBySeoBoost(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final sa = _sellerMeta[a['user_id']];
      final sb = _sellerMeta[b['user_id']];
      final boostA = computeSeoBoostTier(
        sa?['subscription_plan'] as String?,
        sa?['subscription_expires_at'] as String?,
      );
      final boostB = computeSeoBoostTier(
        sb?['subscription_plan'] as String?,
        sb?['subscription_expires_at'] as String?,
      );
      if (boostB != boostA) return boostB.compareTo(boostA);
      final dtA = DateTime.tryParse((a['created_at'] as String?) ?? '') ??
          DateTime(2000);
      final dtB = DateTime.tryParse((b['created_at'] as String?) ?? '') ??
          DateTime(2000);
      return dtB.compareTo(dtA);
    });
  }

  void _openCatalog() {
    Navigator.push(
      context,
      animatedRoute(PartsCatalogScreen(
        selectedCarName: _filterByCar ? _selectedCarLabel : 'جميع السيارات',
        viewerProfile: widget.profile,
      )),
    );
  }

  void _openWorkshopSelector() {
    Navigator.push(context,
        animatedRoute(SelectWorkshopScreen(viewerProfile: widget.profile)));
  }

  void _showCarPicker() {
    String tempBrand = _selectedBrand;
    String tempModel = _selectedModel;
    String tempYear = _selectedYear;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final models = JordanCarsCatalog.brandsAndModels[tempBrand]!;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('اختر سيارتك',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setState(() => _filterByCar = false);
                        Navigator.pop(ctx);
                        _loadInitialData();
                      },
                      child: const Text(
                        'عرض جميع السيارات',
                        style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: tempBrand,
                  decoration: InputDecoration(
                    labelText: '1. اختر الشركة (جميع شركات الأردن)',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  items: JordanCarsCatalog.brands
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setModal(() {
                      tempBrand = val;
                      tempModel =
                          JordanCarsCatalog.brandsAndModels[tempBrand]!.first;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('modal_$tempBrand'),
                  isExpanded: true,
                  initialValue: tempModel,
                  decoration: InputDecoration(
                    labelText: '2. اختر الموديل',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setModal(() => tempModel = val);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: tempYear,
                  decoration: InputDecoration(
                    labelText: '3. سنة الصنع',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  items: JordanCarsCatalog.years
                      .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setModal(() => tempYear = val);
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedBrand = tempBrand;
                        _selectedModel = tempModel;
                        _selectedYear = tempYear;
                        _filterByCar = true;
                      });
                      Navigator.pop(ctx);
                      _loadInitialData();
                    },
                    child: const Text('تطبيق الفلتر على المنشورات',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> get _myVisibleDiscounts {
    final uid = widget.profile?.id ?? _db.auth.currentUser?.id;
    final role = widget.profile?.role ?? 'user';
    return _activeDiscounts.where((d) {
      final targetUid = d['target_user_id'] as String?;
      if (targetUid != null) return uid != null && targetUid == uid;
      final r = (d['target_role'] as String?) ?? 'all';
      return r == 'all' || r == role;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bestSellers = List<Map<String, dynamic>>.from(_products)
      ..sort((a, b) =>
          (((b['sales_count'] ?? 0) * 10) + (b['clicks_count'] ?? 0)).compareTo(
              ((a['sales_count'] ?? 0) * 10) + (a['clicks_count'] ?? 0)));
    final visibleDiscounts = _myVisibleDiscounts;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadInitialData,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: widget.onOpenDrawer,
                          icon: const Icon(Icons.menu, size: 26),
                        ),
                        const SizedBox(width: 4),
                        const GhiyarakLogo(size: 36),
                        const SizedBox(width: 8),
                        const Text('غيارك',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    if (widget.profile != null)
                      BounceTap(
                        onTap: () => Navigator.push(
                            context, animatedRoute(const ChatsListScreen())),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.chat_bubble_outline,
                              size: 20, color: AppColors.navy),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const HomeAdBanner(),
                    HomeLiveProgressBanner(viewerProfile: widget.profile),
                    if (visibleDiscounts.isNotEmpty)
                      _discountsStrip(visibleDiscounts),
                    TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) {
                        FocusScope.of(context).unfocus();
                        _search = v;
                        _loadInitialData();
                      },
                      onChanged: (v) {
                        _search = v;
                        if (v.isEmpty) _loadInitialData();
                      },
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم القطعة أو رقم الشاصي أو السيارة',
                        hintStyle: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                        prefixIcon:
                            const Icon(Icons.search, color: AppColors.navy),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _search = '';
                                  _loadInitialData();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _filterByCar
                                ? AppColors.orange
                                : AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _showCarPicker,
                              child: Text(
                                'القطع المناسبة لـ $_selectedCarLabel',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _showCarPicker,
                            child: const Text(
                              'تغيير',
                              style: TextStyle(
                                color: AppColors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _cats.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final c = _cats[i];
                          final active = _selectedCat == c;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedCat = c);
                              _loadInitialData();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    active ? AppColors.navy : AppColors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: active
                                        ? AppColors.navy
                                        : AppColors.border),
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  color: active
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ShimmerProductsLoading(),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الأكثر مبيعاً',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: _openCatalog,
                        child: const Text(
                          'عرض الكل',
                          style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 245,
                  child: bestSellers.isEmpty
                      ? const Center(
                          child: Text('لا توجد قطع حالياً مطابقة للبحث'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: bestSellers.take(8).length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (_, i) => SizedBox(
                            width: 170,
                            child: FadeSlideIn(
                              index: i,
                              child: _card(
                                  bestSellers[i], 'الأكثر مبيعاً', 'best'),
                            ),
                          ),
                        ),
                ),
              ),

              // إعلان Google AdMob المنظّم (سيارات وتمويل) بمكان واحد مرتب بين القسمين
              const SliverToBoxAdapter(child: AdMobNativeBanner()),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('وصل حديثاً',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: _openCatalog,
                        child: const Text(
                          'عرض الكل',
                          style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_products.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('لا توجد قطع غيار مطابقة')),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.69,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => FadeSlideIn(
                          index: i, child: _card(_products[i], 'جديد', 'new')),
                      childCount: _products.length,
                    ),
                  ),
                ),

              if (_hasMore && _products.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _loadingMore
                          ? null
                          : () => _fetchProductsPage(reset: false),
                      child: _loadingMore
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('عرض المزيد من القطع',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 92),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تركيب في ورشة؟',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      const Text(
                        'احجز موعد تركيب القطعة في أقرب ورشة معتمدة',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _openWorkshopSelector,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.navy, width: 1.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'اختيار ورشة وموعد',
                            style: TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _discountsStrip(List<Map<String, dynamic>> discounts) {
    return Container(
      height: 76,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: discounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final d = discounts[i];
          final code = (d['code'] as String?) ?? '';
          final cat = (d['target_category'] as String?) ?? 'الكل';
          final isPersonal = d['target_user_id'] != null;
          return GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'تم نسخ كود الخصم ($code) — والخصم مطبّق تلقائياً على الصنف ✓'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: Container(
              width: 245,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPersonal
                      ? [const Color(0xFF7B1FA2), const Color(0xFF4A148C)]
                      : [AppColors.navy, const Color(0xFF1F2D3D)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${d['discount_percent']}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isPersonal
                              ? '🎁 خصم خاص لك: ${d['title']}'
                              : (d['title'] as String? ?? 'عرض خاص'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'الصنف: $cat · الكود: $code',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.copy, color: Colors.white70, size: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> p, String badge, String heroPrefix) {
    final imgs = List<String>.from(p['images'] ?? []);
    final heroTag = '${heroPrefix}_${p['id']}';
    final seller = _sellerMeta[p['user_id']];
    final ratingAvg = ((seller?['rating_avg'] as num?) ?? 0).toDouble();
    final ratingCount = (seller?['rating_count'] as int?) ?? 0;
    final boost = computeSeoBoostTier(
      seller?['subscription_plan'] as String?,
      seller?['subscription_expires_at'] as String?,
    );

    final disc = computeEffectiveProductDiscount(
      product: p,
      activeDiscounts: _activeDiscounts,
      viewerRole: widget.profile?.role ?? 'user',
      viewerId: widget.profile?.id ?? _db.auth.currentUser?.id,
    );

    return BounceTap(
      onTap: () => Navigator.push(
        context,
        animatedRoute(
          ProductDetailsScreen(
            product: p,
            viewerProfile: widget.profile,
            heroTag: heroTag,
            effectiveDiscountPercent: disc.percent,
            effectivePrice: disc.finalPrice,
            originalPrice: disc.originalPrice,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: boost >= 2
                ? AppColors.orange.withValues(alpha: 0.6)
                : AppColors.border,
            width: boost >= 2 ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Hero(
                  tag: heroTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 98,
                      width: double.infinity,
                      child: imgs.isNotEmpty
                          ? Image.network(
                              imgs.first,
                              fit: BoxFit.cover,
                              cacheWidth: 420,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.placeholder,
                                child: const Icon(Icons.settings_outlined,
                                    color: AppColors.textSecondary),
                              ),
                            )
                          : Container(
                              color: AppColors.placeholder,
                              child: const Icon(
                                Icons.settings_outlined,
                                color: AppColors.textSecondary,
                                size: 32,
                              ),
                            ),
                    ),
                  ),
                ),
                // شارة الحالة (أعلى اليمين)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: boost > 0 ? AppColors.navy : AppColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      boost > 0 ? 'مميز ★' : badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // شارة الخصم (أعلى اليسار — مكان مرتب بدون تداخل!)
                if (disc.percent > 0)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '-${disc.percent}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (p['title'] as String?) ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              '${p['car_name']} · ${p['car_model']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            if (ratingCount > 0) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 13),
                  const SizedBox(width: 2),
                  Text(
                    '${ratingAvg.toStringAsFixed(1)} ($ratingCount)',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy),
                  ),
                ],
              ),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (disc.percent > 0)
                      Text(
                        '${disc.originalPrice.toStringAsFixed(1)} د.أ',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    Text(
                      '${disc.finalPrice.toStringAsFixed(disc.percent > 0 ? 2 : 1)} د.أ',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: disc.percent > 0
                            ? Colors.red.shade700
                            : AppColors.navy,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(9)),
                  child: const Text(
                    'التفاصيل',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProductDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final CustomerProfile? viewerProfile;
  final String? heroTag;
  final int effectiveDiscountPercent;
  final double? effectivePrice;
  final double? originalPrice;

  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.viewerProfile,
    this.heroTag,
    this.effectiveDiscountPercent = 0,
    this.effectivePrice,
    this.originalPrice,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final _db = Supabase.instance.client;
  final _msgCtrl = TextEditingController();
  CustomerProfile? _seller;
  double _sellerRatingAvg = 0;
  int _sellerRatingCount = 0;
  bool _loadingSeller = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _trackAndLoadSeller();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _trackAndLoadSeller() async {
    try {
      await _db.rpc('increment_product_click',
          params: {'p_id': widget.product['id']});
      await _db.rpc('increment_product_view',
          params: {'p_id': widget.product['id']});
      final sellerMap = await _db
          .from('customers')
          .select()
          .eq('id', widget.product['user_id'])
          .maybeSingle();
      if (mounted) {
        setState(() {
          _seller =
              sellerMap != null ? CustomerProfile.fromMap(sellerMap) : null;
          _sellerRatingAvg =
              ((sellerMap?['rating_avg'] as num?) ?? 0).toDouble();
          _sellerRatingCount = (sellerMap?['rating_count'] as int?) ?? 0;
          _loadingSeller = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSeller = false);
    }
  }

  Future<void> _sendMessage() async {
    FocusScope.of(context).unfocus();
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || widget.viewerProfile == null) return;
    setState(() => _sending = true);
    try {
      await _db.from('messages').insert({
        'sender_id': widget.viewerProfile!.id,
        'receiver_id': widget.product['user_id'],
        'product_id': widget.product['id'],
        'message': text,
      });
      _msgCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال رسالتك إلى البائع بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final imgs = List<String>.from(p['images'] ?? []);
    final basePrice = ((p['price'] as num?) ?? 0).toDouble();
    final displayPrice = widget.effectivePrice ?? basePrice;
    final origPrice = widget.originalPrice ??
        ((p['original_price'] as num?)?.toDouble() ?? basePrice);
    final discPct = widget.effectiveDiscountPercent > 0
        ? widget.effectiveDiscountPercent
        : ((p['discount_percent'] as int?) ?? 0);
    final isOwnProduct =
        (widget.viewerProfile?.id ?? _db.auth.currentUser?.id) == p['user_id'];

    final imageBox = imgs.isNotEmpty
        ? SizedBox(
            height: 220,
            child: PageView.builder(
              itemCount: imgs.length,
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child:
                    Image.network(imgs[i], fit: BoxFit.cover, cacheWidth: 900),
              ),
            ),
          )
        : Container(
            height: 180,
            decoration: BoxDecoration(
                color: AppColors.placeholder,
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.settings_outlined,
                size: 54, color: AppColors.textSecondary),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text((p['title'] as String?) ?? 'تفاصيل القطعة'),
        actions: [
          if (!isOwnProduct)
            IconButton(
              tooltip: 'إبلاغ عن المنشور',
              icon: const Icon(Icons.flag_outlined, color: Colors.redAccent),
              onPressed: () => showContentReportDialog(
                context,
                targetType: 'product',
                targetId: p['id'] as String,
                targetLabel: 'هذا المنشور',
              ),
            ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          Stack(
            children: [
              if (widget.heroTag != null)
                Hero(tag: widget.heroTag!, child: imageBox)
              else
                imageBox,
              if (discPct > 0)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'خصم $discPct%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (p['title'] as String?) ?? '',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (discPct > 0)
                    Text(
                      '${origPrice.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    '${displayPrice.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p['main_category'] ?? ''} · ${p['sub_category'] ?? ''}',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          Text(
            'السيارة: ${p['car_name']} · الموديل: ${p['car_model']}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if ((p['chassis_number'] as String? ?? '').isNotEmpty)
            Text(
              'رقم الشاصي: ${p['chassis_number']}',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Text((p['description'] as String?) ?? ''),
          ),
          if (EnvConfig.paymentsEnabled.value &&
              !isOwnProduct &&
              widget.viewerProfile != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.shopping_cart_checkout),
                label: Text(
                  'شراء ودفع آمن عبر التطبيق (${displayPrice.toStringAsFixed(2)} د.أ)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final ok = await PayTabsPaymentService().startPaymentFlow(
                    context: context,
                    baseAmount: displayPrice,
                    title: 'شراء قطعة: ${p['title']}',
                    orderType: 'ord',
                    referenceId: p['id'] as String,
                    email: widget.viewerProfile?.email,
                    phone: widget.viewerProfile?.phone,
                    name: widget.viewerProfile?.fullName,
                  );
                  if (ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم إرسال طلب الشراء بنجاح! ✓'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تركيب في ورشة؟',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                const Text(
                  'احجز موعد تركيب هذه القطعة في ورشة معتمدة',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      animatedRoute(SelectWorkshopScreen(
                          viewerProfile: widget.viewerProfile)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.navy, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'اختيار ورشة وموعد',
                      style: TextStyle(
                          color: AppColors.navy, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: _loadingSeller
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('معلومات البائع والتاجر',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.navy,
                            child: Icon(Icons.storefront, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _seller?.fullName ?? 'التاجر',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    if (_seller?.isTrustedMerchant == true) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified,
                                          color: Colors.blue, size: 17),
                                    ],
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 15),
                                    const SizedBox(width: 3),
                                    Text(
                                      _sellerRatingCount > 0
                                          ? '${_sellerRatingAvg.toStringAsFixed(1)} ($_sellerRatingCount تقييم)'
                                          : 'لا توجد تقييمات بعد',
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.navy),
                                    ),
                                  ],
                                ),
                                Text(
                                  'الهاتف: ${_seller?.phone ?? "غير متوفر"}',
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_seller != null)
                                  Text(
                                    formatWorkshopStreet(_seller!),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_seller != null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              animatedRoute(
                                MerchantPublicProfileScreen(
                                  seller: _seller!,
                                  viewerProfile: widget.viewerProfile,
                                ),
                              ),
                            ),
                            icon:
                                const Icon(Icons.store_mall_directory_outlined),
                            label: const Text(
                                'عرض بروفايل التاجر وتقييمه وجميع منشوراته'),
                          ),
                        ),
                        if (!isOwnProduct && widget.viewerProfile != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.orange),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                animatedRoute(
                                  ChatConversationScreen(
                                    otherUserId: _seller!.id,
                                    otherUserName:
                                        _seller!.fullName ?? 'التاجر',
                                    otherUserPhone: _seller!.phone,
                                    productId: p['id'] as String?,
                                    productTitle: p['title'] as String?,
                                    productPrice: displayPrice,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.chat,
                                  color: AppColors.orange),
                              label: const Text(
                                'فتح الدردشة المباشرة',
                                style: TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (!isOwnProduct && widget.viewerProfile != null) ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _msgCtrl,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) {
                                  if (!_sending) _sendMessage();
                                },
                                decoration: InputDecoration(
                                  hintText: 'أو أرسل رسالة سريعة للتاجر...',
                                  filled: true,
                                  fillColor: AppColors.background,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                              ),
                              onPressed: _sending ? null : _sendMessage,
                              child: const Text('إرسال'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class MerchantPublicProfileScreen extends StatefulWidget {
  final CustomerProfile seller;
  final CustomerProfile? viewerProfile;
  const MerchantPublicProfileScreen(
      {super.key, required this.seller, this.viewerProfile});

  @override
  State<MerchantPublicProfileScreen> createState() =>
      _MerchantPublicProfileScreenState();
}

class _MerchantPublicProfileScreenState
    extends State<MerchantPublicProfileScreen> {
  final _db = Supabase.instance.client;
  final _commentCtrl = TextEditingController();
  double _ratingAvg = 0;
  int _ratingCount = 0;
  int _selectedStars = 5;
  bool _submittingRating = false;
  List<Map<String, dynamic>> _reviews = [];

  String? get _currentUid =>
      widget.viewerProfile?.id ?? _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRatings() async {
    try {
      final meta = await _db
          .from('customers')
          .select('rating_avg, rating_count')
          .eq('id', widget.seller.id)
          .maybeSingle();
      final list = await _db
          .from('merchant_ratings')
          .select()
          .eq('merchant_id', widget.seller.id)
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      setState(() {
        _ratingAvg = ((meta?['rating_avg'] as num?) ?? 0).toDouble();
        _ratingCount = (meta?['rating_count'] as int?) ?? 0;
        _reviews = List<Map<String, dynamic>>.from(list);
      });
    } catch (_) {}
  }

  Future<void> _submitRating() async {
    FocusScope.of(context).unfocus();
    final uid = _currentUid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل الدخول لتقييم التاجر')),
      );
      return;
    }
    if (uid == widget.seller.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكنك تقييم حسابك الشخصي')),
      );
      return;
    }
    setState(() => _submittingRating = true);
    try {
      await _db.from('merchant_ratings').upsert(
        {
          'merchant_id': widget.seller.id,
          'reviewer_id': uid,
          'rating': _selectedStars,
          'comment': _commentCtrl.text.trim(),
        },
        onConflict: 'merchant_id,reviewer_id',
      );
      _commentCtrl.clear();
      await _loadRatings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ تقييمك للتاجر بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر إرسال التقييم: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seller = widget.seller;
    final isSelf = _currentUid == seller.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(seller.fullName ?? 'بروفايل التاجر'),
        actions: [
          if (!isSelf)
            IconButton(
              tooltip: 'إبلاغ عن هذا الحساب',
              icon: const Icon(Icons.flag_outlined, color: Colors.redAccent),
              onPressed: () => showContentReportDialog(
                context,
                targetType: 'user',
                targetId: seller.id,
                targetLabel: 'هذا الحساب',
              ),
            ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.orange,
                      child:
                          Icon(Icons.storefront, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                seller.fullName ?? 'التاجر',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (seller.isTrustedMerchant) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified,
                                    color: Colors.lightBlueAccent, size: 18),
                              ],
                            ],
                          ),
                          Text('@${seller.username ?? ""}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                _ratingCount > 0
                                    ? '${_ratingAvg.toStringAsFixed(1)} من 5 ($_ratingCount تقييم)'
                                    : 'بدون تقييمات حتى الآن',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 22),
                Text(
                  'رقم الهاتف للتواصل: ${seller.phone ?? "غير متوفر"}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'العنوان: ${formatWorkshopStreet(seller)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (!isSelf && _currentUid != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        animatedRoute(
                          ChatConversationScreen(
                            otherUserId: seller.id,
                            otherUserName: seller.fullName ?? 'التاجر',
                            otherUserPhone: seller.phone,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.chat),
                      label: const Text('مراسلة التاجر الآن'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // بطاقة التقييم التفاعلية
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: isSelf
                ? const Text(
                    'هذا حسابك الشخصي — يظهر التقييم التفاعلي للزبائن الآخرين لتقييم تجربتهم معك.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'قيّم تجربتك مع هذا التاجر',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (idx) {
                          final starVal = idx + 1;
                          return IconButton(
                            onPressed: () =>
                                setState(() => _selectedStars = starVal),
                            icon: Icon(
                              starVal <= _selectedStars
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                              size: 32,
                            ),
                          );
                        }),
                      ),
                      TextField(
                        controller: _commentCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_submittingRating) _submitRating();
                        },
                        decoration: InputDecoration(
                          hintText: 'اكتب تعليقك (اختياري)...',
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _submittingRating ? null : _submitRating,
                          child: Text(_submittingRating
                              ? 'جاري الحفظ...'
                              : 'إرسال التقييم'),
                        ),
                      ),
                    ],
                  ),
          ),

          if (_reviews.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('آراء الزبائن',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._reviews.take(5).map(
                  (rev) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.orangeLight,
                        child: Text(
                          '${rev['rating']}★',
                          style: const TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        (rev['comment'] as String?)?.isNotEmpty == true
                            ? rev['comment'] as String
                            : 'تقييم ${rev['rating']} نجوم',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
          ],

          const SizedBox(height: 18),
          const Text('جميع منشورات التاجر',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db
                .from('products')
                .stream(primaryKey: ['id'])
                .eq('user_id', seller.id)
                .order('created_at', ascending: false)
                .limit(60),
            builder: (_, snap) {
              if (!snap.hasData) return const ShimmerProductsLoading();
              final items = snap.data!
                  .where((p) => p['is_hidden'] != true && p['is_sold'] != true)
                  .toList();
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('لا توجد منشورات أخرى حالياً')),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 230,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.74,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i];
                  final imgs = List<String>.from(p['images'] ?? []);
                  final tag = 'seller_${p['id']}';
                  final disc = (p['discount_percent'] as int?) ?? 0;
                  return BounceTap(
                    onTap: () => Navigator.push(
                      context,
                      animatedRoute(
                        ProductDetailsScreen(
                          product: p,
                          viewerProfile: widget.viewerProfile,
                          heroTag: tag,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Hero(
                                tag: tag,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    height: 95,
                                    width: double.infinity,
                                    child: imgs.isNotEmpty
                                        ? Image.network(imgs.first,
                                            fit: BoxFit.cover, cacheWidth: 400)
                                        : Container(
                                            color: AppColors.placeholder,
                                            child: const Icon(
                                                Icons.settings_outlined,
                                                color: AppColors.textSecondary),
                                          ),
                                  ),
                                ),
                              ),
                              if (disc > 0)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade700,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '-$disc%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (p['title'] as String?) ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            '${p['car_name']} · ${p['car_model']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11),
                          ),
                          const Spacer(),
                          Text(
                            '${p['price']} د.أ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
