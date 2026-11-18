import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import 'animations.dart';

class HomeAdBanner extends StatelessWidget {
  const HomeAdBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('advertisements')
          .stream(primaryKey: ['id'])
          .eq('is_active', true)
          .order('created_at', ascending: false),
      builder: (context, snap) {
        final ads = (snap.data ?? [])
            .where((a) => (a['image_url'] as String? ?? '').trim().isNotEmpty)
            .toList();

        if (ads.isEmpty) return const SizedBox.shrink();

        final ad = ads.first;
        final url = ad['image_url'] as String;
        final isVideo = (ad['media_type'] as String? ?? 'image') == 'video';

        return FadeSlideIn(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 155,
                width: double.infinity,
                child: isVideo
                    ? _AutoPlayBannerVideo(url: url)
                    : Image.network(url, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AutoPlayBannerVideo extends StatefulWidget {
  final String url;
  const _AutoPlayBannerVideo({required this.url});

  @override
  State<_AutoPlayBannerVideo> createState() => _AutoPlayBannerVideoState();
}

class _AutoPlayBannerVideoState extends State<_AutoPlayBannerVideo> {
  late final VideoPlayerController _vc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _ready = true);
          _vc.play();
        }
      });
  }

  @override
  void dispose() {
    _vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Container(
        color: AppColors.placeholder,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _vc.value.size.width,
        height: _vc.value.size.height,
        child: VideoPlayer(_vc),
      ),
    );
  }
}
