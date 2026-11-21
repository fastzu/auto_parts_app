import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/add_product_screen.dart';

class MerchantProductsDashboard extends StatefulWidget {
  const MerchantProductsDashboard({super.key});

  @override
  State<MerchantProductsDashboard> createState() =>
      _MerchantProductsDashboardState();
}

class _MerchantProductsDashboardState extends State<MerchantProductsDashboard> {
  final _db = Supabase.instance.client;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  String _sortBy = 'newest'; // newest | views | clicks | sales

  Future<void> _showEditProductDialog(Map<String, dynamic> p) async {
    final currentDiscount = (p['discount_percent'] as num?)?.toInt() ?? 0;
    final currentPrice = (p['price'] as num?)?.toDouble() ?? 0.0;
    final currentOriginal =
        (p['original_price'] as num?)?.toDouble() ?? currentPrice;
    final currentQty = (p['quantity'] as num?)?.toInt() ?? 1;

    final priceCtrl = TextEditingController(
      text: currentOriginal.toStringAsFixed(
        currentOriginal.truncateToDouble() == currentOriginal ? 0 : 2,
      ),
    );
    final qtyCtrl = TextEditingController(text: '$currentQty');
    final discountCtrl = TextEditingController(text: '$currentDiscount');
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final basePrice = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
          final pct =
              (int.tryParse(discountCtrl.text.trim()) ?? 0).clamp(0, 95);
          final finalPrice = pct > 0
              ? double.parse((basePrice * (1 - pct / 100)).toStringAsFixed(2))
              : basePrice;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تعديل: ${p['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setModal(() {}),
                          decoration: InputDecoration(
                            labelText: 'السعر الأصلي (د.أ)',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'الكمية المتوفرة',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setModal(() {}),
                    decoration: InputDecoration(
                      labelText: 'نسبة الخصم % (0 لإلغاء الخصم)',
                      prefixIcon: const Icon(Icons.local_offer_outlined,
                          color: Colors.red),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [0, 10, 15, 20, 30, 50].map((v) {
                      final active = pct == v;
                      return ChoiceChip(
                        label: Text(v == 0 ? 'بدون خصم' : '$v%'),
                        selected: active,
                        selectedColor:
                            v == 0 ? AppColors.navy : Colors.red.shade600,
                        labelStyle: TextStyle(
                          color: active ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onSelected: (_) {
                          setModal(() => discountCtrl.text = '$v');
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pct > 0
                          ? Colors.red.withValues(alpha: 0.08)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: pct > 0
                            ? Colors.red.withValues(alpha: 0.35)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'السعر النهائي للزبون:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            if (pct > 0) ...[
                              Text(
                                '${basePrice.toStringAsFixed(basePrice.truncateToDouble() == basePrice ? 0 : 2)} د.أ',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  decoration: TextDecoration.lineThrough,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '${finalPrice.toStringAsFixed(finalPrice.truncateToDouble() == finalPrice ? 0 : 2)} د.أ',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: pct > 0
                                    ? Colors.red.shade700
                                    : AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      ],
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              if (basePrice <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('يرجى إدخال سعر صحيح'),
                                  ),
                                );
                                return;
                              }
                              setModal(() => saving = true);
                              try {
                                final newQty =
                                    (int.tryParse(qtyCtrl.text.trim()) ?? 1)
                                        .clamp(0, 9999);
                                await _db.from('products').update({
                                  'price': finalPrice,
                                  'original_price': pct > 0 ? basePrice : null,
                                  'discount_percent': pct,
                                  'quantity': newQty,
                                }).eq('id', p['id']);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        pct > 0
                                            ? 'تم تطبيق خصم $pct% بنجاح!'
                                            : 'تم تحديث بيانات المنشور بنجاح!',
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModal(() => saving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('خطأ: $e'),
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
                              'حفظ التعديلات',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    priceCtrl.dispose();
    qtyCtrl.dispose();
    discountCtrl.dispose();
  }

  Future<void> _confirmDelete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنشور'),
        content: Text('هل أنت متأكد من حذف "${p['title'] ?? ''}" نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.from('products').delete().eq('id', p['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المنشور بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('يرجى تسجيل الدخول أولاً')),
      );
    }
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);

    return Scaffold(
      appBar: AppBar(
        title: const Text('داش بورد المنتجات والأداء'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.orange, size: 28),
            onPressed: () =>
                Navigator.push(context, animatedRoute(const AddProductScreen())),
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
            if (dt == null) return true;
            return !dt.isBefore(range.start) &&
                !dt.isAfter(range.end.add(const Duration(days: 1)));
          }).toList();

          if (_sortBy == 'views') {
            items.sort((a, b) =>
                ((b['views_count'] as int?) ?? 0)
                    .compareTo((a['views_count'] as int?) ?? 0));
          } else if (_sortBy == 'clicks') {
            items.sort((a, b) =>
                ((b['clicks_count'] as int?) ?? 0)
                    .compareTo((a['clicks_count'] as int?) ?? 0));
          } else if (_sortBy == 'sales') {
            items.sort((a, b) =>
                ((b['sales_count'] as int?) ?? 0)
                    .compareTo((a['sales_count'] as int?) ?? 0));
          }

          final totalViews =
              items.fold<int>(0, (s, p) => s + ((p['views_count'] as int?) ?? 0));
          final totalClicks =
              items.fold<int>(0, (s, p) => s + ((p['clicks_count'] as int?) ?? 0));
          final totalSales =
              items.fold<int>(0, (s, p) => s + ((p['sales_count'] as int?) ?? 0));

          final chartMetricKey = switch (_sortBy) {
            'clicks' => 'clicks_count',
            'sales' => 'sales_count',
            _ => 'views_count',
          };
          final chartTitle = switch (_sortBy) {
            'clicks' => 'تفاعل النقرات حسب القطعة',
            'sales' => 'المبيعات حسب القطعة',
            _ => 'تفاعل المشاهدات حسب القطعة',
          };
          final chartUnit = switch (_sortBy) {
            'clicks' => 'نقرة',
            'sales' => 'مبيعة',
            _ => 'مشاهدة',
          };

          final chartData = items.take(6).map((p) {
            final title = (p['title'] as String? ?? '');
            final short = title.length > 8 ? title.substring(0, 8) : title;
            return (
              label: short,
              value: ((p[chartMetricKey] as int?) ?? 0).toDouble(),
            );
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
                  _statCard('المنشورات', items.length,
                      Icons.inventory_2_outlined, 'newest'),
                  const SizedBox(width: 8),
                  _statCard('المشاهدات', totalViews,
                      Icons.visibility_outlined, 'views'),
                  const SizedBox(width: 8),
                  _statCard('النقرات', totalClicks,
                      Icons.touch_app_outlined, 'clicks'),
                  const SizedBox(width: 8),
                  _statCard('المبيعات', totalSales,
                      Icons.shopping_bag_outlined, 'sales'),
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
              const Text(
                'إدارة وإحصائيات كل قطعة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  final discountPct =
                      (p['discount_percent'] as num?)?.toInt() ?? 0;
                  final origPrice = (p['original_price'] as num?)?.toDouble();
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
                                Stack(
                                  children: [
                                    Container(
                                      width: 62,
                                      height: 62,
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
                                          ? const Icon(Icons.settings_outlined)
                                          : null,
                                    ),
                                    if (discountPct > 0)
                                      Positioned(
                                        bottom: 2,
                                        right: 2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade600,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '-$discountPct%',
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p['title'] ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          if (isHidden)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'مخفي',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black54),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            '${p['price']} د.أ',
                                            style: TextStyle(
                                              color: discountPct > 0
                                                  ? Colors.red.shade700
                                                  : AppColors.navy,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (discountPct > 0 &&
                                              origPrice != null)
                                            Text(
                                              '$origPrice د.أ',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                          Text(
                                            '· الكمية: $qty · ${p['car_name']}',
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 8),
                                      foregroundColor: discountPct > 0
                                          ? Colors.red.shade700
                                          : AppColors.navy,
                                      side: BorderSide(
                                        color: discountPct > 0
                                            ? Colors.red.shade400
                                            : AppColors.border,
                                      ),
                                    ),
                                    onPressed: () => _showEditProductDialog(p),
                                    icon: Icon(
                                      discountPct > 0
                                          ? Icons.local_offer
                                          : Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      discountPct > 0
                                          ? 'تعديل / خصم $discountPct%'
                                          : 'سعر / كمية / خصم',
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: isHidden ? 'إظهار' : 'إخفاء',
                                  icon: Icon(
                                    isHidden
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppColors.navy,
                                  ),
                                  onPressed: () => _db
                                      .from('products')
                                      .update({'is_hidden': !isHidden})
                                      .eq('id', p['id']),
                                ),
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _confirmDelete(p),
                                ),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _miniMetric(Icons.visibility_outlined,
                                    '$views مشاهدة'),
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

  Widget _statCard(String label, int val, IconData icon, String sortKey) {
    final active = _sortBy == sortKey;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _sortBy = sortKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: active
                ? AppColors.orange.withValues(alpha: 0.1)
                : AppColors.surface,
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
              AnimatedCounter(
                value: val,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              Text(
                label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
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
        Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}