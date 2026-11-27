import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/subscription_plans.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../dashboard/provider_subscriptions_screen.dart';

/// نافذة اقتراح الاشتراك الأنيقة عند الوصول للحد الأقصى للمنشورات
Future<void> showPostLimitUpgradeSheet(
  BuildContext context, {
  required String currentPlanCode,
  required int currentCount,
  required int maxLimit,
  required VoidCallback onSubscribed,
  bool justPublished = false,
}) async {
  final showSubs = EnvConfig.subscriptionsEnabled.value;
  final currentPlan = AppSubscriptionCatalog.getProviderPlan(currentPlanCode);
  final upgradePlans = AppSubscriptionCatalog.providerPlans
      .where((p) => p.code != 'free' && p.code != currentPlanCode)
      .toList();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.orange, width: 1.5),
                ),
                child: Icon(
                  showSubs
                      ? Icons.workspace_premium
                      : Icons.inventory_2_outlined,
                  color: AppColors.orange,
                  size: 34,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                justPublished
                    ? 'تم نشر منشورك بنجاح! 🎉\nووصلت للحد الأقصى ($currentCount / $maxLimit)'
                    : 'وصلت للحد الأقصى للمنشورات ($currentCount / $maxLimit)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                showSubs
                    ? 'باقتك الحالية: ${currentPlan.title}. اشترك الآن لرفع عدد المنشورات المسموحة وتقليل العمولة وزيادة ظهورك للعملاء!'
                    : 'لقد وصلت للحد الأقصى المسموح للمنشورات حالياً ($currentCount / $maxLimit). يمكنك إدارة منشوراتك الحالية من لوحة التحكم.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              if (showSubs) ...[
                const SizedBox(height: 16),
                ...upgradePlans.map((plan) {
                  final isUnlimited =
                      plan.maxPostsLimit < 0 || plan.maxPostsLimit >= 9999;
                  final postsLabel = isUnlimited
                      ? 'منشورات لا نهائية ∞'
                      : '${plan.maxPostsLimit} منشور';
                  final commPct = (plan.commissionRate * 100).toStringAsFixed(
                    plan.commissionRate == 0.065 || plan.commissionRate == 0.025
                        ? 1
                        : 0,
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: isUnlimited
                          ? AppColors.orangeLight
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isUnlimited ? AppColors.orange : AppColors.border,
                        width: isUnlimited ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isUnlimited
                              ? Icons.all_inclusive
                              : Icons.rocket_launch_outlined,
                          color: isUnlimited ? AppColors.orange : AppColors.navy,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: AppColors.navy,
                                ),
                              ),
                              Text(
                                '$postsLabel · عمولة $commPct% · تاجر موثوق ✓',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${plan.priceJod.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppColors.orange,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text(
                      'اشترك بالباقة الآن',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        animatedRoute(
                          ProviderSubscriptionsScreen(
                            currentPlanCode: currentPlanCode,
                            onSubscribed: onSubscribed,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'لاحقاً',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'حسناً',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class AddProductScreen extends StatefulWidget {
  final VoidCallback? onSubscribed;
  const AddProductScreen({super.key, this.onSubscribed});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _chassisCtrl = TextEditingController();

  String _mainCat = CarPartsCatalogAZ.mainCategories.first;
  late String _subPart = CarPartsCatalogAZ.categoriesAndParts[_mainCat]!.first;

  String _selectedBrand = JordanCarsCatalog.brands.first;
  late String _selectedModel =
      JordanCarsCatalog.brandsAndModels[_selectedBrand]!.first;
  String _selectedYear = '2022';

  final List<({String name, Uint8List bytes})> _images = [];
  bool _publishing = false;

  // حالة حصة المنشورات للباقة الحالية
  bool _loadingQuota = true;
  String _planCode = 'free';
  int _activePostsCount = 0;
  int _planLimit = 5;
  bool _isUnlimited = false;
  bool _limitsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _chassisCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingQuota = false);
      return;
    }
    try {
      final settingsRows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', ['enable_post_limits', 'default_max_posts']);
      final settingsMap = {
        for (final r in settingsRows) r['key'] as String: r['value'] as String,
      };
      final limitsEnabled = settingsMap['enable_post_limits'] != 'false';
      final globalDefaultLimit =
          int.tryParse(settingsMap['default_max_posts'] ?? '5') ?? 5;

      final profile = await _db
          .from('customers')
          .select('subscription_plan, max_posts_limit')
          .eq('id', user.id)
          .maybeSingle();

      final planCode = (profile?['subscription_plan'] as String?) ?? 'free';
      final plan = AppSubscriptionCatalog.getProviderPlan(planCode);
      final isUnlimited =
          plan.maxPostsLimit < 0 || plan.maxPostsLimit >= 9999;

      // الحد المعتمد حسب الباقة (المجانية: 5، شهر: 15، 3 أشهر: 30، 6 أشهر: 45، 12 شهر: لا نهائي)
      final effectiveLimit = planCode == 'free'
          ? ((profile?['max_posts_limit'] as int?) ?? globalDefaultLimit)
          : plan.maxPostsLimit;

      final myProducts = await _db
          .from('products')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_hidden', false);

      if (mounted) {
        setState(() {
          _limitsEnabled = limitsEnabled;
          _planCode = planCode;
          _isUnlimited = isUnlimited;
          _planLimit = effectiveLimit;
          _activePostsCount = (myProducts as List).length;
          _loadingQuota = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingQuota = false);
    }
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) {
      return;
    }
    for (final file in picked.take(4)) {
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() => _images.add((name: file.name, bytes: bytes)));
      }
    }
  }

  Future<void> _publish() async {
    if (_images.isEmpty ||
        _titleCtrl.text.trim().isEmpty ||
        _priceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى رفع صورة القطعة وإدخال عنوان المنشور والسعر'),
        ),
      );
      return;
    }

    final user = _db.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل الدخول أولاً')),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      await _loadQuota();
      // التحقق قبل النشر وإظهار اقتراح الاشتراك مباشرة عند الوصول للحد
      if (_limitsEnabled && !_isUnlimited && _activePostsCount >= _planLimit) {
        if (mounted) {
          setState(() => _publishing = false);
          await showPostLimitUpgradeSheet(
            context,
            currentPlanCode: _planCode,
            currentCount: _activePostsCount,
            maxLimit: _planLimit,
            onSubscribed: () {
              widget.onSubscribed?.call();
              _loadQuota();
            },
          );
        }
        return;
      }

      final uid = user.id;
      final List<String> imageUrls = [];

      for (final img in _images) {
        final safeName = img.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path =
            'products/$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await _db.storage.from('app_media').uploadBinary(
              path,
              img.bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        imageUrls.add(_db.storage.from('app_media').getPublicUrl(path));
      }

      final cleanBrand = _selectedBrand.split(' ').first;
      final fullCarName = '$cleanBrand $_selectedModel';

      await _db.from('products').insert({
        'user_id': uid,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? '$_subPart متوافقة مع $fullCarName ($_selectedYear)'
            : _descCtrl.text.trim(),
        'main_category': _mainCat,
        'sub_category': _subPart,
        'car_name': fullCarName,
        'car_model': _selectedYear,
        'chassis_number':
            _chassisCtrl.text.trim().isEmpty ? null : _chassisCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
        'images': imageUrls,
      });

      final newCount = _activePostsCount + 1;
      try {
        await _db.from('customers').update({
          'free_posts_count': newCount,
          'last_post_at': DateTime.now().toIso8601String(),
        }).eq('id', uid);
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نشر القطعة بنجاح! ✓'),
          backgroundColor: AppColors.success,
        ),
      );

      // إذا وصل المستخدم الآن إلى الحد الأقصى (مثلاً المنشور الـ 5)، نعرض له اقتراح الاشتراك فوراً!
      if (_limitsEnabled &&
          !_isUnlimited &&
          newCount >= _planLimit &&
          EnvConfig.subscriptionsEnabled.value) {
        setState(() {
          _activePostsCount = newCount;
          _publishing = false;
        });
        await showPostLimitUpgradeSheet(
          context,
          currentPlanCode: _planCode,
          currentCount: newCount,
          maxLimit: _planLimit,
          justPublished: true,
          onSubscribed: () {
            widget.onSubscribed?.call();
            _loadQuota();
          },
        );
        if (mounted) Navigator.pop(context);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _publishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelsForBrand = JordanCarsCatalog.brandsAndModels[_selectedBrand]!;
    final currentPlan = AppSubscriptionCatalog.getProviderPlan(_planCode);
    final reachedLimit =
        _limitsEnabled && !_isUnlimited && _activePostsCount >= _planLimit;

    return ListenableBuilder(
      listenable: EnvConfig.subscriptionsEnabled,
      builder: (context, _) {
        final showSubs = EnvConfig.subscriptionsEnabled.value;

        return Scaffold(
          appBar: AppBar(title: const Text('إضافة منشور قطعة غيار')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_loadingQuota)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color:
                        reachedLimit ? AppColors.orangeLight : AppColors.navy,
                    borderRadius: BorderRadius.circular(14),
                    border: reachedLimit
                        ? Border.all(color: AppColors.orange, width: 1.4)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isUnlimited
                            ? Icons.all_inclusive
                            : (reachedLimit
                                ? Icons.workspace_premium
                                : Icons.inventory_2_outlined),
                        color: AppColors.orange,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showSubs ? currentPlan.title : 'حصة المنشورات',
                              style: TextStyle(
                                color: reachedLimit
                                    ? AppColors.navy
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _isUnlimited
                                  ? 'منشوراتك لا نهائية ∞'
                                  : 'المنشورات المستخدمة: $_activePostsCount من $_planLimit',
                              style: TextStyle(
                                color: reachedLimit
                                    ? AppColors.orange
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: reachedLimit
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isUnlimited && showSubs)
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          onPressed: () => showPostLimitUpgradeSheet(
                            context,
                            currentPlanCode: _planCode,
                            currentCount: _activePostsCount,
                            maxLimit: _planLimit,
                            onSubscribed: () {
                              widget.onSubscribed?.call();
                              _loadQuota();
                            },
                          ),
                          child: const Text(
                            'ترقية الباقة',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  height: 125,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _images.isEmpty
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 36,
                              color: AppColors.orange,
                            ),
                            SizedBox(height: 6),
                            Text('اضغط لرفع صورة القطعة (إلزامي)'),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(10),
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _images[i].bytes,
                                  width: 95,
                                  height: 105,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _images.removeAt(i)),
                                  child: const CircleAvatar(
                                    radius: 11,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _mainCat,
                decoration: InputDecoration(
                  labelText: 'القسم الرئيسي للقطعة',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                items: CarPartsCatalogAZ.mainCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _mainCat = val;
                      _subPart =
                          CarPartsCatalogAZ.categoriesAndParts[_mainCat]!.first;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_mainCat),
                  isExpanded: true,
                  initialValue: _subPart,
                  decoration: InputDecoration(
                    labelText: 'القطعة الفرعية / الملحقات',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: CarPartsCatalogAZ.categoriesAndParts[_mainCat]!
                      .map((sub) =>
                          DropdownMenuItem(value: sub, child: Text(sub)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _subPart = val);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedBrand,
                decoration: InputDecoration(
                  labelText: 'شركة السيارة',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                items: JordanCarsCatalog.brands
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedBrand = val;
                      _selectedModel = JordanCarsCatalog
                          .brandsAndModels[_selectedBrand]!.first;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_selectedBrand),
                        isExpanded: true,
                        initialValue: _selectedModel,
                        decoration: InputDecoration(
                          labelText: 'الموديل',
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: modelsForBrand
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedModel = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedYear,
                      decoration: InputDecoration(
                        labelText: 'السنة',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: JordanCarsCatalog.years
                          .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedYear = val);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(_titleCtrl, 'عنوان المنشور'),
              _field(_priceCtrl, 'السعر (د.أ)', type: TextInputType.number),
              _field(_chassisCtrl, 'رقم الشاصي (VIN / Chassis Number)'),
              _field(_descCtrl, 'وصف وتفاصيل القطعة', maxLines: 3),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _publishing ? null : _publish,
                child: _publishing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'نشر القطعة الآن',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? type,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}