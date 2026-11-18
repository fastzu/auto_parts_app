import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'book_workshop_screen.dart';

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

  List<String> get _cats => ['الكل', ...CarPartsCatalogAZ.mainCategories];

  Future<void> _pickWorkshopForInstall() async {
    final rows = await _db.from('customers').select().eq('role', 'mechanic');
    final workshops = rows.map<CustomerProfile>(CustomerProfile.fromMap).toList();
    if (!mounted) {
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر ورشة لتركيب القطعة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (workshops.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('لا توجد ورش مسجلة حالياً')),
              )
            else
              ...workshops.map((w) => ListTile(
                    leading: const Icon(Icons.build_circle, color: AppColors.orange),
                    title: Text(w.fullName ?? 'ورشة صيانة'),
                    subtitle: Text('${w.workshopAddress ?? ""} · ${w.openingHours}'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        animatedRoute(BookWorkshopScreen(workshop: w)),
                      );
                    },
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _contactSeller(Map<String, dynamic> p) async {
    await _db.rpc('increment_product_click', params: {'p_id': p['id']});
    await _db.rpc('increment_product_view', params: {'p_id': p['id']});
    final seller = await _db
        .from('customers')
        .select('full_name, phone')
        .eq('id', p['user_id'])
        .maybeSingle();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p['title'] ?? ''),
        content: Text(
          'البائع: ${seller?['full_name'] ?? 'التاجر'}\n'
          'رقم الهاتف: ${seller?['phone'] ?? 'غير متوفر'}\n'
          'السعر: ${p['price']} د.أ',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

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
            if (p['is_sold'] == true) {
              return false;
            }
            final catOk = _selectedCat == 'الكل' ||
                (p['main_category'] ?? '').toString().contains(_selectedCat) ||
                (p['sub_category'] ?? '').toString().contains(_selectedCat);
            final q = _search.trim().toLowerCase();
            final searchOk = q.isEmpty ||
                (p['title'] ?? '').toString().toLowerCase().contains(q) ||
                (p['chassis_number'] ?? '').toString().toLowerCase().contains(q);
            return catOk && searchOk;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم القطعة أو رقمها',
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
                            color: active ? Colors.white : AppColors.textPrimary,
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.74,
                  ),
                  itemCount: parts.length,
                  itemBuilder: (_, i) {
                    final p = parts[i];
                    final imgs = List<String>.from(p['images'] ?? []);

                    return FadeSlideIn(
                      index: i,
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
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${p['price']} د.أ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                BounceTap(
                                  onTap: () => _contactSeller(p),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.navy,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'تواصل',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('احجز موعد تركيب القطعة في أقرب ورشة',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _pickWorkshopForInstall,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.navy, width: 1.4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('اختيار ورشة وموعد',
                            style: TextStyle(
                                color: AppColors.navy, fontWeight: FontWeight.bold)),
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