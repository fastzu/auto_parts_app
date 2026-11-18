import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/add_product_screen.dart';

class MerchantProductsDashboard extends StatelessWidget {
  const MerchantProductsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('داش بورد المنتجات والأداء'),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add_circle, color: AppColors.orange, size: 28),
            onPressed: () => Navigator.push(
                context, animatedRoute(const AddProductScreen())),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: db
            .from('products')
            .stream(primaryKey: ['id'])
            .eq('user_id', uid)
            .order('created_at', ascending: false),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;

          final totalViews = items.fold<int>(
              0, (s, p) => s + ((p['views_count'] as int?) ?? 0));
          final totalClicks = items.fold<int>(
              0, (s, p) => s + ((p['clicks_count'] as int?) ?? 0));
          final totalSales = items.fold<int>(
              0, (s, p) => s + ((p['sales_count'] as int?) ?? 0));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _statCard('المنشورات', '${items.length}',
                      Icons.inventory_2_outlined),
                  const SizedBox(width: 8),
                  _statCard(
                      'المشاهدات', '$totalViews', Icons.visibility_outlined),
                  const SizedBox(width: 8),
                  _statCard(
                      'النقرات', '$totalClicks', Icons.touch_app_outlined),
                  const SizedBox(width: 8),
                  _statCard(
                      'المبيعات', '$totalSales', Icons.shopping_bag_outlined),
                ],
              ),
              const SizedBox(height: 18),
              const Text('إحصائيات كل قطعة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('لم تنشر أي قطع غيار بعد'),
                  ),
                )
              else
                ...List.generate(items.length, (i) {
                  final p = items[i];
                  final views = (p['views_count'] as int?) ?? 0;
                  final clicks = (p['clicks_count'] as int?) ?? 0;
                  final sales = (p['sales_count'] as int?) ?? 0;
                  final isHidden = (p['is_hidden'] as bool?) ?? false;
                  final imgs = List<String>.from(p['images'] ?? []);

                  return FadeSlideIn(
                    index: i,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: AppColors.placeholder,
                                    borderRadius: BorderRadius.circular(12),
                                    image: imgs.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(imgs.first),
                                            fit: BoxFit.cover)
                                        : null,
                                  ),
                                  child: imgs.isEmpty
                                      ? const Icon(Icons.settings_outlined)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p['title'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                          '${p['price']} د.أ · ${p['car_name']}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: isHidden ? 'إظهار' : 'إخفاء',
                                  icon: Icon(isHidden
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () => db
                                      .from('products')
                                      .update({'is_hidden': !isHidden}).eq(
                                          'id', p['id']),
                                ),
                              ],
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _miniMetric(
                                    Icons.visibility_outlined, '$views مشاهدة'),
                                _miniMetric(
                                    Icons.touch_app_outlined, '$clicks نقرة'),
                                _miniMetric(
                                    Icons.sell_outlined, '$sales مبيعة'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String val, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.orange, size: 20),
            const SizedBox(height: 4),
            Text(val,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.navy),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
