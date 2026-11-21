import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../theme/app_theme.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _chassisCtrl = TextEditingController();

  String _mainCat = CarPartsCatalogAZ.mainCategories.first;
  late String _subPart = CarPartsCatalogAZ.categoriesAndParts[_mainCat]!.first;

  String _selectedBrand = JordanCarsCatalog.brands.first;
  late String _selectedModel = JordanCarsCatalog.brandsAndModels[_selectedBrand]!.first;
  String _selectedYear = '2022';

  final List<({String name, Uint8List bytes})> _images = [];
  bool _publishing = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _chassisCtrl.dispose();
    super.dispose();
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
    if (_images.isEmpty || _titleCtrl.text.trim().isEmpty || _priceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى رفع صورة القطعة وإدخال عنوان المنشور والسعر')),
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
      final uid = user.id;

      final settingsRows = await _db
          .from('system_settings')
          .select('key, value')
          .inFilter('key', ['enable_post_limits', 'default_max_posts']);
      final settingsMap = {for (final r in settingsRows) r['key'] as String: r['value'] as String};
      final limitsEnabled = settingsMap['enable_post_limits'] != 'false';
      final globalDefaultLimit = int.tryParse(settingsMap['default_max_posts'] ?? '5') ?? 5;

      final profile = await _db
          .from('customers')
          .select('max_posts_limit, free_posts_count')
          .eq('id', uid)
          .maybeSingle();

      final userLimit = (profile?['max_posts_limit'] as int?) ?? globalDefaultLimit;
      final currentCount = (profile?['free_posts_count'] as int?) ?? 0;

      if (limitsEnabled && currentCount >= userLimit) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'وصلت للحد الأقصى للمنشورات ($userLimit منشورات). تواصل مع الإدارة لزيادة الحد!',
              ),
              backgroundColor: AppColors.orange,
            ),
          );
        }
        return;
      }

      final List<String> imageUrls = [];
      for (final img in _images) {
        final safeName = img.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path = 'products/$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await _db.storage.from('app_media').uploadBinary(
              path,
              img.bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        imageUrls.add(_db.storage.from('app_media').getPublicUrl(path));
      }

      final cleanBrand = _selectedBrand.split(' ').first;
      final fullCarName = '$cleanBrand $_selectedModel';
      final parsedQty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
      final safeQty = parsedQty < 1 ? 1 : parsedQty;

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
        'chassis_number': _chassisCtrl.text.trim().isEmpty ? null : _chassisCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
        'quantity': safeQty,
        'images': imageUrls,
      });

      if (profile != null) {
        await _db.from('customers').update({
          'free_posts_count': currentCount + 1,
          'last_post_at': DateTime.now().toIso8601String(),
        }).eq('id', uid);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم نشر القطعة بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
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

    return Scaffold(
      appBar: AppBar(title: const Text('إضافة منشور قطعة غيار')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 36, color: AppColors.orange),
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
                              onTap: () => setState(() => _images.removeAt(i)),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close, size: 14, color: Colors.white),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            items: CarPartsCatalogAZ.mainCategories
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _mainCat = val;
                  _subPart = CarPartsCatalogAZ.categoriesAndParts[_mainCat]!.first;
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: CarPartsCatalogAZ.categoriesAndParts[_mainCat]!
                  .map((sub) => DropdownMenuItem(value: sub, child: Text(sub)))
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            items: JordanCarsCatalog.brands
                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedBrand = val;
                  _selectedModel = JordanCarsCatalog.brandsAndModels[_selectedBrand]!.first;
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    items: modelsForBrand
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _field(_priceCtrl, 'السعر (د.أ)', type: TextInputType.number),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(_qtyCtrl, 'الكمية المتوفرة', type: TextInputType.number),
              ),
            ],
          ),
          _field(_chassisCtrl, 'رقم الشاصي (VIN / Chassis Number)'),
          _field(_descCtrl, 'وصف وتفاصيل القطعة', maxLines: 3),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _publishing ? null : _publish,
            child: _publishing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'نشر القطعة الآن',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? type, int maxLines = 1}) {
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