import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'book_workshop_screen.dart';
import 'live_store_home_screen.dart';

class PartsCatalogScreen extends StatefulWidget {
  final String selectedCarName;
  final CustomerProfile? viewerProfile;

  const PartsCatalogScreen({
    super.key,
    required this.selectedCarName,
    this.viewerProfile,
  });

  @override
  State<PartsCatalogScreen> createState() => _PartsCatalogScreenState();
}

class _PartsCatalogScreenState extends State<PartsCatalogScreen> {
  final _db = Supabase.instance.client;
  final _loc = AppLocaleService.instance;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _selectedCat = 'الكل';

  static const int _pageSize = 20;
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _activeDiscounts = [];
  final Map<String, Map<String, dynamic>> _sellerMeta = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  List<String> get _cats => ['الكل', ...CarPartsCatalogAZ.mainCategories];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isPaidTrustedSeller(Map<String, dynamic>? seller) {
    if (seller == null) return false;
    final plan = (seller['subscription_plan'] as String? ?? 'free').trim();
    if (plan.isEmpty || plan == 'free') return false;
    final expStr = seller['subscription_expires_at'] as String?;
    if (expStr != null && expStr.isNotEmpty) {
      final exp = DateTime.tryParse(expStr);
      if (exp != null && exp.isBefore(DateTime.now())) return false;
    }
    return true;
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _hasMore = true;
    });
    await Future.wait([_fetchDiscounts(), _fetchPage(reset: true)]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchDiscounts() async {
    try {
      final rows = await _db
          .from('discounts')
          .select()
          .eq('is_active', true)
          .order('discount_percent', ascending: false)
          .limit(40);
      final now = DateTime.now();
      _activeDiscounts = List<Map<String, dynamic>>.from(rows).where((d) {
        final exp = DateTime.tryParse((d['expires_at'] as String?) ?? '');
        return exp == null || exp.isAfter(now);
      }).toList();
    } catch (_) {}
  }

  Future<void> _fetchPage({required bool reset}) async {
    if (_loadingMore && !reset) return;
    if (!reset) setState(() => _loadingMore = true);
    try {
      final offset = reset ? 0 : _parts.length;
      var query = _db
          .from('products')
          .select()
          .eq('is_hidden', false)
          .eq('is_sold', false);

      if (_selectedCat != 'الكل') {
        query = query.or(
          'main_category.ilike.%$_selectedCat%,sub_category.ilike.%$_selectedCat%',
        );
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

      final missingIds = list
          .map((p) => p['user_id'] as String?)
          .where((id) => id != null && !_sellerMeta.containsKey(id))
          .cast<String>()
          .toSet()
          .toList();
      if (missingIds.isNotEmpty) {
        final sellers = await _db
            .from('customers')
            .select(
                'id, rating_avg, rating_count, is_trusted_merchant, subscription_plan, subscription_expires_at')
            .inFilter('id', missingIds);
        for (final s in sellers) {
          _sellerMeta[s['id'] as String] = Map<String, dynamic>.from(s);
        }
      }

      if (!mounted) return;
      setState(() {
        if (reset) {
          _parts = list;
        } else {
          _parts.addAll(list);
        }
        _hasMore = list.length >= _pageSize;
        _parts.sort((a, b) {
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
          return boostB.compareTo(boostA);
        });
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _loc.langCode,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              '${_loc.tr("قطع الغيار", "Spare Parts")} · ${widget.selectedCarName}',
            ),
          ),
          body: RefreshIndicator(
            color: AppColors.orange,
            onRefresh: _loadAll,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) {
                    FocusScope.of(context).unfocus();
                    _search = v;
                    _loadAll();
                  },
                  onChanged: (v) {
                    _search = v;
                    if (v.isEmpty) _loadAll();
                  },
                  decoration: InputDecoration(
                    hintText: _loc.tr(
                      'ابحث باسم القطعة أو رقم الشاصي',
                      'Search by part name or VIN',
                    ),
                    hintStyle: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: AppColors.navy),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
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
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _cats.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final cat = _cats[i];
                      final active = _selectedCat == cat;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCat = cat);
                          _loadAll();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? AppColors.navy : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active ? AppColors.navy : AppColors.border,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              color:
                                  active ? Colors.white : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const ShimmerProductsLoading()
                else if (_parts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        _loc.tr('لا توجد قطع غيار مطابقة', 'No matching parts'),
                      ),
                    ),
                  )
                else ...[
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.64,
                    ),
                    itemCount: _parts.length,
                    itemBuilder: (_, i) {
                      final p = _parts[i];
                      final imgs = List<String>.from(p['images'] ?? []);
                      final seller = _sellerMeta[p['user_id']];
                      final ratingAvg =
                          ((seller?['rating_avg'] as num?) ?? 0).toDouble();
                      final ratingCount = (seller?['rating_count'] as int?) ?? 0;
                      final isTrusted = _isPaidTrustedSeller(seller);
                      final disc = computeEffectiveProductDiscount(
                        product: p,
                        activeDiscounts: _activeDiscounts,
                        viewerRole: widget.viewerProfile?.role ?? 'user',
                        viewerId: widget.viewerProfile?.id ??
                            _db.auth.currentUser?.id,
                      );

                      return FadeSlideIn(
                        index: i,
                        child: BounceTap(
                          onTap: () => Navigator.push(
                            context,
                            animatedRoute(
                              ProductDetailsScreen(
                                product: p,
                                viewerProfile: widget.viewerProfile,
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
                                color: isTrusted
                                    ? const Color(0xFF0284C7)
                                        .withValues(alpha: 0.45)
                                    : AppColors.border,
                                width: isTrusted ? 1.3 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        height: 94,
                                        width: double.infinity,
                                        child: imgs.isNotEmpty
                                            ? Image.network(
                                                imgs.first,
                                                fit: BoxFit.cover,
                                                cacheWidth: 400,
                                              )
                                            : Container(
                                                color: AppColors.placeholder,
                                                child: const Icon(
                                                  Icons.settings_outlined,
                                                  color:
                                                      AppColors.textSecondary,
                                                  size: 32,
                                                ),
                                              ),
                                      ),
                                    ),
                                    if (disc.percent > 0)
                                      Positioned(
                                        top: 6,
                                        left: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade700,
                                            borderRadius:
                                                BorderRadius.circular(10),
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
                                const SizedBox(height: 7),
                                if (isTrusted) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF0284C7)
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.verified,
                                            color: Color(0xFF0284C7), size: 12),
                                        const SizedBox(width: 3),
                                        Text(
                                          _loc.tr(
                                              'تاجر موثوق', 'Trusted Merchant'),
                                          style: const TextStyle(
                                            color: Color(0xFF0369A1),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Text(
                                  (p['title'] as String?) ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                Text(
                                  '${p['car_name']} · ${p['car_model']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11),
                                ),
                                if (ratingCount > 0) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 13),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${ratingAvg.toStringAsFixed(1)} ($ratingCount)',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ],
                                const Spacer(),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (disc.percent > 0)
                                          Text(
                                            '${disc.originalPrice.toStringAsFixed(1)} ${_loc.tr("د.أ", "JOD")}',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppColors.textSecondary,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                        Text(
                                          '${disc.finalPrice.toStringAsFixed(disc.percent > 0 ? 2 : 1)} ${_loc.tr("د.أ", "JOD")}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: disc.percent > 0
                                                ? Colors.red.shade700
                                                : AppColors.navy,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.navy,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _loc.tr('التفاصيل', 'Details'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_hasMore) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed:
                          _loadingMore ? null : () => _fetchPage(reset: false),
                      child: _loadingMore
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_loc.tr('عرض المزيد', 'Load More')),
                    ),
                  ],
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
                      Text(
                        _loc.tr('تركيب في ورشة؟', 'Need workshop installation?'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loc.tr(
                          'احجز موعد تركيب القطعة في أقرب ورشة',
                          'Book an appointment at the nearest workshop',
                        ),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              animatedRoute(
                                SelectWorkshopScreen(
                                    viewerProfile: widget.viewerProfile),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.navy, width: 1.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _loc.tr('اختيار ورشة وموعد',
                                'Choose Workshop & Time'),
                            style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}