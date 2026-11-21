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
  bool _isActive = true;
  String? _uploadedUrl;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadMedia() async {
    final XFile? file = _mediaType == 'image'
        ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await _picker.pickVideo(source: ImageSource.gallery);

    if (file == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await file.readAsBytes();
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = 'ads/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await _db.storage.from('app_media').uploadBinary(path, bytes);
      final url = _db.storage.from('app_media').getPublicUrl(path);
      if (mounted) {
        setState(() => _uploadedUrl = url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر رفع الملف: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addNewAd() async {
    if (_uploadedUrl == null || _uploadedUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى رفع صورة أو فيديو الإعلان أولاً')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _db.from('advertisements').insert({
        'title': _titleCtrl.text.trim().isEmpty
            ? 'إعلان الصفحة الرئيسية'
            : _titleCtrl.text.trim(),
        'image_url': _uploadedUrl!,
        'media_type': _mediaType,
        'is_active': _isActive,
      });

      if (mounted) {
        setState(() {
          _titleCtrl.clear();
          _uploadedUrl = null;
          _mediaType = 'image';
          _isActive = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة الإعلان بنجاح! سيظهر بالسكرول في الصفحة الرئيسية.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الإضافة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAd(Map<String, dynamic> ad) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الإعلان'),
        content: Text('هل أنت متأكد من حذف إعلان "${ad['title'] ?? ""}" نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.from('advertisements').delete().eq('id', ad['id']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'إدارة إعلانات الصفحة الرئيسية',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'يمكنك إضافة أكثر من إعلان؛ عند تفعيل أكثر من إعلان سيظهرون في الصفحة الرئيسية مع سكرول يدوي وتلقائي كل 5 ثواني.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إضافة إعلان جديد',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'image', label: Text('صورة'), icon: Icon(Icons.image)),
                    ButtonSegment(value: 'video', label: Text('فيديو'), icon: Icon(Icons.videocam)),
                  ],
                  selected: {_mediaType},
                  onSelectionChanged: (s) => setState(() {
                    _mediaType = s.first;
                    _uploadedUrl = null;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'عنوان الإعلان (اختياري)',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل الإعلان فور الإضافة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  value: _isActive,
                  activeTrackColor: AppColors.orange,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickAndUploadMedia,
                  icon: Icon(_mediaType == 'image' ? Icons.upload_file : Icons.video_library),
                  label: Text(
                    _uploadedUrl == null
                        ? 'رفع ${_mediaType == "image" ? "صورة" : "فيديو"} الإعلان'
                        : 'تم الرفع ✓ (اضغط لتغيير الملف)',
                  ),
                ),
                if (_uploadedUrl != null && _mediaType == 'image') ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(_uploadedUrl!, height: 120, fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _addNewAd,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle_outline),
                  label: const Text('إضافة الإعلان للقائمة', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'الإعلانات الحالية',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('advertisements').stream(primaryKey: ['id']).order('created_at', ascending: false),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
            }
            final ads = snap.data!;
            if (ads.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('لا توجد إعلانات مضافة حالياً')),
                ),
              );
            }
            return Column(
              children: ads.map((ad) {
                final active = ad['is_active'] == true;
                final isVideo = (ad['media_type'] as String? ?? 'image') == 'video';
                final url = (ad['image_url'] as String?) ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 64,
                        height: 48,
                        color: AppColors.placeholder,
                        child: isVideo
                            ? const Icon(Icons.play_circle_fill, color: AppColors.navy, size: 28)
                            : (url.isNotEmpty
                                ? Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                                  )
                                : const Icon(Icons.image)),
                      ),
                    ),
                    title: Text(
                      (ad['title'] as String?)?.isNotEmpty == true ? ad['title'] : 'إعلان بدون عنوان',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${isVideo ? "فيديو" : "صورة"} · ${active ? "نشط في الرئيسية" : "متوقف"}',
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
                          onChanged: (v) => _db
                              .from('advertisements')
                              .update({'is_active': v}).eq('id', ad['id']),
                        ),
                        IconButton(
                          tooltip: 'حذف الإعلان',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteAd(ad),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}