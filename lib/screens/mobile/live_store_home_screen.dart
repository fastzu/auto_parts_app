import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/home_ad_banner.dart';
import '../../widgets/home_live_progress_banner.dart';
import 'book_workshop_screen.dart';
import 'chat_screen.dart';
import 'parts_catalog_screen.dart';

class _SellerMeta {
  final bool isTrusted;
  final double ratingAvg;
  final int ratingCount;
  final int seoBoostTier;

  const _SellerMeta({
    this.isTrusted = false,
    this.ratingAvg = 0.0,
    this.ratingCount = 0,
    this.seoBoostTier = 0,
  });
}

int computeSeoBoostTier(String? plan, dynamic expiresRaw) {
  if (expiresRaw != null) {
    final exp = DateTime.tryParse(expiresRaw.toString());
    if (exp != null && exp.isBefore(DateTime.now())) {
      return 0;
    }
  }
  return switch (plan) {
    'provider_12m' => 3,
    'provider_6m' => 2,
    'provider_3m' => 1,
    _ => 0,
  };
}

Future<void> _dialPhone(String? phone) async {
  final clean = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.isEmpty) return;
  final uri = Uri(scheme: 'tel', path: clean);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

Future<void> _showRateMerchantSheet({
  required BuildContext context,
  required String merchantId,
  required String merchantName,
  required String reviewerId,
  int initialStars = 5,
  String initialComment = '',
  bool isEditing = false,
  required Future<void> Function() onSaved,
}) async {
  final db = Supabase.instance.client;
  int selectedStars = initialStars.clamp(1, 5);
  final commentCtrl = TextEditingController(text: initialComment);
  bool saving = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'تعديل تقييمك للتاجر' : 'قيّم التاجر',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              merchantName,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final star = index + 1;
                return IconButton(
                  onPressed: () => setModal(() => selectedStars = star),
                  icon: Icon(
                    star <= selectedStars
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 40,
                  ),
                );
              }),
            ),
            Center(
              child: Text(
                '$selectedStars / 5',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'اكتب تجربتك مع التاجر (اختياري)...',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: saving
                    ? null
                    : () async {
                        setModal(() => saving = true);
                        try {
                          await db.from('merchant_ratings').upsert(
                            {
                              'merchant_id': merchantId,
                              'reviewer_id': reviewerId,
                              'rating': selectedStars,
                              'comment': commentCtrl.text.trim(),
                              'updated_at': DateTime.now().toIso8601String(),
                            },
                            onConflict: 'merchant_id,reviewer_id',
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await onSaved();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم حفظ تقييمك بنجاح!'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          setModal(() => saving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تعذر حفظ التقييم: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'حفظ التقييم',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  commentCtrl.dispose();
}

class LiveStoreHomeScreen extends StatefulWidget {
  final CustomerProfile? profile;
  final VoidCallback onOpenDrawer;

  const LiveStoreHomeScreen({
    super.key,
    required this.profile,
    required this.onOpenDrawer,
  });

  @override
  State<LiveStoreHomeScreen> createState() => _LiveStoreHomeScreenState();
}

class _LiveStoreHomeScreenState extends State<LiveStoreHomeScreen> {
  final _db = Supabase.instance.client;
  String _search = '';
  String _selectedCat = 'الكل';

  String _selectedBrand = JordanCarsCatalog.brands.first;
  String _selectedModel =
      JordanCarsCatalog.brandsAndModels[JordanCarsCatalog.brands.first]!.first;
  String _selectedYear = 'جميع الموديلات';
  bool _filterByCar = false;

  Map<String, _SellerMeta> _sellerMeta = {};

  @override
  void initState() {
    super.initState();
    _loadSellerMeta();
  }

  Future<void> _loadSellerMeta() async {
    try {
      final rows = await _db.from('customers').select(
            'id, is_trusted_merchant, subscription_plan, subscription_expires_at, rating_avg, rating_count',
          );
      final map = <String, _SellerMeta>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final id = r['id'] as String?;
        if (id == null) continue;
        map[id] = _SellerMeta(
          isTrusted: r['is_trusted_merchant'] == true,
          ratingAvg: (r['rating_avg'] as num?)?.toDouble() ?? 0.0,
          ratingCount: (r['rating_count'] as num?)?.toInt() ?? 0,
          seoBoostTier: computeSeoBoostTier(
            r['subscription_plan'] as String?,
            r['subscription_expires_at'],
          ),
        );
      }
      if (mounted) {
        setState(() => _sellerMeta = map);
      }
    } catch (_) {}
  }

  List<String> get _cats => ['الكل', ...CarPartsCatalogAZ.mainCategories];

  String get _selectedCarLabel {
    if (!_filterByCar) {
      return 'جميع السيارات';
    }
    final cleanBrand = _selectedBrand.split(' ').first;
    if (_selectedYear == 'جميع الموديلات') {
      return '$cleanBrand $_selectedModel';
    }
    return '$cleanBrand $_selectedModel $_selectedYear';
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
    Navigator.push(
      context,
      animatedRoute(SelectWorkshopScreen(viewerProfile: widget.profile)),
    );
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
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setState(() => _filterByCar = false);
                        Navigator.pop(ctx);
                      },
                      child: const Text('عرض جميع السيارات',
                          style: TextStyle(
                              color: AppColors.orange, fontWeight: FontWeight.bold)),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: JordanCarsCatalog.brands
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setModal(() {
                      tempBrand = val;
                      tempModel = JordanCarsCatalog.brandsAndModels[tempBrand]!.first;
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModal(() => tempModel = val);
                    }
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: JordanCarsCatalog.years
                      .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModal(() => tempYear = val);
                    }
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedBrand = tempBrand;
                        _selectedModel = tempModel;
                        _selectedYear = tempYear;
                        _filterByCar = true;
                      });
                      Navigator.pop(ctx);
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

  Widget _discountsStrip() {
    final role = widget.profile?.role ?? 'user';
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('discounts')
          .stream(primaryKey: ['id'])
          .eq('is_active', true)
          .order('created_at', ascending: false),
      builder: (_, snap) {
        final list = (snap.data ?? []).where((d) {
          final target = (d['target_role'] as String?) ?? 'all';
          final expRaw = d['expires_at'];
          if (expRaw != null) {
            final exp = DateTime.tryParse(expRaw.toString());
            if (exp != null && exp.isBefore(DateTime.now())) return false;
          }
          return target == 'all' || target == role;
        }).toList();

        if (list.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final d = list[i];
                final code = (d['code'] as String?) ?? '';
                final pct = (d['discount_percent'] as num?)?.toInt() ?? 0;
                return GestureDetector(
                  onTap: () {
                    if (code.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم نسخ كود الخصم: $code'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: 225,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.navy, Color(0xFF1E3A5F)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$pct%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                (d['title'] as String?) ?? 'عرض خاص',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                code.isNotEmpty
                                    ? 'الكود: $code (اضغط للنسخ)'
                                    : (d['target_category'] as String?) ?? 'جميع الفئات',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
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
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db
            .from('products')
            .stream(primaryKey: ['id'])
            .eq('is_hidden', false)
            .order('created_at', ascending: false),
        builder: (context, snap) {
          final isLoading =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          final all = (snap.data ?? []).where((p) {
            if (p['is_sold'] == true) return false;
            final catOk = _selectedCat == 'الكل' ||
                (p['main_category'] ?? '').toString().contains(_selectedCat) ||
                (p['sub_category'] ?? '').toString().contains(_selectedCat);
            bool carOk = true;
            if (_filterByCar) {
              final cleanBrand = _selectedBrand.split(' ').first.toLowerCase();
              final model = _selectedModel.toLowerCase();
              final pCar = (p['car_name'] ?? '').toString().toLowerCase();
              final pYear = (p['car_model'] ?? '').toString();
              carOk = pCar.contains(cleanBrand) &&
                  pCar.contains(model) &&
                  (_selectedYear == 'جميع الموديلات' ||
                      pYear == 'جميع الموديلات' ||
                      pYear.contains(_selectedYear));
            }
            final q = _search.trim().toLowerCase();
            final searchOk = q.isEmpty ||
                (p['title'] ?? '').toString().toLowerCase().contains(q) ||
                (p['car_name'] ?? '').toString().toLowerCase().contains(q) ||
                (p['sub_category'] ?? '').toString().toLowerCase().contains(q) ||
                (p['chassis_number'] ?? '').toString().toLowerCase().contains(q);
            return catOk && carOk && searchOk;
          }).toList();

          all.sort((a, b) {
            final ma = _sellerMeta[a['user_id']] ?? const _SellerMeta();
            final mb = _sellerMeta[b['user_id']] ?? const _SellerMeta();
            final boostCmp = mb.seoBoostTier.compareTo(ma.seoBoostTier);
            if (boostCmp != 0) return boostCmp;
            if (_search.trim().isNotEmpty) {
              final ratingCmp = mb.ratingAvg.compareTo(ma.ratingAvg);
              if (ratingCmp != 0) return ratingCmp;
            }
            final ta =
                DateTime.tryParse((a['created_at'] ?? '').toString()) ?? DateTime(2000);
            final tb =
                DateTime.tryParse((b['created_at'] ?? '').toString()) ?? DateTime(2000);
            return tb.compareTo(ta);
          });

          final bestSellers = List<Map<String, dynamic>>.from(all)
            ..sort((a, b) {
              final ma = _sellerMeta[a['user_id']] ?? const _SellerMeta();
              final mb = _sellerMeta[b['user_id']] ?? const _SellerMeta();
              final scoreA = (((a['sales_count'] ?? 0) as num) * 10) +
                  ((a['clicks_count'] ?? 0) as num) +
                  (ma.seoBoostTier * 25) +
                  (ma.ratingAvg * 4);
              final scoreB = (((b['sales_count'] ?? 0) as num) * 10) +
                  ((b['clicks_count'] ?? 0) as num) +
                  (mb.seoBoostTier * 25) +
                  (mb.ratingAvg * 4);
              return scoreB.compareTo(scoreA);
            });

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      if (widget.profile != null)
                        BounceTap(
                          onTap: () => Navigator.push(
                            context,
                            animatedRoute(const ChatsListScreen()),
                          ),
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
                      _discountsStrip(),
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم القطعة أو رقمها أو السيارة',
                          hintStyle: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _filterByCar ? AppColors.orange : AppColors.border,
                          ),
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
                              onTap: () => setState(() => _selectedCat = c),
                              child: AnimatedScale(
                                scale: active ? 1.04 : 1.0,
                                duration: const Duration(milliseconds: 160),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: active ? AppColors.navy : AppColors.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: active ? AppColors.navy : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    c,
                                    style: TextStyle(
                                      color: active ? Colors.white : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
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
              if (isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: ShimmerProductsLoading(),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الأكثر مبيعاً',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: _openCatalog,
                          child: const Text('عرض الكل',
                              style: TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 256,
                    child: bestSellers.isEmpty
                        ? const Center(child: Text('لا توجد قطع حالياً لهذه السيارة'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: bestSellers.take(8).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (_, i) => SizedBox(
                              width: 172,
                              child: FadeSlideIn(
                                index: i,
                                child: _card(bestSellers[i], 'الأكثر مبيعاً', 'best'),
                              ),
                            ),
                          ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('وصل حديثاً',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: _openCatalog,
                          child: const Text('عرض الكل',
                              style: TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => FadeSlideIn(
                        index: i,
                        child: _card(all[i], 'جديد', 'new'),
                      ),
                      childCount: all.length,
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
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
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text('احجز موعد تركيب القطعة في أقرب ورشة معتمدة',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _openWorkshopSelector,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.navy, width: 1.4),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('اختيار ورشة وموعد',
                                style: TextStyle(
                                    color: AppColors.navy, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> p, String badge, String heroPrefix) {
    final imgs = List<String>.from(p['images'] ?? []);
    final heroTag = '${heroPrefix}_${p['id']}';
    final meta = _sellerMeta[p['user_id']] ?? const _SellerMeta();
    final qty = (p['quantity'] as num?)?.toInt() ?? 1;
    final discountPct = (p['discount_percent'] as num?)?.toInt() ?? 0;
    final origPrice = (p['original_price'] as num?)?.toDouble();

    return BounceTap(
      onTap: () async {
        await Navigator.push(
          context,
          animatedRoute(ProductDetailsScreen(
            product: p,
            viewerProfile: widget.profile,
            heroTag: heroTag,
          )),
        );
        _loadSellerMeta();
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: meta.seoBoostTier > 0
                ? AppColors.orange.withValues(alpha: 0.65)
                : AppColors.border,
            width: meta.seoBoostTier > 0 ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Hero(
                  tag: heroTag,
                  child: Container(
                    height: 92,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.placeholder,
                      borderRadius: BorderRadius.circular(12),
                      image: imgs.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(imgs.first),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imgs.isEmpty
                        ? const Icon(Icons.settings_outlined,
                            color: AppColors.textSecondary, size: 32)
                        : null,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: meta.seoBoostTier > 0
                          ? const Color(0xFFD97706)
                          : AppColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      meta.seoBoostTier > 0 ? 'مميز' : badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (meta.isTrusted)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 11),
                          SizedBox(width: 2),
                          Text(
                            'موثوق',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (discountPct > 0)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'خصم $discountPct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              p['title'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              '${p['car_name']} · ${p['car_model']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (meta.ratingCount > 0) ...[
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    '${meta.ratingAvg.toStringAsFixed(1)} (${meta.ratingCount})',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    'الكمية: $qty',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${p['price']} د.أ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: discountPct > 0
                                ? Colors.red.shade700
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (discountPct > 0 && origPrice != null) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$origPrice',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'التفاصيل',
                    style: TextStyle(
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
    );
  }
}

class ProductDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final CustomerProfile? viewerProfile;
  final String? heroTag;

  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.viewerProfile,
    this.heroTag,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final _db = Supabase.instance.client;
  final _msgCtrl = TextEditingController();
  CustomerProfile? _seller;
  bool _loadingSeller = true;
  bool _sending = false;

  String? get _currentUid =>
      widget.viewerProfile?.id ?? _db.auth.currentUser?.id;

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
      await _db.rpc('increment_product_click', params: {'p_id': widget.product['id']});
      await _db.rpc('increment_product_view', params: {'p_id': widget.product['id']});
      await _reloadSeller();
    } catch (_) {
      await _reloadSeller();
    }
  }

  Future<void> _reloadSeller() async {
    try {
      final sellerMap = await _db
          .from('customers')
          .select()
          .eq('id', widget.product['user_id'])
          .maybeSingle();
      if (mounted) {
        setState(() {
          _seller = sellerMap != null ? CustomerProfile.fromMap(sellerMap) : null;
          _loadingSeller = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSeller = false);
      }
    }
  }

  Future<void> _quickRateSeller() async {
    final uid = _currentUid;
    final seller = _seller;
    if (seller == null) return;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل دخولك أولاً لتقييم التاجر')),
      );
      return;
    }
    if (uid == seller.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكنك تقييم حسابك الشخصي — جرّب بحساب زبون آخر'),
        ),
      );
      return;
    }

    final existing = await _db
        .from('merchant_ratings')
        .select('rating, comment')
        .eq('merchant_id', seller.id)
        .eq('reviewer_id', uid)
        .maybeSingle();

    if (!mounted) return;
    await _showRateMerchantSheet(
      context: context,
      merchantId: seller.id,
      merchantName: seller.fullName ?? 'التاجر',
      reviewerId: uid,
      initialStars: (existing?['rating'] as num?)?.toInt() ?? 5,
      initialComment: (existing?['comment'] as String?) ?? '',
      isEditing: existing != null,
      onSaved: _reloadSeller,
    );
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    final uid = _currentUid;
    if (text.isEmpty || uid == null) return;
    setState(() => _sending = true);
    try {
      await _db.from('messages').insert({
        'sender_id': uid,
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
    final qty = (p['quantity'] as num?)?.toInt() ?? 1;
    final discountPct = (p['discount_percent'] as num?)?.toInt() ?? 0;
    final origPrice = (p['original_price'] as num?)?.toDouble();
    final uid = _currentUid;

    final imageBox = imgs.isNotEmpty
        ? SizedBox(
            height: 220,
            child: PageView.builder(
              itemCount: imgs.length,
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(imgs[i], fit: BoxFit.cover),
              ),
            ),
          )
        : Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.placeholder,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.settings_outlined,
                size: 54, color: AppColors.textSecondary),
          );

    return Scaffold(
      appBar: AppBar(title: Text(p['title'] ?? 'تفاصيل القطعة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.heroTag != null) Hero(tag: widget.heroTag!, child: imageBox) else imageBox,
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  p['title'] ?? '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (discountPct > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'خصم $discountPct%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${p['price']} د.أ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: discountPct > 0
                              ? Colors.red.shade700
                              : AppColors.orange,
                        ),
                      ),
                    ],
                  ),
                  if (discountPct > 0 && origPrice != null)
                    Text(
                      '$origPrice د.أ',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p['main_category'] ?? ''} · ${p['sub_category'] ?? ''}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          Text(
            'السيارة: ${p['car_name']} · الموديل: ${p['car_model']} · الكمية المتوفرة: $qty',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if ((p['chassis_number'] as String? ?? '').isNotEmpty)
            Text(
              'رقم الشاصي: ${p['chassis_number']}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(p['description'] ?? ''),
          ),
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('احجز موعد تركيب هذه القطعة في ورشة معتمدة',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      animatedRoute(
                          SelectWorkshopScreen(viewerProfile: widget.viewerProfile)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.navy, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('اختيار ورشة وموعد',
                        style: TextStyle(
                            color: AppColors.navy, fontWeight: FontWeight.bold)),
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                                    Flexible(
                                      child: Text(
                                        _seller?.fullName ?? 'التاجر',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                    ),
                                    if (_seller?.isTrustedMerchant == true) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified,
                                          color: Colors.blue, size: 17),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: _quickRateSeller,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          color: Colors.amber, size: 17),
                                      const SizedBox(width: 3),
                                      Text(
                                        (_seller?.ratingCount ?? 0) > 0
                                            ? '${_seller!.ratingAvg.toStringAsFixed(1)} (${_seller!.ratingCount} تقييم)'
                                            : 'لا توجد تقييمات بعد',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'قيّم',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => _dialPhone(_seller?.phone),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.call,
                                          color: AppColors.orange, size: 15),
                                      const SizedBox(width: 4),
                                      Text(
                                        _seller?.phone ?? 'غير متوفر',
                                        style: const TextStyle(
                                          color: AppColors.orange,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_seller != null)
                                  Text(
                                    formatWorkshopStreet(_seller!),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary, fontSize: 12),
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
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                animatedRoute(MerchantPublicProfileScreen(
                                  seller: _seller!,
                                  viewerProfile: widget.viewerProfile,
                                )),
                              );
                              _reloadSeller();
                            },
                            icon: const Icon(Icons.store_mall_directory_outlined),
                            label: const Text('عرض بروفايل التاجر وتقييماته'),
                          ),
                        ),
                        if (uid != null && uid != p['user_id']) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.orange),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                animatedRoute(ChatConversationScreen(
                                  otherUserId: _seller!.id,
                                  otherUserName: _seller!.fullName ?? 'التاجر',
                                  otherUserPhone: _seller!.phone,
                                  productId: p['id'] as String?,
                                  productTitle: p['title'] as String?,
                                  productPrice: (p['price'] as num?)?.toDouble(),
                                )),
                              ),
                              icon: const Icon(Icons.chat, color: AppColors.orange),
                              label: const Text('فتح الدردشة المباشرة',
                                  style: TextStyle(
                                      color: AppColors.orange,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ],
                      if (uid != null && uid != p['user_id']) ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _msgCtrl,
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

  const MerchantPublicProfileScreen({
    super.key,
    required this.seller,
    this.viewerProfile,
  });

  @override
  State<MerchantPublicProfileScreen> createState() =>
      _MerchantPublicProfileScreenState();
}

class _MerchantPublicProfileScreenState
    extends State<MerchantPublicProfileScreen> {
  final _db = Supabase.instance.client;
  late double _ratingAvg;
  late int _ratingCount;
  Map<String, String> _reviewerNames = {};
  Map<String, dynamic>? _myExistingRating;

  String? get _currentUid =>
      widget.viewerProfile?.id ?? _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _ratingAvg = widget.seller.ratingAvg;
    _ratingCount = widget.seller.ratingCount;
    _refreshRatingSummary();
  }

  Future<void> _refreshRatingSummary() async {
    try {
      final row = await _db
          .from('customers')
          .select('rating_avg, rating_count')
          .eq('id', widget.seller.id)
          .maybeSingle();

      final ratings = await _db
          .from('merchant_ratings')
          .select('reviewer_id, rating, comment')
          .eq('merchant_id', widget.seller.id);

      final rList = List<Map<String, dynamic>>.from(ratings);
      final ids = rList
          .map((e) => e['reviewer_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final users = await _db
            .from('customers')
            .select('id, full_name, username')
            .inFilter('id', ids);
        for (final u in List<Map<String, dynamic>>.from(users)) {
          names[u['id'] as String] =
              (u['full_name'] as String?)?.trim().isNotEmpty == true
                  ? u['full_name'] as String
                  : (u['username'] as String?) ?? 'زبون غيارك';
        }
      }

      Map<String, dynamic>? mine;
      final uid = _currentUid;
      if (uid != null) {
        for (final r in rList) {
          if (r['reviewer_id'] == uid) {
            mine = r;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          if (row != null) {
            _ratingAvg = (row['rating_avg'] as num?)?.toDouble() ?? 0.0;
            _ratingCount = (row['rating_count'] as num?)?.toInt() ?? 0;
          }
          _reviewerNames = names;
          _myExistingRating = mine;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleRateTap({int? presetStars}) async {
    final uid = _currentUid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل دخولك أولاً لتقييم هذا التاجر')),
      );
      return;
    }
    if (uid == widget.seller.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكنك تقييم حسابك الشخصي — جرّب بحساب زبون آخر'),
        ),
      );
      return;
    }

    await _showRateMerchantSheet(
      context: context,
      merchantId: widget.seller.id,
      merchantName: widget.seller.fullName ?? 'التاجر',
      reviewerId: uid,
      initialStars:
          presetStars ?? (_myExistingRating?['rating'] as num?)?.toInt() ?? 5,
      initialComment: (_myExistingRating?['comment'] as String?) ?? '',
      isEditing: _myExistingRating != null,
      onSaved: _refreshRatingSummary,
    );
  }

  Widget _starsRow(double value, {double size = 18}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final idx = i + 1;
        IconData icon;
        if (value >= idx) {
          icon = Icons.star_rounded;
        } else if (value >= idx - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return Icon(icon, color: Colors.amber, size: size);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seller = widget.seller;
    final uid = _currentUid;
    final isOwnProfile = uid != null && uid == seller.id;
    final myStars = (_myExistingRating?['rating'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(seller.fullName ?? 'بروفايل التاجر')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.orange,
                      child: Icon(Icons.storefront, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  seller.fullName ?? 'التاجر',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (seller.isTrustedMerchant) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified,
                                    color: Colors.lightBlueAccent, size: 18),
                              ],
                            ],
                          ),
                          Text(
                            '@${seller.username ?? ""}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _handleRateTap(),
                            child: Row(
                              children: [
                                _starsRow(_ratingAvg, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  _ratingCount > 0
                                      ? '${_ratingAvg.toStringAsFixed(1)} ($_ratingCount تقييم)'
                                      : 'بدون تقييمات بعد',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 22),
                InkWell(
                  onTap: () => _dialPhone(seller.phone),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.call, color: AppColors.orange, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'رقم الهاتف للتواصل: ${seller.phone ?? "غير متوفر"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'العنوان: ${formatWorkshopStreet(seller)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (uid != null && !isOwnProfile) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        animatedRoute(ChatConversationScreen(
                          otherUserId: seller.id,
                          otherUserName: seller.fullName ?? 'التاجر',
                          otherUserPhone: seller.phone,
                        )),
                      ),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('مراسلة التاجر الآن'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  isOwnProfile
                      ? 'تقييم حسابك'
                      : (_myExistingRating != null
                          ? 'تقييمك الحالي ($myStars / 5) — اضغط لتعديله'
                          : 'قيّم تجربتك مع هذا التاجر'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                if (isOwnProfile)
                  const Text(
                    'لا يمكنك تقييم حسابك الشخصي. يظهر هذا الكرت للزبائن لتقييمك من 1 إلى 5 نجوم.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      return IconButton(
                        onPressed: () => _handleRateTap(presetStars: star),
                        icon: Icon(
                          star <= myStars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 34,
                        ),
                      );
                    }),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.navy),
                      ),
                      onPressed: () => _handleRateTap(),
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: Text(
                        _myExistingRating != null
                            ? 'تعديل التقييم والتعليق'
                            : 'إضافة تقييم وتعليق',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('تقييمات الزبائن',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db
                .from('merchant_ratings')
                .stream(primaryKey: ['id'])
                .eq('merchant_id', seller.id)
                .order('created_at', ascending: false),
            builder: (_, snap) {
              final reviews = snap.data ?? [];
              if (reviews.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'لا توجد تقييمات لهذا التاجر بعد. كن أول من يقيّم تجربته!',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: reviews.take(5).map((r) {
                  final stars = (r['rating'] as num?)?.toDouble() ?? 0.0;
                  final comment = (r['comment'] as String?)?.trim() ?? '';
                  final reviewerName =
                      _reviewerNames[r['reviewer_id']] ?? 'زبون غيارك';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              reviewerName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            _starsRow(stars, size: 15),
                          ],
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(comment, style: const TextStyle(fontSize: 12.5)),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          const Text('جميع منشورات التاجر',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db
                .from('products')
                .stream(primaryKey: ['id'])
                .eq('user_id', seller.id)
                .order('created_at', ascending: false),
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
                  childAspectRatio: 0.72,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i];
                  final imgs = List<String>.from(p['images'] ?? []);
                  final qty = (p['quantity'] as num?)?.toInt() ?? 1;
                  final discountPct =
                      (p['discount_percent'] as num?)?.toInt() ?? 0;
                  final origPrice = (p['original_price'] as num?)?.toDouble();
                  final tag = 'seller_${p['id']}';
                  return BounceTap(
                    onTap: () => Navigator.push(
                      context,
                      animatedRoute(ProductDetailsScreen(
                        product: p,
                        viewerProfile: widget.viewerProfile,
                        heroTag: tag,
                      )),
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
                                child: Container(
                                  height: 92,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: AppColors.placeholder,
                                    borderRadius: BorderRadius.circular(12),
                                    image: imgs.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(imgs.first),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: imgs.isEmpty
                                      ? const Icon(Icons.settings_outlined,
                                          color: AppColors.textSecondary)
                                      : null,
                                ),
                              ),
                              if (discountPct > 0)
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade600,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'خصم $discountPct%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p['title'] ?? '',
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
                          Text(
                            'الكمية: $qty',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 10.5),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${p['price']} د.أ',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: discountPct > 0
                                        ? Colors.red.shade700
                                        : AppColors.orange,
                                  ),
                                ),
                              ),
                              if (discountPct > 0 && origPrice != null) ...[
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    '$origPrice',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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