import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/car_parts_catalog_az.dart';
import '../../models/db_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'book_workshop_screen.dart';
import 'emergency_screen.dart';
import 'live_store_home_screen.dart';

void showAiDiagnosticSheet(BuildContext context,
    {CustomerProfile? viewerProfile}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.76,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _AiDiagnosticBody(
          viewerProfile: viewerProfile,
          scrollController: scrollCtrl,
        ),
      ),
    ),
  );
}

class _AiDiagnosticBody extends StatefulWidget {
  final CustomerProfile? viewerProfile;
  final ScrollController scrollController;

  const _AiDiagnosticBody({
    required this.viewerProfile,
    required this.scrollController,
  });

  @override
  State<_AiDiagnosticBody> createState() => _AiDiagnosticBodyState();
}

class _AiDiagnosticBodyState extends State<_AiDiagnosticBody> {
  static const String _noBrand = 'غير محدد (اختياري)';

  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _descCtrl = TextEditingController();

  String _selectedBrand = _noBrand;
  String _selectedModel = '';
  String _selectedYear = 'جميع الموديلات';

  Uint8List? _imageBytes;
  Uint8List? _audioBytes;
  String _audioMime = 'audio/mp4';
  bool _isRecording = false;
  bool _analyzing = false;

  Map<String, dynamic>? _aiResult;
  List<Map<String, dynamic>> _matchingParts = [];

