import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../../widgets/home_ad_banner.dart';
import 'book_workshop_screen.dart';
import '../mobile/chat_screen.dart';
import 'parts_catalog_screen.dart';

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
                          style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold)),
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
                    if (val == null) {
                      return;
                    }
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

  void _openProductDetailsPage(Map<String, dynamic> p) {
    Navigator.push(
      context,
      animatedRoute(ProductDetailsScreen(
        product: p,
        viewerProfile: widget.profile,
      )),
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
          final all = (snap.data ?? []).where((p) {
            if (p['is_sold'] == true) {
              return false;
            }
            final catOk = _selectedCat == 'الكل' ||
                (p['main_category'] ?? '').toString().contains(_selectedCat) ||
                (p['sub_category'] ?? '').toString().contains(_selectedCat);

            bool carOk = true;
            if (_filterByCar) {
              final cleanBrand = _selectedBrand.split(' ').first.toLowerCase();
              final model = _selectedModel.toLowerCase();
              final pCar = (p['car_name'] ?? '').toString().toLowerCase();
              final pYear = (p['car_model'] ?? '').toString();
              final matchesName = pCar.contains(cleanBrand) && pCar.contains(model);
              final matchesYear = _selectedYear == 'جميع الموديلات' ||
                  pYear == 'جميع الموديلات' ||
                  pYear.contains(_selectedYear);
              carOk = matchesName && matchesYear;
            }

            final q = _search.trim().toLowerCase();
            final searchOk = q.isEmpty ||
                (p['title'] ?? '').toString().toLowerCase().contains(q) ||
                (p['car_name'] ?? '').toString().toLowerCase().contains(q) ||
                (p['sub_category'] ?? '').toString().toLowerCase().contains(q) ||
                (p['chassis_number'] ?? '').toString().toLowerCase().contains(q);

            return catOk && carOk && searchOk;
          }).toList();

          final bestSellers = List<Map<String, dynamic>>.from(all)
            ..sort((a, b) {
              final scoreA = ((a['sales_count'] ?? 0) * 10) + (a['clicks_count'] ?? 0);
              final scoreB = ((b['sales_count'] ?? 0) * 10) + (b['clicks_count'] ?? 0);
              return scoreB.compareTo(scoreA);
            });

          final newArrivals = all;

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
                          const SizedBox(width: 6),
                          const Text(
                            'أوتو بارتس برو',
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                          ),
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
                            child: const Icon(
                              Icons.chat_bubble_outline,
                              size: 20,
                              color: AppColors.navy,
                            ),
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
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم القطعة أو رقمها أو السيارة',
                          hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الأكثر مبيعاً',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
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
                  height: 230,
                  child: bestSellers.isEmpty
                      ? const Center(child: Text('لا توجد قطع حالياً لهذه السيارة'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: bestSellers.take(8).length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => SizedBox(
                            width: 164,
                            child: FadeSlideIn(
                              index: i,
                              child: _card(bestSellers[i], 'الأكثر مبيعاً'),
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
                      const Text(
                        'وصل حديثاً',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.74,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => FadeSlideIn(index: i, child: _card(newArrivals[i], 'جديد')),
                    childCount: newArrivals.length,
                  ),
                ),
              ),
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
                        const Text(
                          'تركيب في ورشة؟',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'احجز موعد تركيب القطعة في أقرب ورشة معتمدة',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _openWorkshopSelector,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.navy, width: 1.4),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'اختيار ورشة وموعد',
                              style: TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _card(Map<String, dynamic> p, String badge) {
    final imgs = List<String>.from(p['images'] ?? []);
    return BounceTap(
      onTap: () => _openProductDetailsPage(p),
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
                Container(
                  height: 95,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.placeholder,
                    borderRadius: BorderRadius.circular(12),
                    image: imgs.isNotEmpty
                        ? DecorationImage(image: NetworkImage(imgs.first), fit: BoxFit.cover)
                        : null,
                  ),
                  child: imgs.isEmpty
                      ? const Icon(
                          Icons.settings_outlined,
                          color: AppColors.textSecondary,
                          size: 32,
                        )
                      : null,
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
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
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${p['price']} د.أ',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'التفاصيل',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
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

  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.viewerProfile,
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

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || widget.viewerProfile == null) {
      return;
    }
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
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final imgs = List<String>.from(p['images'] ?? []);

    return Scaffold(
      appBar: AppBar(title: Text(p['title'] ?? 'تفاصيل القطعة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (imgs.isNotEmpty)
            SizedBox(
              height: 220,
              child: PageView.builder(
                itemCount: imgs.length,
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(imgs[i], fit: BoxFit.cover),
                ),
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.placeholder,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.settings_outlined, size: 54, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  p['title'] ?? '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${p['price']} د.أ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p['main_category'] ?? ''} · ${p['sub_category'] ?? ''}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'السيارة: ${p['car_name']} · الموديل: ${p['car_model']}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if ((p['chassis_number'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'رقم الشاصي: ${p['chassis_number']}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
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
                const Text(
                  'تركيب في ورشة؟',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'احجز موعد تركيب هذه القطعة في ورشة معتمدة',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        animatedRoute(SelectWorkshopScreen(viewerProfile: widget.viewerProfile)),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.navy, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'اختيار ورشة وموعد',
                      style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold),
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
                      const Text(
                        'معلومات البائع والتاجر',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
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
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (_seller?.isTrustedMerchant == true) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified, color: Colors.blue, size: 17),
                                    ],
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
                            onPressed: () {
                              Navigator.push(
                                context,
                                animatedRoute(MerchantPublicProfileScreen(
                                  seller: _seller!,
                                  viewerProfile: widget.viewerProfile,
                                )),
                              );
                            },
                            icon: const Icon(Icons.store_mall_directory_outlined),
                            label: const Text('عرض بروفايل التاجر وجميع منشوراته'),
                          ),
                        ),
                        if (widget.viewerProfile != null &&
                            widget.viewerProfile!.id != p['user_id']) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.orange),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  animatedRoute(ChatConversationScreen(
                                    otherUserId: _seller!.id,
                                    otherUserName: _seller!.fullName ?? 'التاجر',
                                    otherUserPhone: _seller!.phone,
                                    productId: p['id'] as String?,
                                    productTitle: p['title'] as String?,
                                    productPrice: (p['price'] as num?)?.toDouble(),
                                  )),
                                );
                              },
                              icon: const Icon(Icons.chat, color: AppColors.orange),
                              label: const Text(
                                'فتح الدردشة المباشرة',
                                style: TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (widget.viewerProfile != null &&
                          widget.viewerProfile!.id != p['user_id']) ...[
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
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

class MerchantPublicProfileScreen extends StatelessWidget {
  final CustomerProfile seller;
  final CustomerProfile? viewerProfile;

  const MerchantPublicProfileScreen({
    super.key,
    required this.seller,
    this.viewerProfile,
  });

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;

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
                                const Icon(Icons.verified, color: Colors.lightBlueAccent, size: 18),
                              ],
                            ],
                          ),
                          Text(
                            '@${seller.username ?? ""}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 22),
                Text(
                  'رقم الهاتف للتواصل: ${seller.phone ?? "غير متوفر"}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'العنوان: ${formatWorkshopStreet(seller)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (viewerProfile != null && viewerProfile!.id != seller.id) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          animatedRoute(ChatConversationScreen(
                            otherUserId: seller.id,
                            otherUserName: seller.fullName ?? 'التاجر',
                            otherUserPhone: seller.phone,
                          )),
                        );
                      },
                      icon: const Icon(Icons.chat),
                      label: const Text('مراسلة التاجر الآن'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'جميع منشورات التاجر',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: db
                .from('products')
                .stream(primaryKey: ['id'])
                .eq('user_id', seller.id)
                .order('created_at', ascending: false),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
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
                  childAspectRatio: 0.76,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i];
                  final imgs = List<String>.from(p['images'] ?? []);
                  return BounceTap(
                    onTap: () => Navigator.push(
                      context,
                      animatedRoute(ProductDetailsScreen(
                        product: p,
                        viewerProfile: viewerProfile,
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
                          Container(
                            height: 95,
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
                                ? const Icon(
                                    Icons.settings_outlined,
                                    color: AppColors.textSecondary,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
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