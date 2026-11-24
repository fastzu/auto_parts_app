import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_top_toast.dart';

class AdminAdSettingsView extends StatefulWidget {
  const AdminAdSettingsView({super.key});

  @override
  State<AdminAdSettingsView> createState() => _AdminAdSettingsViewState();
}

class _AdminAdSettingsViewState extends State<AdminAdSettingsView> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  final _titleCtrl = TextEditingController();

  String _mediaType = 'image';
  bool _isActive = true;
  String? _uploadedUrl;
  String? _editingAdId; // null = إضافة إعلان جديد
  bool _saving = false;
  bool _loading = true;
  List<Map<String, dynamic>> _allAds = [];

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _startNewAd() {
    setState(() {
      _editingAdId = null;
      _titleCtrl.clear();
      _uploadedUrl = null;
      _mediaType = 'image';
      _isActive = true;
    });
    AppTopToast.info(
      'أنت الآن في وضع إضافة إعلان جديد — ارفع الصورة أو الفيديو ثم اضغط حفظ.',
      title: 'إعلان جديد',
      context: context,
    );
  }

  void _selectAdForEdit(Map<String, dynamic> ad) {
    setState(() {
      _editingAdId = ad['id'] as String?;
      _titleCtrl.text = (ad['title'] as String?) ?? '';
      _uploadedUrl = ad['image_url'] as String?;
      _mediaType = (ad['media_type'] as String?) ?? 'image';
      _isActive = (ad['is_active'] as bool?) ?? false;
    });
  }

  Future<void> _loadAds() async {
    try {
      final rows = await _db
          .from('advertisements')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _allAds = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppTopToast.error('تعذر تحميل الإعلانات: $e', context: context);
      }
    }
  }

  Future<void> _pickAndUploadMedia() async {
    final XFile? file = _mediaType == 'image'
        ? await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1400,
            maxHeight: 900,
            imageQuality: 78,
          )
        : await _picker.pickVideo(source: ImageSource.gallery);

    if (file == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await file.readAsBytes();
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = 'ads/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await _db.storage.from('app_media').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _mediaType == 'image' ? 'image/jpeg' : 'video/mp4',
              upsert: true,
            ),
          );
      final url = _db.storage.from('app_media').getPublicUrl(path);
      if (mounted) {
        setState(() => _uploadedUrl = url);
        AppTopToast.success(
          'تم رفع الملف بنجاح! اضغط "${_editingAdId == null ? 'إضافة الإعلان' : 'حفظ التعديل'}" لتطبيقه.',
          context: context,
        );
      }
    } catch (e) {
      if (mounted) {
        AppTopToast.error('فشل رفع الملف: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSpecificAd(Map<String, dynamic> ad, bool nextVal) async {
    try {
      final updated = await _db
          .from('advertisements')
          .update({'is_active': nextVal})
          .eq('id', ad['id'])
          .select();
      if (updated.isEmpty) {
        throw Exception('لا توجد صلاحية تعديل');
      }
      if (_editingAdId == ad['id'] && mounted) {
        setState(() => _isActive = nextVal);
      }
      await _loadAds();
      if (mounted) {
        AppTopToast.success(
          nextVal
              ? 'تم تفعيل الإعلان وإضافته لشريط الإعلانات ✓'
              : 'تم إيقاف الإعلان ✓',
          context: context,
        );
      }
    } catch (e) {
      if (mounted) {
        AppTopToast.error('تعذر تغيير حالة الإعلان: $e', context: context);
      }
    }
  }

  Future<void> _deleteAd(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الإعلان'),
        content: const Text('هل أنت متأكد من حذف هذا الإعلان نهائياً؟'),
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
    if (confirm != true) return;

    try {
      await _db.from('advertisements').delete().eq('id', id);
      if (_editingAdId == id) {
        _editingAdId = null;
        _uploadedUrl = null;
        _isActive = true;
        _titleCtrl.clear();
      }
      await _loadAds();
      if (mounted) {
        AppTopToast.success('تم حذف الإعلان بنجاح', context: context);
      }
    } catch (e) {
      if (mounted) {
        AppTopToast.error('تعذر الحذف: $e', context: context);
      }
    }
  }

  Future<void> _saveAdSettings() async {
    FocusScope.of(context).unfocus();
    if (_uploadedUrl == null || _uploadedUrl!.isEmpty) {
      AppTopToast.warning(
        'يرجى رفع صورة أو فيديو الإعلان أولاً',
        context: context,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleCtrl.text.trim().isEmpty
            ? 'إعلان #${_allAds.length + 1}'
            : _titleCtrl.text.trim(),
        'image_url': _uploadedUrl ?? '',
        'media_type': _mediaType,
        'is_active': _isActive,
      };

      if (_editingAdId != null) {
        final updated = await _db
            .from('advertisements')
            .update(data)
            .eq('id', _editingAdId!)
            .select();
        if (updated.isEmpty) {
          throw Exception('لم يتم حفظ التعديل — تحقق من صلاحيات الأدمن');
        }
        if (mounted) {
          AppTopToast.success(
            'تم تحديث الإعلان بنجاح ✓',
            context: context,
          );
        }
      } else {
        await _db.from('advertisements').insert(data).select().single();
        _titleCtrl.clear();
        _uploadedUrl = null;
        _isActive = true;
        if (mounted) {
          AppTopToast.success(
            'تم إضافة الإعلان الجديد بنجاح! يمكنك إضافة المزيد وسيتم التمرير بينها تلقائياً.',
            context: context,
          );
        }
      }

      await _loadAds();
    } catch (e) {
      if (mounted) {
        AppTopToast.error('فشل الحفظ: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final activeCount = _allAds.where((a) => a['is_active'] == true).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'إدارة إعلانات الصفحة الرئيسية',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _saving ? null : _startNewAd,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('إعلان جديد'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.view_carousel_rounded,
                  color: AppColors.orange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'الإعلانات المفعّلة حالياً: $activeCount من ${_allAds.length} — جميع الإعلانات المفعّلة تظهر للمستخدمين بشريط متحرك (سكرول أفقي).',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // بطاقة إضافة / تعديل إعلان
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _editingAdId != null ? AppColors.orange : AppColors.border,
              width: _editingAdId != null ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _editingAdId == null
                        ? 'إضافة إعلان جديد'
                        : 'تعديل إعلان محفوظ',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  if (_editingAdId != null)
                    TextButton(
                      onPressed: _startNewAd,
                      child: const Text('إلغاء التعديل'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'تفعيل هذا الإعلان في الصفحة الرئيسية',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  _isActive
                      ? 'سيظهر ضمن شريط الإعلانات المتحرك'
                      : 'سيُحفظ كمسودة (مخفي)',
                  style: TextStyle(
                    color:
                        _isActive ? AppColors.success : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                value: _isActive,
                activeTrackColor: AppColors.orange,
                onChanged: _saving ? null : (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'image', label: Text('صورة'), icon: Icon(Icons.image)),
                  ButtonSegment(
                      value: 'video',
                      label: Text('فيديو'),
                      icon: Icon(Icons.videocam)),
                ],
                selected: {_mediaType},
                onSelectionChanged: (s) => setState(() => _mediaType = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'عنوان الإعلان (اختياري)',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_uploadedUrl != null &&
                  _uploadedUrl!.isNotEmpty &&
                  _mediaType == 'image') ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    _uploadedUrl!,
                    height: 155,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 110,
                      color: AppColors.placeholder,
                      alignment: Alignment.center,
                      child: const Text('تعذر معاينة الصورة'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickAndUploadMedia,
                icon: Icon(
                    _mediaType == 'image' ? Icons.upload_file : Icons.video_library),
                label: Text(
                  _uploadedUrl == null || _uploadedUrl!.isEmpty
                      ? 'رفع ${_mediaType == "image" ? "صورة" : "فيديو"} الإعلان'
                      : 'تغيير الملف المرفوع (تم الرفع ✓)',
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _saveAdSettings,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(_editingAdId == null ? Icons.add_circle_outline : Icons.save),
                label: Text(
                  _editingAdId == null
                      ? 'إضافة الإعلان إلى الشريط'
                      : 'حفظ تعديلات الإعلان',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        if (_allAds.isNotEmpty) ...[
          const Divider(height: 32),
          Text(
            'جميع الإعلانات المحفوظة (${_allAds.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          ..._allAds.map((ad) {
            final active = ad['is_active'] == true;
            final isSelected = _editingAdId == ad['id'];
            final imgUrl = (ad['image_url'] as String? ?? '').trim();
            final isVideo = ad['media_type'] == 'video';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.orange
                      : (active
                          ? AppColors.success.withValues(alpha: 0.45)
                          : AppColors.border),
                  width: isSelected ? 1.6 : 1,
                ),
              ),
              child: ListTile(
                onTap: () => _selectAdForEdit(ad),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: !isVideo && imgUrl.isNotEmpty
                        ? Image.network(
                            imgUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.placeholder,
                              child: const Icon(Icons.image_not_supported),
                            ),
                          )
                        : Container(
                            color: AppColors.navy.withValues(alpha: 0.1),
                            child: Icon(
                              isVideo ? Icons.videocam : Icons.image,
                              color: active
                                  ? AppColors.orange
                                  : AppColors.textSecondary,
                            ),
                          ),
                  ),
                ),
                title: Text(
                  (ad['title'] as String?)?.trim().isNotEmpty == true
                      ? ad['title'] as String
                      : 'إعلان',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  active
                      ? 'مفعّل ويظهر في الشريط ✓ · اضغط للتعديل'
                      : 'متوقف · اضغط للتعديل',
                  style: TextStyle(
                    fontSize: 11.5,
                    color:
                        active ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: active,
                      activeTrackColor: AppColors.orange,
                      onChanged: (v) => _toggleSpecificAd(ad, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteAd(ad['id'] as String),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}