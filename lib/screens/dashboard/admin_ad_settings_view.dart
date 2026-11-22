import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

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
  bool _isActive = false;
  String? _uploadedUrl;
  String? _currentAdId;
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

  Future<void> _loadAds() async {
    try {
      final rows = await _db
          .from('advertisements')
          .select()
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _allAds = list;
        _loading = false;
        if (list.isNotEmpty) {
          final first = list.first;
          _currentAdId = first['id'] as String?;
          _titleCtrl.text = (first['title'] as String?) ?? '';
          _uploadedUrl = first['image_url'] as String?;
          _isActive = (first['is_active'] as bool?) ?? false;
          _mediaType = (first['media_type'] as String?) ?? 'image';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل الإعلانات: $e'), backgroundColor: Colors.red),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع الملف بنجاح! اضغط "حفظ إعدادات الإعلان" لتطبيقه.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الملف: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleAdActiveInstant(bool nextVal) async {
    if (nextVal && (_uploadedUrl == null || _uploadedUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى رفع صورة أو فيديو أولاً قبل تفعيل الإعلان'),
          backgroundColor: AppColors.orange,
        ),
      );
      return;
    }

    final prev = _isActive;
    setState(() => _isActive = nextVal);

    if (_currentAdId == null) return;

    try {
      // عند تفعيل إعلان واحد، نعطل باقي الإعلانات القديمة إن وجدت لضمان عرض الإعلان الحالي فقط
      if (nextVal) {
        await _db.from('advertisements').update({'is_active': false}).neq('id', _currentAdId!);
      }
      final updated = await _db
          .from('advertisements')
          .update({'is_active': nextVal})
          .eq('id', _currentAdId!)
          .select();

      if (updated.isEmpty) {
        throw Exception('لم يتم تعديل السجل — تأكد من تطبيق صلاحيات الأدمن في SQL (الدفعة 1)');
      }

      await _loadAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextVal ? 'تم تفعيل الإعلان في الصفحة الرئيسية ✓' : 'تم تعطيل الإعلان ✓'),
            backgroundColor: nextVal ? AppColors.success : AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActive = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تغيير حالة الإعلان: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleSpecificAd(Map<String, dynamic> ad, bool nextVal) async {
    try {
      if (nextVal) {
        await _db.from('advertisements').update({'is_active': false}).neq('id', ad['id']);
      }
      final updated = await _db
          .from('advertisements')
          .update({'is_active': nextVal})
          .eq('id', ad['id'])
          .select();
      if (updated.isEmpty) {
        throw Exception('لا توجد صلاحية تعديل');
      }
      await _loadAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextVal ? 'تم تفعيل الإعلان ✓' : 'تم إيقاف الإعلان ✓'),
            backgroundColor: nextVal ? AppColors.success : AppColors.navy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAd(String id) async {
    try {
      await _db.from('advertisements').delete().eq('id', id);
      if (_currentAdId == id) {
        _currentAdId = null;
        _uploadedUrl = null;
        _isActive = false;
        _titleCtrl.clear();
      }
      await _loadAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الإعلان بنجاح'), backgroundColor: AppColors.navy),
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

  Future<void> _saveAdSettings() async {
    FocusScope.of(context).unfocus();
    if (_isActive && (_uploadedUrl == null || _uploadedUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى رفع صورة أو فيديو أولاً قبل تفعيل الإعلان')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleCtrl.text.trim().isEmpty ? 'إعلان رئيسي' : _titleCtrl.text.trim(),
        'image_url': _uploadedUrl ?? '',
        'media_type': _mediaType,
        'is_active': _isActive,
      };
      if (_currentAdId != null) {
        if (_isActive) {
          await _db.from('advertisements').update({'is_active': false}).neq('id', _currentAdId!);
        }
        final updated =
            await _db.from('advertisements').update(data).eq('id', _currentAdId!).select();
        if (updated.isEmpty) {
          throw Exception('لم يتم حفظ التعديل — تحقق من صلاحيات الأدمن في قاعدة البيانات');
        }
      } else {
        if (_isActive) {
          await _db.from('advertisements').update({'is_active': false}).neq('id', '00000000-0000-0000-0000-000000000000');
        }
        final inserted = await _db.from('advertisements').insert(data).select().single();
        _currentAdId = inserted['id'] as String?;
      }
      await _loadAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ إعدادات الإعلان وتحديث الصفحة الرئيسية!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
        );
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'إعدادات بانر الإعلان (أعلى الصفحة الرئيسية)',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'يُحدَّث التفعيل والتعطيل فوراً في قاعدة البيانات ويظهر مباشرة على شاشات جميع المستخدمين.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            title: const Text(
              'تفعيل الإعلان في الصفحة الرئيسية',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _isActive ? 'الإعلان ظاهر حالياً للمستخدمين' : 'الإعلان مخفي حالياً',
              style: TextStyle(
                color: _isActive ? AppColors.success : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            value: _isActive,
            activeTrackColor: AppColors.orange,
            onChanged: _saving ? null : _toggleAdActiveInstant,
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'image', label: Text('صورة'), icon: Icon(Icons.image)),
            ButtonSegment(value: 'video', label: Text('فيديو'), icon: Icon(Icons.videocam)),
          ],
          selected: {_mediaType},
          onSelectionChanged: (s) => setState(() => _mediaType = s.first),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleCtrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'عنوان الإعلان (اختياري)',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        if (_uploadedUrl != null && _uploadedUrl!.isNotEmpty && _mediaType == 'image') ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              _uploadedUrl!,
              height: 165,
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
          icon: Icon(_mediaType == 'image' ? Icons.upload_file : Icons.video_library),
          label: Text(
            _uploadedUrl == null || _uploadedUrl!.isEmpty
                ? 'رفع ${_mediaType == "image" ? "صورة" : "فيديو"} الإعلان'
                : 'تغيير الملف المرفوع (تم الرفع ✓)',
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _saving ? null : _saveAdSettings,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('حفظ إعدادات الإعلان', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (_allAds.isNotEmpty) ...[
          const Divider(height: 32),
          const Text(
            'جميع الإعلانات المحفوظة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._allAds.map((ad) {
            final active = ad['is_active'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  ad['media_type'] == 'video' ? Icons.videocam : Icons.image,
                  color: active ? AppColors.orange : AppColors.textSecondary,
                ),
                title: Text(
                  (ad['title'] as String?) ?? 'إعلان',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  active ? 'مفعّل حالياً' : 'متوقف',
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? AppColors.success : AppColors.textSecondary,
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