import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../config/env_config.dart';
import '../theme/app_theme.dart';
import 'animations.dart';

class HomeAdBanner extends StatefulWidget {
  const HomeAdBanner({super.key});

  @override
  State<HomeAdBanner> createState() => _HomeAdBannerState();
}

class _HomeAdBannerState extends State<HomeAdBanner> {
  late final Stream<List<Map<String, dynamic>>> _adsStream;

  @override
  void initState() {
    super.initState();
    _adsStream = Supabase.instance.client
        .from('advertisements')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EnvConfig.adsEnabled,
      builder: (_, enabled, __) {
        if (!enabled) return const SizedBox.shrink();
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _adsStream,
          builder: (context, snap) {
            final ads = (snap.data ?? [])
                .where((a) =>
                    (a['image_url'] as String? ?? '').trim().isNotEmpty)
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
    _pageController = PageController(viewportFraction: 1.0);
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
      if (!mounted || !_pageController.hasClients || widget.ads.length <= 1) {
        return;
      }
      final next = (_currentIndex + 1) % widget.ads.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _goToPage(int index) {
    if (!_pageController.hasClients || widget.ads.isEmpty) return;
    final target = index % widget.ads.length;
    _pageController.animateToPage(
      target < 0 ? widget.ads.length - 1 : target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
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
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 162,
            width: double.infinity,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: count,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                    _startAutoScroll();
                  },
                  itemBuilder: (_, index) {
                    final ad = widget.ads[index];
                    final url = (ad['image_url'] as String).trim();
                    final title = (ad['title'] as String? ?? '').trim();
                    final isVideo =
                        (ad['media_type'] as String? ?? 'image') == 'video';

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        isVideo
                            ? _AutoPlayBannerVideo(
                                key: ValueKey(ad['id']),
                                url: url,
                              )
                            : Image.network(
                                url,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 162,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.placeholder,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textSecondary,
                                    size: 32,
                                  ),
                                ),
                              ),
                        if (title.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 22, 12, 26),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.65),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                // شارة العدّاد عند وجود أكثر من إعلان
                if (count > 1)
                  PositionedDirectional(
                    top: 10,
                    end: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / $count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // أسهم تنقل سريعة اختيارية بالإضافة للسحب باليد
                if (count > 1) ...[
                  PositionedDirectional(
                    start: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: InkWell(
                        onTap: () => _goToPage(_currentIndex - 1),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: InkWell(
                        onTap: () => _goToPage(_currentIndex + 1),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // نقاط التنقل السفلية
                if (count > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(count, (i) {
                            final active = i == _currentIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              height: 6,
                              width: active ? 18 : 6,
                              decoration: BoxDecoration(
                                color:
                                    active ? AppColors.orange : Colors.white70,
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