import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';

Route<T> animatedRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class GhiyarakLogo extends StatefulWidget {
  final double size;
  const GhiyarakLogo({super.key, this.size = 40});

  @override
  State<GhiyarakLogo> createState() => _GhiyarakLogoState();
}

class _GhiyarakLogoState extends State<GhiyarakLogo> {
  double _turns = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _turns += 0.5);
      },
      child: AnimatedRotation(
        turns: _turns,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * 0.25),
          child: Image.asset(
            'assets/ghayarak-icon.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: widget.size,
              height: widget.size,
              color: const Color(0xFF121A27),
              child: Icon(Icons.settings, color: Colors.white, size: widget.size * 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// السبلاش المتحرك باستخدام الصور الثلاث المنفصلة: gear.png + ring.png + wrench.png
class GhiyarakAnimatedSplash extends StatefulWidget {
  final VoidCallback? onCompleted;
  const GhiyarakAnimatedSplash({super.key, this.onCompleted});

  @override
  State<GhiyarakAnimatedSplash> createState() => _GhiyarakAnimatedSplashState();
}

class _GhiyarakAnimatedSplashState extends State<GhiyarakAnimatedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            widget.onCompleted?.call();
          }
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ctrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121A27),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            final gearT = Curves.easeOutCubic.transform((t / 0.42).clamp(0.0, 1.0));
            final ringT = Curves.easeOut.transform(((t - 0.21) / 0.29).clamp(0.0, 1.0));
            final wrenchT = Curves.easeOutBack.transform(((t - 0.37) / 0.38).clamp(0.0, 1.0));
            final titleT = Curves.easeOutCubic.transform(((t - 0.62) / 0.29).clamp(0.0, 1.0));
            final subT = Curves.easeOutCubic.transform(((t - 0.71) / 0.29).clamp(0.0, 1.0));

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 195,
                  height: 195,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1) صورة الترس: gear.png
                      Opacity(
                        opacity: gearT,
                        child: Transform.rotate(
                          angle: -math.pi * (1 - gearT),
                          child: Transform.scale(
                            scale: 0.4 + 0.6 * gearT,
                            child: Image.asset('assets/gear.png', width: 195, height: 195),
                          ),
                        ),
                      ),
                      // 2) صورة الحلقة: ring.png (تُرسم دائرياً تدريجياً)
                      if (ringT > 0)
                        ClipPath(
                          clipper: _RingSweepClipper(ringT),
                          child: Image.asset('assets/ring.png', width: 195, height: 195),
                        ),
                      // 3) صورة المفتاح: wrench.png
                      Opacity(
                        opacity: wrenchT.clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: (-140 * math.pi / 180) * (1 - wrenchT),
                          child: Transform.scale(
                            scale: (0.2 + 0.8 * wrenchT).clamp(0.01, 1.3),
                            child: Image.asset('assets/wrench.png', width: 195, height: 195),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: titleT,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - titleT)),
                    child: const Text(
                      'غيارك',
                      style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: subT,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - subT)),
                    child: const Text(
                      'قطع غيار · ورش · طوارئ',
                      style: TextStyle(color: Color(0xFF9AA4B4), fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RingSweepClipper extends CustomClipper<Path> {
  final double progress;
  _RingSweepClipper(this.progress);

  @override
  Path getClip(Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p >= 1.0) {
      return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    final center = Offset(size.width / 2, size.height / 2);
    return Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: size.width), 0, 2 * math.pi * p, false)
      ..close();
  }

  @override
  bool shouldReclip(covariant _RingSweepClipper oldClipper) => oldClipper.progress != progress;
}

class ShimmerProductsLoading extends StatefulWidget {
  const ShimmerProductsLoading({super.key});

  @override
  State<ShimmerProductsLoading> createState() => _ShimmerProductsLoadingState();
}

class _ShimmerProductsLoadingState extends State<ShimmerProductsLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final col = Color.lerp(AppColors.placeholder, Colors.grey.shade100, _c.value)!;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 230,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (_, __) => Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 95, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(12))),
                const SizedBox(height: 10),
                Container(height: 14, width: 100, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 6),
                Container(height: 11, width: 70, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AnimatedCounter extends StatelessWidget {
  final int value;
  final String suffix;
  final TextStyle? style;
  const AnimatedCounter({super.key, required this.value, this.suffix = '', this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, val, __) => Text('$val$suffix', style: style),
    );
  }
}

class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration duration;
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.duration = const Duration(milliseconds: 380)});

  @override
  Widget build(BuildContext context) {
    final delay = (index * 45).clamp(0, 320);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: duration.inMilliseconds + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 16 * (1 - value)), child: child)),
      child: child,
    );
  }
}

class BounceTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const BounceTap({super.key, required this.child, required this.onTap});

  @override
  State<BounceTap> createState() => _BounceTapState();
}

class _BounceTapState extends State<BounceTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

class PulsingPin extends StatefulWidget {
  final Color color;
  const PulsingPin({super.key, required this.color});

  @override
  State<PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<PulsingPin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => Transform.scale(
              scale: 0.6 + (_controller.value * 1.1),
              child: Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: (1 - _controller.value) * 0.35))),
            ),
          ),
          Icon(Icons.location_on, color: widget.color, size: 38),
        ],
      ),
    );
  }
}