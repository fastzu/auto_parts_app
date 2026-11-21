import 'dart:async';
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

        return FadeSlideIn(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _AdsCarousel(ads: ads),
          ),
        );
      },
    );
  }
}

class _AdsCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> ads;
  const _AdsCarousel({required this.ads});

  @override
  State<_AdsCarousel> createState() => _AdsCarouselState();
}

class _AdsCarouselState extends State<_AdsCarousel> {
  late final PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _AdsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= widget.ads.length) {
      _currentIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
    if (oldWidget.ads.length != widget.ads.length) {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (widget.ads.length <= 1) return;

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients || widget.ads.length <= 1) return;
      final next = (_currentIndex + 1) % widget.ads.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.ads.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 155,
            width: double.infinity,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: count,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                    // إعادة ضبط المؤقت عند السحب اليدوي حتى لا يقلب فوراً
                    _startAutoScroll();
                  },
                  itemBuilder: (_, index) {
                    final ad = widget.ads[index];
                    final url = ad['image_url'] as String;
                    final isVideo = (ad['media_type'] as String? ?? 'image') == 'video';
                    return isVideo
                        ? _AutoPlayBannerVideo(key: ValueKey(ad['id']), url: url)
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 155,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.placeholder,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textSecondary,
                                size: 32,
                              ),
                            ),
                          );
                  },
                ),
                if (count > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(count, (i) {
                            final active = i == _currentIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: 6,
                              width: active ? 18 : 6,
                              decoration: BoxDecoration(
                                color: active ? AppColors.orange : Colors.white70,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AutoPlayBannerVideo extends StatefulWidget {
  final String url;
  const _AutoPlayBannerVideo({super.key, required this.url});

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