  @override
  void dispose() {
    _recorder.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _carSummary {
    if (_selectedBrand == _noBrand) {
      return '';
    }
    final cleanBrand = _selectedBrand.split(' ').first;
    if (_selectedYear == 'جميع الموديلات') {
      return '$cleanBrand $_selectedModel';
    }
    return '$cleanBrand $_selectedModel ($_selectedYear)';
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 75);
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _toggleAudioRecording() async {
    if (_isRecording) {
      final pathOrUrl = await _recorder.stop();
      setState(() => _isRecording = false);
      if (pathOrUrl == null) {
        return;
      }

      if (kIsWeb) {
        final resp = await http.get(Uri.parse(pathOrUrl));
        if (mounted) {
          setState(() {
            _audioBytes = resp.bodyBytes;
            _audioMime = 'audio/webm';
          });
        }
      } else {
        final bytes = await XFile(pathOrUrl).readAsBytes();
        if (mounted) {
          setState(() {
            _audioBytes = bytes;
            _audioMime = 'audio/mp4';
          });
        }
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يرجى السماح بصلاحية الميكروفون لتسجيل صوت العطل')),
        );
      }
      return;
    }

    if (kIsWeb) {
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.opus),
          path: '');
    } else {
      final dir = await getTemporaryDirectory();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: '${dir.path}/engine_sound.m4a',
      );
    }
    if (mounted) {
      setState(() => _isRecording = true);
    }
  }

  Future<void> _analyzeWithAi() async {
    if (_imageBytes == null &&
        _audioBytes == null &&
        _descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('صوّر المشكلة أو سجّل صوت العطل أو اكتب وصفاً أولاً')),
      );
      return;
    }

    setState(() {
      _analyzing = true;
      _aiResult = null;
      _matchingParts = [];
    });

    try {
      final res = await _db.functions.invoke(
        'ai-diagnose',
        body: {
          'car_name': _carSummary,
          'text_description': _descCtrl.text.trim(),
          'image_base64':
              _imageBytes != null ? base64Encode(_imageBytes!) : null,
          'audio_base64':
              _audioBytes != null ? base64Encode(_audioBytes!) : null,
          'audio_mime': _audioMime,
        },
      );

      final Map<String, dynamic> parsed = res.data is String
          ? jsonDecode(res.data)
          : Map<String, dynamic>.from(res.data);

      final mainCat = (parsed['main_category'] as String?) ?? '';
      final keywords = List<String>.from(parsed['search_keywords'] ?? []);
      final allProducts = await _db
          .from('products')
          .select()
          .eq('is_hidden', false)
          .eq('is_sold', false)
          .limit(50);

      final matched = allProducts.where((p) {
        final pCat = (p['main_category'] ?? '').toString();
        final pText = '${p['title']} ${p['sub_category']} ${p['description']}'
            .toLowerCase();
        final categoryMatches =
            (mainCat.isNotEmpty && pCat.contains(mainCat)) ||
                keywords.any((k) => pText.contains(k.toLowerCase()));
        if (!categoryMatches) {
          return false;
        }
        if (_selectedBrand != _noBrand) {
          final cleanBrand = _selectedBrand.split(' ').first.toLowerCase();
          final pCar = (p['car_name'] ?? '').toString().toLowerCase();
          return pCar.contains(cleanBrand);
        }
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _aiResult = parsed;
          _matchingParts = matched;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر التحليل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBrand = _selectedBrand != _noBrand;
    final models = hasBrand
        ? JordanCarsCatalog.brandsAndModels[_selectedBrand]!
        : <String>[];

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 20 + MediaQuery.of(context).viewInsets.bottom),
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, color: AppColors.orange),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مساعد غيارك الذكي (AI)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'صوّر المشكلة أو سجّل صوت العطل لتشخيصه واقتراح القطع',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface),
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt,
                    color: AppColors.navy, size: 18),
                label: const Text('تصوير العطل'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface),
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo, color: AppColors.navy, size: 18),
                label: const Text('من المعرض'),
              ),
            ),
          ],
        ),
        if (_imageBytes != null) ...[
          const SizedBox(height: 10),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(_imageBytes!,
                    height: 140, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => setState(() => _imageBytes = null),
                  child: const CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 15, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        BounceTap(
          onTap: _toggleAudioRecording,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: _isRecording
                  ? Colors.red.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _isRecording ? Colors.red : AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isRecording ? Icons.stop_circle : Icons.mic,
                  color: _isRecording ? Colors.red : AppColors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  _isRecording
                      ? 'جاري التسجيل... اضغط للإيقاف'
                      : (_audioBytes != null
                          ? 'تم تسجيل الصوت ✓ (اضغط لإعادة التسجيل)'
                          : 'تسجيل صوت المحرك أو المشكلة'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _isRecording ? Colors.red : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // اختيار شركة السيارة من الكتالوج (ثم يظهر الموديل والسنة)
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _selectedBrand,
          decoration: InputDecoration(
            labelText: 'شركة السيارة',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          items: [_noBrand, ...JordanCarsCatalog.brands]
              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
              .toList(),
          onChanged: (val) {
            if (val == null) {
              return;
            }
            setState(() {
              _selectedBrand = val;
              _selectedModel = val == _noBrand
                  ? ''
                  : JordanCarsCatalog.brandsAndModels[val]!.first;
            });
          },
        ),

        // تظهر قائمتا الموديل والسنة فور اختيار الشركة
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: !hasBrand
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey('car_models_$_selectedBrand'),
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('model_$_selectedBrand'),
                          isExpanded: true,
                          initialValue: _selectedModel,
                          decoration: InputDecoration(
                            labelText: 'الموديل',
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          items: models
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          items: JordanCarsCatalog.years
                              .map((y) =>
                                  DropdownMenuItem(value: y, child: Text(y)))
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
                ),
        ),

        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'اشرح الأعراض بإيجاز (اختياري)',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _analyzing ? null : _analyzeWithAi,
          icon: const Icon(Icons.auto_awesome),
          label: _analyzing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('فحص المشكلة واقتراح القطع',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (_aiResult != null) ...[
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _aiResult!['problem_title'] ?? 'نتيجة الفحص',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(
                        backgroundColor: _aiResult!['severity'] == 'عاجلة'
                            ? Colors.red.withValues(alpha: 0.15)
                            : AppColors.orangeLight,
                        label: Text(
                          'الخطورة: ${_aiResult!['severity'] ?? "متوسطة"}',
                          style: TextStyle(
                            color: _aiResult!['severity'] == 'عاجلة'
                                ? Colors.red
                                : AppColors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_aiResult!['diagnosis'] ?? '',
                      style: const TextStyle(fontSize: 13)),
                  const Divider(height: 18),
                  const Text('خطوات الحل:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  ...List<String>.from(_aiResult!['solution_steps'] ?? []).map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('• $s', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              animatedRoute(
                                SelectWorkshopScreen(
                                    viewerProfile: widget.viewerProfile),
                              ),
                            );
                          },
                          child: const Text('حجز ورشة'),
                        ),
                      ),
                      if (_aiResult!['needs_emergency'] == true &&
                          widget.viewerProfile != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                animatedRoute(
                                  Scaffold(
                                    appBar: AppBar(title: const Text('طوارئ')),
                                    body: EmergencyScreen(
                                        profile: widget.viewerProfile!),
                                  ),
                                ),
                              );
                            },
                            child: const Text('ميكانيكي طوارئ'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'القطع المقترحة في متجر غيارك',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_matchingParts.isEmpty)
            const Text(
              'لا توجد قطع مطابقة منشورة حالياً، يمكنك حجز ورشة مباشرة.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            ..._matchingParts.map((p) => Card(
                  child: ListTile(
                    title: Text(p['title'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${p['car_name']} · ${p['price']} د.أ'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        animatedRoute(ProductDetailsScreen(
                          product: p,
                          viewerProfile: widget.viewerProfile,
                        )),
                      );
                    },
                  ),
                )),
        ],
      ],
    );
  }
}
