import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/add_product_screen.dart';
import '../mobile/wallet_and_payments_screens.dart';

class MerchantProductsDashboard extends StatefulWidget {
  final bool embedded;
  final CustomerProfile? profile;
  const MerchantProductsDashboard({
    super.key,
    this.embedded = false,
    this.profile,
  });

  @override
  State<MerchantProductsDashboard> createState() =>
      _MerchantProductsDashboardState();
}

class _MerchantProductsDashboardState extends State<MerchantProductsDashboard> {
  final _db = Supabase.instance.client;
  final _loc = AppLocaleService.instance;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  final Set<String> _busyIds = {};
  CustomerProfile? _loadedProfile;

  @override
  void initState() {
    super.initState();
    _loadedProfile = widget.profile;
    if (_loadedProfile == null) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _db
          .from('customers')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() => _loadedProfile = CustomerProfile.fromMap(row));
      }
    } catch (_) {}
  }

  Future<void> _toggleVisibility(Map<String, dynamic> p) async {
    final id = p['id'] as String;
    final currentHidden = (p['is_hidden'] as bool?) ?? false;
    final nextHidden = !currentHidden;

    setState(() => _busyIds.add(id));
    try {
      final updated = await _db
          .from('products')
          .update({'is_hidden': nextHidden})
          .eq('id', id)
          .select('id, is_hidden');

      if (updated.isEmpty) {
        throw Exception('لم يتم تعديل حالة المنتج — تحقق من الصلاحيات');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextHidden
                  ? 'تم إخفاء "${p['title']}" من المتجر ✓'
                  : 'تم إظهار "${p['title']}" في المتجر ✓',
            ),
            backgroundColor: nextHidden ? AppColors.navy : AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تغيير حالة الإظهار: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _editProductDialog(Map<String, dynamic> p) async {
    final currentPrice = ((p['price'] as num?) ?? 0).toDouble();
    final currentOriginal =
        ((p['original_price'] as num?) ?? currentPrice).toDouble();
    final currentDiscount = (p['discount_percent'] as int?) ?? 0;

    final priceCtrl = TextEditingController(
      text: (currentDiscount > 0 ? currentOriginal : currentPrice)
          .toStringAsFixed(2),
    );
    final discountCtrl = TextEditingController(text: '$currentDiscount');
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final basePrice =
              double.tryParse(priceCtrl.text.trim()) ?? currentPrice;
          final disc =
              (int.tryParse(discountCtrl.text.trim()) ?? 0).clamp(0, 90);
          final finalPrice = disc > 0
              ? double.parse((basePrice * (1 - disc / 100)).toStringAsFixed(2))
              : basePrice;

          return AlertDialog(
            title: const Text(
              'تعديل السعر والخصم',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (p['title'] as String?) ?? '',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setD(() {}),
                  decoration: InputDecoration(
                    labelText: 'السعر الأصلي (د.أ)',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: discountCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setD(() {}),
                  decoration: InputDecoration(
                    labelText: 'نسبة الخصم % (0 = بدون خصم)',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    disc > 0
                        ? 'السعر بعد الخصم ($disc%): ${finalPrice.toStringAsFixed(2)} د.أ'
                        : 'السعر النهائي: ${finalPrice.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: saving
                    ? null
                    : () async {
                        if (basePrice <= 0) return;
                        setD(() => saving = true);
                        try {
                          final updated = await _db
                              .from('products')
                              .update({
                                'price': finalPrice,
                                'original_price': disc > 0 ? basePrice : null,
                                'discount_percent': disc,
                              })
                              .eq('id', p['id'])
                              .select('id');
                          if (updated.isEmpty) {
                            throw Exception('تعذر حفظ التعديل');
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تحديث السعر والخصم بنجاح ✓'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          setD(() => saving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('خطأ: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('حفظ التعديل'),
              ),
            ],
          );
        },
      ),
    );
    priceCtrl.dispose();
    discountCtrl.dispose();
  }

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنشور'),
        content: Text('هل تريد حذف "${p['title']}" نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.from('products').delete().eq('id', p['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حذف المنتج بنجاح'),
              backgroundColor: AppColors.navy),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildProductsBody(String uid) {
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('products')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100),
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

        final totalViews =
            items.fold<int>(0, (s, p) => s + ((p['views_count'] as int?) ?? 0));
        final totalClicks = items.fold<int>(
            0, (s, p) => s + ((p['clicks_count'] as int?) ?? 0));
        final totalSales =
            items.fold<int>(0, (s, p) => s + ((p['sales_count'] as int?) ?? 0));

        final chartData = items.take(6).map((p) {
          final title = (p['title'] as String? ?? '');
          final short = title.length > 8 ? title.substring(0, 8) : title;
          return (
            label: short,
            value: ((p['views_count'] as int?) ?? 0).toDouble()
          );
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'قطع الغيار والمخزون',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                          context, animatedRoute(const AddProductScreen())),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة قطعة'),
                    ),
                  ],
                ),
              ),
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
                _statCard('المنشورات', items.length, Icons.inventory_2_outlined),
                const SizedBox(width: 8),
                _statCard('المشاهدات', totalViews, Icons.visibility_outlined),
                const SizedBox(width: 8),
                _statCard('النقرات', totalClicks, Icons.touch_app_outlined),
                const SizedBox(width: 8),
                _statCard('المبيعات', totalSales, Icons.shopping_bag_outlined),
              ],
            ),
            if (chartData.isNotEmpty) ...[
              const SizedBox(height: 16),
              InteractiveAnimatedChart(
                title: 'تفاعل المشاهدات حسب القطعة',
                data: chartData,
                unit: 'مشاهدة',
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
                final id = p['id'] as String;
                final views = (p['views_count'] as int?) ?? 0;
                final clicks = (p['clicks_count'] as int?) ?? 0;
                final sales = (p['sales_count'] as int?) ?? 0;
                final isHidden = (p['is_hidden'] as bool?) ?? false;
                final discount = (p['discount_percent'] as int?) ?? 0;
                final imgs = List<String>.from(p['images'] ?? []);
                final isBusy = _busyIds.contains(id);

                return FadeSlideIn(
                  index: i,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isHidden ? Colors.grey.shade100 : Colors.white,
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
                                child: imgs.isEmpty
                                    ? const Icon(Icons.settings_outlined)
                                    : null,
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
                                            (p['title'] as String?) ?? '',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isHidden
                                                  ? AppColors.textSecondary
                                                  : AppColors.navy,
                                            ),
                                          ),
                                        ),
                                        if (isHidden)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'مخفي',
                                              style: TextStyle(
                                                color: Colors.deepOrange,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (discount > 0) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '-$discount%',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${p['price']} د.أ · ${p['car_name'] ?? ""}',
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
                          const Divider(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _miniMetric(
                                  Icons.visibility_outlined, '$views مشاهدة'),
                              _miniMetric(
                                  Icons.touch_app_outlined, '$clicks نقرة'),
                              _miniMetric(Icons.sell_outlined, '$sales مبيعة'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isHidden
                                        ? AppColors.success
                                        : Colors.orange,
                                    side: BorderSide(
                                      color: isHidden
                                          ? AppColors.success
                                          : Colors.orange,
                                    ),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () => _toggleVisibility(p),
                                  icon: isBusy
                                      ? const SizedBox(
                                          width: 15,
                                          height: 15,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(
                                          isHidden
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          size: 17,
                                        ),
                                  label: Text(
                                    isHidden ? 'إظهار' : 'إخفاء',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.navy,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: () => _editProductDialog(p),
                                  icon: const Icon(Icons.local_offer_outlined,
                                      size: 17),
                                  label: const Text(
                                    'السعر والخصم',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'حذف المنتج',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _deleteProduct(p),
                              ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return const Center(child: Text('يرجى تسجيل الدخول'));
    }

    if (widget.embedded) {
      return _buildProductsBody(uid);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_loc.tr('لوحة تحكم التاجر', 'Merchant Dashboard')),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle,
                  color: AppColors.orange, size: 28),
              onPressed: () => Navigator.push(
                  context, animatedRoute(const AddProductScreen())),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.orange,
            labelColor: AppColors.orange,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(
                icon: const Icon(Icons.inventory_2_outlined),
                text: _loc.tr('المنتجات والأداء', 'Products & Stats'),
              ),
              Tab(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                text: _loc.tr('المحفظة المالية', 'Wallet & Payouts'),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildProductsBody(uid),
            _loadedProfile == null
                ? const Center(child: CircularProgressIndicator())
                : ProviderWalletView(
                    profile: _loadedProfile!,
                    onRefreshProfile: _loadProfile,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, int val, IconData icon) {
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
            PulseBlink(child: Icon(icon, color: AppColors.orange, size: 20)),
            const SizedBox(height: 4),
            AnimatedCounter(
              value: val,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
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