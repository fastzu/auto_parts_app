import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';

Route<T> animatedRoute<T>(Widget page) {
  if (kIsWeb) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 110),
      reverseTransitionDuration: const Duration(milliseconds: 90),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class GoogleLogoIcon extends StatelessWidget {
  final double size;
  const GoogleLogoIcon({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.19;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -2.55, 1.85, false, paint);

    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.55, 1.18, false, paint);

    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.72, 1.83, false, paint);

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.08, 0.85, false, paint);

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(Offset(w * 0.50, h * 0.50), Offset(w * 0.95, h * 0.50), barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PulseBlink extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const PulseBlink({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 950),
  });

  @override
  State<PulseBlink> createState() => _PulseBlinkState();
}

class _PulseBlinkState extends State<PulseBlink> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final v = Curves.easeInOut.transform(_ctrl.value);
          return Opacity(
            opacity: 0.62 + (0.38 * v),
            child: Transform.scale(scale: 0.98 + (0.04 * v), child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}

enum DashboardPeriod { month1, months3, months6, custom }

class DateRangeFilterBar extends StatelessWidget {
  final DashboardPeriod period;
  final DateTimeRange? customRange;
  final void Function(DashboardPeriod period, DateTimeRange? customRange) onChanged;

  const DateRangeFilterBar({
    super.key,
    required this.period,
    required this.customRange,
    required this.onChanged,
  });

  static DateTimeRange resolveRange(DashboardPeriod period, DateTimeRange? customRange) {
    final now = DateTime.now();
    return switch (period) {
      DashboardPeriod.month1 =>
        DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      DashboardPeriod.months3 =>
        DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now),
      DashboardPeriod.months6 =>
        DateTimeRange(start: now.subtract(const Duration(days: 180)), end: now),
      DashboardPeriod.custom =>
        customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    };
  }

  @override
  Widget build(BuildContext context) {
    String customLabel = 'فترة مخصصة';
    if (period == DashboardPeriod.custom && customRange != null) {
      final s = customRange!.start;
      final e = customRange!.end;
      customLabel = '${s.month}/${s.day} - ${e.month}/${e.day}';
    }

    final items = [
      (DashboardPeriod.month1, 'آخر شهر'),
      (DashboardPeriod.months3, 'آخر 3 أشهر'),
      (DashboardPeriod.months6, 'آخر 6 أشهر'),
      (DashboardPeriod.custom, customLabel),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final active = period == item.$1;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(item.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              selected: active,
              selectedColor: AppColors.navy,
              labelStyle: TextStyle(color: active ? Colors.white : AppColors.textPrimary),
              onSelected: (_) async {
                if (item.$1 == DashboardPeriod.custom) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: customRange ??
                        DateTimeRange(
                          start: DateTime.now().subtract(const Duration(days: 30)),
                          end: DateTime.now(),
                        ),
                  );
                  if (picked != null) {
                    onChanged(DashboardPeriod.custom, picked);
                  }
                } else {
                  onChanged(item.$1, customRange);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class InteractiveAnimatedChart extends StatefulWidget {
  final String title;
  final List<({String label, double value})> data;
  final String unit;

  const InteractiveAnimatedChart({
    super.key,
    required this.title,
    required this.data,
    this.unit = '',
  });

  @override
  State<InteractiveAnimatedChart> createState() => _InteractiveAnimatedChartState();
}

class _InteractiveAnimatedChartState extends State<InteractiveAnimatedChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final maxVal = widget.data.fold<double>(1.0, (m, e) => e.value > m ? e.value : m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              if (_hoveredIndex != null && _hoveredIndex! < widget.data.length)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.data[_hoveredIndex!].label}: ${widget.data[_hoveredIndex!].value.toStringAsFixed(0)} ${widget.unit}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 165,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(widget.data.length, (i) {
                final item = widget.data[i];
                final isActive = _hoveredIndex == i;
                final ratio = (item.value / maxVal).clamp(0.06, 1.0);

                return Expanded(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hoveredIndex = i),
                    onExit: (_) => setState(() => _hoveredIndex = null),
                    child: GestureDetector(
                      onTap: () {
                        if (!kIsWeb) HapticFeedback.selectionClick();
                        setState(() => _hoveredIndex = isActive ? null : i);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedOpacity(
                              opacity: isActive ? 1.0 : 0.65,
                              duration: const Duration(milliseconds: 140),
                              child: Text(
                                item.value.toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                  color: isActive ? AppColors.orange : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: ratio),
                              duration: Duration(
                                milliseconds: kIsWeb ? 260 : 550 + (i * 60),
                              ),
                              curve: Curves.easeOutCubic,
                              builder: (_, hRatio, __) => AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: (105 * hRatio) + (isActive ? 6 : 0),
                                width: isActive ? 28 : 22,
                                decoration: BoxDecoration(
                                  color: isActive ? AppColors.orange : AppColors.navy,
                                  borderRadius:
                                      const BorderRadius.vertical(top: Radius.circular(8)),
                                  boxShadow: isActive
                                      ? [
                                          BoxShadow(
                                            color: AppColors.orange.withValues(alpha: 0.35),
                                            blurRadius: 8,
                                          )
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                color: isActive ? AppColors.navy : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
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
        if (!kIsWeb) HapticFeedback.lightImpact();
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
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: kIsWeb ? 1100 : 2400),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(Duration(milliseconds: kIsWeb ? 150 : 600), () {
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
        child: RepaintBoundary(
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
                        if (ringT > 0)
                          ClipPath(
                            clipper: _RingSweepClipper(ringT),
                            child: Image.asset('assets/ring.png', width: 195, height: 195),
                          ),
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
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 44,
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
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
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
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 95,
                    decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(12)),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 14,
                    width: 100,
                    decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 11,
                    width: 70,
                    decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
    if (kIsWeb) {
      return Text('$value$suffix', style: style);
    }
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
    if (kIsWeb) return child;

    final delay = (index * 45).clamp(0, 320);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: duration.inMilliseconds + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, 16 * (1 - value)), child: child),
      ),
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
    if (kIsWeb) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.child,
        ),
      );
    }

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Transform.scale(
                scale: 0.6 + (_controller.value * 1.1),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: (1 - _controller.value) * 0.35),
                  ),
                ),
              ),
            ),
            Icon(Icons.location_on, color: widget.color, size: 38),
          ],
        ),
      ),
    );
  }
}

