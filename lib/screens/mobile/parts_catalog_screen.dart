import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
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
  String _search = '';
  String _selectedCat = 'الكل';

  Map<String,
          ({bool trusted, double ratingAvg, int ratingCount, int boostTier})>
      _sellerMeta = {};

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
      final map = <String,
          ({bool trusted, double ratingAvg, int ratingCount, int boostTier})>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final id = r['id'] as String?;
        if (id == null) continue;
        map[id] = (
          trusted: r['is_trusted_merchant'] == true,
          ratingAvg: (r['rating_avg'] as num?)?.toDouble() ?? 0.0,
          ratingCount: (r['rating_count'] as num?)?.toInt() ?? 0,
          boostTier: computeSeoBoostTier(
            r['subscription_plan'] as String?,
            r['subscription_expires_at'],
          ),
        );
      }
      if (mounted) setState(() => _sellerMeta = map);
    } catch (_) {}
  }

  List<String> get _cats => ['الكل', ...CarPartsCatalogAZ.mainCategories];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قطع الغيار')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db
            .from('products')
            .stream(primaryKey: ['id'])
            .eq('is_hidden', false)
            .order('created_at', ascending: false),
        builder: (context, snap) {
          final parts = (snap.data ?? []).where((p) {
            if (p['is_sold'] == true) return false;
            final catOk = _selectedCat == 'الكل' ||
                (p['main_category'] ?? '').toString().contains(_selectedCat) ||
                (p['sub_category'] ?? '').toString().contains(_selectedCat);
            final q = _search.trim().toLowerCase();
            final searchOk = q.isEmpty ||
                (p['title'] ?? '').toString().toLowerCase().contains(q) ||
                (p['car_name'] ?? '').toString().toLowerCase().contains(q) ||
                (p['chassis_number'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(q);
            return catOk && searchOk;
          }).toList();

          parts.sort((a, b) {
            final ma = _sellerMeta[a['user_id']];
            final mb = _sellerMeta[b['user_id']];
            final boostCmp = (mb?.boostTier ?? 0).compareTo(ma?.boostTier ?? 0);
            if (boostCmp != 0) return boostCmp;
            if (_search.trim().isNotEmpty) {
              final ratingCmp =
                  (mb?.ratingAvg ?? 0).compareTo(ma?.ratingAvg ?? 0);
              if (ratingCmp != 0) return ratingCmp;
            }
            final ta = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
                DateTime(2000);
            final tb = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
                DateTime(2000);
            return tb.compareTo(ta);
          });

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم القطعة أو رقمها',
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
                      onTap: () => setState(() => _selectedCat = cat),
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
              if (parts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('لا توجد قطع غيار مطابقة')),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: parts.length,
                  itemBuilder: (_, i) {
                    final p = parts[i];
                    final imgs = List<String>.from(p['images'] ?? []);
                    final qty = (p['quantity'] as num?)?.toInt() ?? 1;
                    final discountPct =
                        (p['discount_percent'] as num?)?.toInt() ?? 0;
                    final origPrice = (p['original_price'] as num?)?.toDouble();
                    final meta = _sellerMeta[p['user_id']];
                    final isTrusted = meta?.trusted ?? false;
                    final boostTier = meta?.boostTier ?? 0;
                    final ratingAvg = meta?.ratingAvg ?? 0.0;
                    final ratingCount = meta?.ratingCount ?? 0;

                    return FadeSlideIn(
                      index: i,
                      child: BounceTap(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            animatedRoute(ProductDetailsScreen(
                              product: p,
                              viewerProfile: widget.viewerProfile,
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
                              color: boostTier > 0
                                  ? AppColors.orange.withValues(alpha: 0.65)
                                  : AppColors.border,
                              width: boostTier > 0 ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  Container(
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
                                            color: AppColors.textSecondary,
                                            size: 32)
                                        : null,
                                  ),
                                  if (boostTier > 0)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD97706),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'مميز',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (isTrusted)
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade700,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.verified,
                                                color: Colors.white, size: 11),
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                '${p['car_name']} · ${p['car_model']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (ratingCount > 0) ...[
                                    const Icon(Icons.star_rounded,
                                        color: Colors.amber, size: 14),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${ratingAvg.toStringAsFixed(1)} ($ratingCount)',
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                              color: discountPct > 0
                                                  ? Colors.red.shade700
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (discountPct > 0 &&
                                            origPrice != null) ...[
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '$origPrice',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                color: AppColors.textSecondary,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 5),
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
                      ),
                    );
                  },
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
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('احجز موعد تركيب القطعة في أقرب ورشة',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
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
                        child: const Text('اختيار ورشة وموعد',
                            style: TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
