import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

Route<T> animatedRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// شعار غيارك الرسمي من assets/ghayarak-icon.png
class GhiyarakLogo extends StatelessWidget {
  final double size;

  const GhiyarakLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: Image.asset(
        'assets/ghayarak-icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// شاشة السبلاش المتحركة بالطبقات الثلاث (gear.png + ring.png + wrench.png)
class GhiyarakAnimatedSplash extends StatefulWidget {
  const GhiyarakAnimatedSplash({super.key});

  @override
  State<GhiyarakAnimatedSplash> createState() => _GhiyarakAnimatedSplashState();
}

class _GhiyarakAnimatedSplashState extends State<GhiyarakAnimatedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
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
                  width: 185,
                  height: 185,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1) الترس
                      Opacity(
                        opacity: gearT,
                        child: Transform.rotate(
                          angle: -math.pi * (1 - gearT),
                          child: Transform.scale(
                            scale: 0.4 + 0.6 * gearT,
                            child: Image.asset('assets/gear.png', width: 175, height: 175),
                          ),
                        ),
                      ),
                      // 2) الحلقة
                      Opacity(
                        opacity: ringT,
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * ringT,
                          child: Image.asset('assets/ring.png', width: 175, height: 175),
                        ),
                      ),
                      // 3) المفتاح البرتقالي
                      Opacity(
                        opacity: wrenchT.clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: (-140 * math.pi / 180) * (1 - wrenchT),
                          child: Transform.scale(
                            scale: (0.2 + 0.8 * wrenchT).clamp(0.01, 1.3),
                            child: Image.asset('assets/wrench.png', width: 175, height: 175),
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                      ),
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
                      style: TextStyle(
                        color: Color(0xFF9AA4B4),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
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

class AnimatedCounter extends StatelessWidget {
  final int value;
  final String suffix;
  final TextStyle? style;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.suffix = '',
    this.style,
  });

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

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 380),
  });

  @override
  Widget build(BuildContext context) {
    final delay = (index * 45).clamp(0, 320);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: duration.inMilliseconds + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
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
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
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
            builder: (_, __) {
              return Transform.scale(
                scale: 0.6 + (_controller.value * 1.1),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: (1 - _controller.value) * 0.35),
                  ),
                ),
              );
            },
          ),
          Icon(Icons.location_on, color: widget.color, size: 38),
        ],
      ),
    );
  }
}