/// شريط تتبع حي لسيارة / ونش متحركة على خط الطريق حسب تقدم الـ GPS
class GpsCarProgressTrack extends StatelessWidget {
  final double progress;
  final bool isWinch;
  final String? distanceLabel;
  final bool isArrived;
  final Color? trackColor;
  final Color? activeColor;
  final Color? labelColor;
  final String startLabel;
  final String endLabel;

  const GpsCarProgressTrack({
    super.key,
    required this.progress,
    this.isWinch = false,
    this.distanceLabel,
    this.isArrived = false,
    this.trackColor,
    this.activeColor,
    this.labelColor,
    this.startLabel = 'الانطلاق',
    this.endLabel = 'الوجهة',
  });

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = isArrived ? 1.0 : progress.clamp(0.04, 1.0);
    final fillColor = isArrived ? AppColors.success : (activeColor ?? AppColors.orange);
    final bgTrack = trackColor ?? Colors.white24;
    final txtColor = labelColor ?? Colors.white70;
    final dir = Directionality.of(context);
    final isRtl = dir == TextDirection.rtl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const carSize = 30.0;
              const endPinSize = 22.0;
              final totalW = constraints.maxWidth;
              final usableW = (totalW - carSize).clamp(1.0, double.infinity);

              return TweenAnimationBuilder<double>(
                tween: Tween<double>(end: effectiveProgress),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (_, animVal, __) {
                  final val = animVal.clamp(0.0, 1.0);
                  final carStart = usableW * val;
                  final lineFillWidth = (carStart + (carSize / 2)).clamp(0.0, totalW);

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // خط الطريق الخلفي
                      Positioned(
                        left: 6,
                        right: 6,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: bgTrack,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      // الجزء المقطوع من الطريق
                      Positioned.directional(
                        textDirection: dir,
                        start: 6,
                        child: Container(
                          width: (lineFillWidth - 6).clamp(0.0, (totalW - 12).clamp(0.0, totalW)),
                          height: 6,
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      // نقطة البداية
                      Positioned.directional(
                        textDirection: dir,
                        start: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: fillColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                      // نقطة الوصول (الوجهة)
                      Positioned.directional(
                        textDirection: dir,
                        end: 0,
                        child: Container(
                          width: endPinSize,
                          height: endPinSize,
                          decoration: BoxDecoration(
                            color: isArrived ? AppColors.success : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isArrived ? Colors.white : fillColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            isArrived ? Icons.check : Icons.location_on,
                            size: 13,
                            color: isArrived ? Colors.white : fillColor,
                          ),
                        ),
                      ),
                      // السيارة / الونش المتحركة على الخط حسب GPS
                      Positioned.directional(
                        textDirection: dir,
                        start: carStart,
                        child: Container(
                          width: carSize,
                          height: carSize,
                          decoration: BoxDecoration(
                            color: fillColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: fillColor.withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Transform.flip(
                            flipX: isRtl && isWinch,
                            child: Icon(
                              isWinch ? Icons.local_shipping_rounded : Icons.directions_car_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(startLabel, style: TextStyle(fontSize: 10, color: txtColor)),
            if (distanceLabel != null && distanceLabel!.isNotEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    distanceLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isArrived ? AppColors.success : fillColor,
                    ),
                  ),
                ),
              ),
            Text(
              isArrived ? 'تم الوصول ✓' : endLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isArrived ? FontWeight.bold : FontWeight.normal,
                color: isArrived ? AppColors.success : txtColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}