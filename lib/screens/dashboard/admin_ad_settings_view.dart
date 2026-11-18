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

  @override
  void initState() {
    super.initState();
    _loadCurrentAd();
  }

  Future<void> _loadCurrentAd() async {
    final row = await _db
        .from('advertisements')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row != null && mounted) {
      setState(() {
        _currentAdId = row['id'];
        _titleCtrl.text = row['title'] ?? '';
        _uploadedUrl = row['image_url'];
        _isActive = row['is_active'] ?? false;
        _mediaType = row['media_type'] ?? 'image';
      });
    }
  }

  Future<void> _pickAndUploadMedia() async {
    final XFile? file = _mediaType == 'image'
        ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await _picker.pickVideo(source: ImageSource.gallery);

    if (file == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await file.readAsBytes();
      final path = 'ads/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await _db.storage.from('app_media').uploadBinary(path, bytes);
      final url = _db.storage.from('app_media').getPublicUrl(path);
      setState(() => _uploadedUrl = url);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAdSettings() async {
    if (_isActive && (_uploadedUrl == null || _uploadedUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى رفع صورة أو فيديو أولاً قبل تفعيل الإعلان')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleCtrl.text.trim().isEmpty
            ? 'إعلان رئيسي'
            : _titleCtrl.text.trim(),
        'image_url': _uploadedUrl ?? '',
        'media_type': _mediaType,
        'is_active': _isActive,
      };
      if (_currentAdId != null) {
        await _db.from('advertisements').update(data).eq('id', _currentAdId!);
      } else {
        final inserted =
            await _db.from('advertisements').insert(data).select().single();
        _currentAdId = inserted['id'];
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حفظ إعدادات الإعلان وتحديث الصفحة الرئيسية!'),
              backgroundColor: AppColors.success),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('إعدادات بانر الإعلان (أعلى الصفحة الرئيسية)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
            'لن يظهر البانر للمستخدمين إلا بعد رفع صورة/فيديو وتفعيل الإعلان.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('تفعيل الإعلان في الصفحة الرئيسية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          value: _isActive,
          activeTrackColor: AppColors.orange,
          onChanged: (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: 'عنوان الإعلان (اختياري)',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickAndUploadMedia,
          icon: Icon(
              _mediaType == 'image' ? Icons.upload_file : Icons.video_library),
          label: Text(_uploadedUrl == null
              ? 'رفع ${_mediaType == "image" ? "صورة" : "فيديو"} الإعلان'
              : 'تغيير الملف المرفوع (تم الرفع ✓)'),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _saving ? null : _saveAdSettings,
          child: _saving
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('حفظ إعدادات الإعلان',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
