import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/add_product_screen.dart';

class MerchantProductsDashboard extends StatefulWidget {
  const MerchantProductsDashboard({super.key});

  @override
  State<MerchantProductsDashboard> createState() => _MerchantProductsDashboardState();
}

class _MerchantProductsDashboardState extends State<MerchantProductsDashboard> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  String _sortMode = 'newest'; // newest | views | clicks | sales

  Future<void> _editProductDialog(Map<String, dynamic> p) async {
    final titleCtrl = TextEditingController(text: (p['title'] as String?) ?? '');
    final priceCtrl = TextEditingController(text: '${p['price'] ?? 0}');
    final qtyCtrl = TextEditingController(text: '${p['quantity'] ?? 1}');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المنشور (السعر والكمية)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'عنوان القطعة'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر (د.أ)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية المتوفرة'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newPrice = double.tryParse(priceCtrl.text.trim()) ??
                  ((p['price'] as num?)?.toDouble() ?? 0.0);
              final rawQty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
              final newQty = rawQty < 0 ? 0 : rawQty;

              await _db.from('products').update({
                'title': titleCtrl.text.trim().isEmpty ? p['title'] : titleCtrl.text.trim(),
                'price': newPrice,
                'quantity': newQty,
              }).eq('id', p['id']);

              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث السعر والكمية بنجاح!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProductDialog(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنشور'),
        content: Text('هل أنت متأكد من حذف "${p['title'] ?? ''}" نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.from('products').delete().eq('id', p['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المنشور بنجاح')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser!.id;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);

    return Scaffold(
      appBar: AppBar(
        title: const Text('داش بورد المنتجات والأداء'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.orange, size: 28),
            onPressed: () => Navigator.push(context, animatedRoute(const AddProductScreen())),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db
            .from('products')
            .stream(primaryKey: ['id'])
            .eq('user_id', uid)
            .order('created_at', ascending: false),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data!.where((p) {
            final dt = DateTime.tryParse((p['created_at'] as String?) ?? '');
            if (dt == null) {
              return true;
            }
            return !dt.isBefore(range.start) &&
                !dt.isAfter(range.end.add(const Duration(days: 1)));
          }).toList();

          if (_sortMode == 'views') {
            items.sort((a, b) => ((b['views_count'] as int?) ?? 0).compareTo((a['views_count'] as int?) ?? 0));
          } else if (_sortMode == 'clicks') {
            items.sort((a, b) => ((b['clicks_count'] as int?) ?? 0).compareTo((a['clicks_count'] as int?) ?? 0));
          } else if (_sortMode == 'sales') {
            items.sort((a, b) => ((b['sales_count'] as int?) ?? 0).compareTo((a['sales_count'] as int?) ?? 0));
          }

          final totalViews = items.fold<int>(0, (s, p) => s + ((p['views_count'] as int?) ?? 0));
          final totalClicks = items.fold<int>(0, (s, p) => s + ((p['clicks_count'] as int?) ?? 0));
          final totalSales = items.fold<int>(0, (s, p) => s + ((p['sales_count'] as int?) ?? 0));

          final (chartTitle, chartUnit, metricKey) = switch (_sortMode) {
            'clicks' => ('تفاعل النقرات حسب القطعة', 'نقرة', 'clicks_count'),
            'sales' => ('المبيعات حسب القطعة', 'مبيعة', 'sales_count'),
            _ => ('تفاعل المشاهدات حسب القطعة', 'مشاهدة', 'views_count'),
          };

          final chartData = items.take(6).map((p) {
            final title = (p['title'] as String? ?? '');
            final short = title.length > 8 ? title.substring(0, 8) : title;
            return (label: short, value: ((p[metricKey] as int?) ?? 0).toDouble());
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DateRangeFilterBar(
                period: _period,
                customRange: _customRange,
                onChanged: (p, r) => setState(() {
                  _period = p;
                  _customRange = r;
                }),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _statCard('المنشورات', items.length, Icons.inventory_2_outlined, 'newest'),
                  const SizedBox(width: 8),
                  _statCard('المشاهدات', totalViews, Icons.visibility_outlined, 'views'),
                  const SizedBox(width: 8),
                  _statCard('النقرات', totalClicks, Icons.touch_app_outlined, 'clicks'),
                  const SizedBox(width: 8),
                  _statCard('المبيعات', totalSales, Icons.shopping_bag_outlined, 'sales'),
                ],
              ),
              if (chartData.isNotEmpty) ...[
                const SizedBox(height: 16),
                InteractiveAnimatedChart(
                  title: chartTitle,
                  data: chartData,
                  unit: chartUnit,
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'إدارة منشوراتك',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    switch (_sortMode) {
                      'views' => 'مرتبة حسب المشاهدات',
                      'clicks' => 'مرتبة حسب النقرات',
                      'sales' => 'مرتبة حسب المبيعات',
                      _ => 'مرتبة حسب الأحدث',
                    },
                    style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('لا توجد قطع ضمن هذه الفترة الزمنية'),
                  ),
                )
              else
                ...List.generate(items.length, (i) {
                  final p = items[i];
                  final views = (p['views_count'] as int?) ?? 0;
                  final clicks = (p['clicks_count'] as int?) ?? 0;
                  final sales = (p['sales_count'] as int?) ?? 0;
                  final qty = (p['quantity'] as num?)?.toInt() ?? 1;
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
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: imgs.isEmpty ? const Icon(Icons.settings_outlined) : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p['title'] ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          if (isHidden)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'مخفي',
                                                style: TextStyle(color: AppColors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Text(
                                        '${p['price']} د.أ · ${p['car_name']}',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'الكمية المتوفرة: $qty',
                                        style: const TextStyle(
                                          color: AppColors.success,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  ),
                                  onPressed: () => _editProductDialog(p),
                                  icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.navy),
                                  label: const Text('تعديل السعر/الكمية', style: TextStyle(fontSize: 11, color: AppColors.navy)),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: isHidden ? 'إظهار المنشور' : 'إخفاء المنشور',
                                  icon: Icon(
                                    isHidden ? Icons.visibility_off : Icons.visibility,
                                    color: isHidden ? AppColors.orange : AppColors.navy,
                                  ),
                                  onPressed: () => _db
                                      .from('products')
                                      .update({'is_hidden': !isHidden}).eq('id', p['id']),
                                ),
                                IconButton(
                                  tooltip: 'حذف المنشور',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _deleteProductDialog(p),
                                ),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _miniMetric(Icons.visibility_outlined, '$views مشاهدة'),
                                _miniMetric(Icons.touch_app_outlined, '$clicks نقرة'),
                                _miniMetric(Icons.sell_outlined, '$sales مبيعة'),
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

  Widget _statCard(String label, int val, IconData icon, String sortKey) {
    final active = _sortMode == sortKey;
    return Expanded(
      child: Material(
        color: active ? AppColors.orangeLight : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _sortMode = sortKey),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? AppColors.orange : AppColors.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                PulseBlink(child: Icon(icon, color: AppColors.orange, size: 20)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedCounter(
                    value: val,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? AppColors.orange : AppColors.textSecondary,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.navy),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}