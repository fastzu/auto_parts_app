import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';

/// مفتاح التنقل العام لتمكين إظهار الإشعارات والتنبيهات من الأعلى من أي مكان في التطبيق
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

enum AppToastType {
  success,
  error,
  warning,
  info,
  notification,
  chat,
}

class AppTopToast {
  AppTopToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    try {
      _currentEntry?.remove();
    } catch (_) {}
    _currentEntry = null;
  }

  static void success(
    String message, {
    String title = 'تمت العملية بنجاح',
    BuildContext? context,
    Duration duration = const Duration(seconds: 3),
  }) {
    HapticFeedback.lightImpact();
    show(
      title: title,
      message: message,
      type: AppToastType.success,
      context: context,
      duration: duration,
    );
  }

  static void error(
    String message, {
    String title = 'تعذر إتمام العملية',
    BuildContext? context,
    Duration duration = const Duration(seconds: 4),
  }) {
    HapticFeedback.mediumImpact();
    show(
      title: title,
      message: message,
      type: AppToastType.error,
      context: context,
      duration: duration,
    );
  }

  static void warning(
    String message, {
    String title = 'تنبيه',
    BuildContext? context,
    Duration duration = const Duration(seconds: 4),
  }) {
    HapticFeedback.selectionClick();
    show(
      title: title,
      message: message,
      type: AppToastType.warning,
      context: context,
      duration: duration,
    );
  }

  static void info(
    String message, {
    String title = 'معلومة',
    BuildContext? context,
    Duration duration = const Duration(seconds: 3),
  }) {
    HapticFeedback.selectionClick();
    show(
      title: title,
      message: message,
      type: AppToastType.info,
      context: context,
      duration: duration,
    );
  }

  static void notification({
    required String title,
    required String body,
    bool isChat = false,
    VoidCallback? onTap,
    BuildContext? context,
    Duration duration = const Duration(seconds: 4),
  }) {
    HapticFeedback.mediumImpact();
    show(
      title: title,
      message: body,
      type: isChat ? AppToastType.chat : AppToastType.notification,
      onTap: onTap,
      context: context,
      duration: duration,
    );
  }

  static void show({
    required String title,
    required String message,
    required AppToastType type,
    BuildContext? context,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    OverlayState? overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null && context != null) {
      overlay = Overlay.maybeOf(context, rootOverlay: true);
    }
    if (overlay == null) return;

    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToastOverlayWidget(
        title: title,
        message: message,
        type: type,
        duration: duration,
        onTap: onTap,
        onDismissed: () {
          if (_currentEntry == entry) {
            dismiss();
          } else {
            try {
              entry.remove();
            } catch (_) {}
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _TopToastOverlayWidget extends StatefulWidget {
  final String title;
  final String message;
  final AppToastType type;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDismissed;

  const _TopToastOverlayWidget({
    required this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
    this.onTap,
  });

  @override
  State<_TopToastOverlayWidget> createState() => _TopToastOverlayWidgetState();
}

class _TopToastOverlayWidgetState extends State<_TopToastOverlayWidget>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final AnimationController _progressCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _fadeAnim = CurvedAnimation(
      parent: _slideCtrl,
      curve: Curves.easeOut,
    );

    _progressCtrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _close();
        }
      });

    _slideCtrl.forward();
    _progressCtrl.forward();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    try {
      await _slideCtrl.reverse();
    } catch (_) {}
    widget.onDismissed();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  ({
    Color bg,
    Color accent,
    Color border,
    IconData icon,
  }) _styleFor(AppToastType type) {
    return switch (type) {
      AppToastType.success => (
          bg: const Color(0xFF0F291E),
          accent: const Color(0xFF22C55E),
          border: const Color(0xFF22C55E).withValues(alpha: 0.45),
          icon: Icons.check_circle_rounded,
        ),
      AppToastType.error => (
          bg: const Color(0xFF2B1215),
          accent: const Color(0xFFEF4444),
          border: const Color(0xFFEF4444).withValues(alpha: 0.5),
          icon: Icons.error_rounded,
        ),
      AppToastType.warning => (
          bg: const Color(0xFF2B1F0F),
          accent: const Color(0xFFF59E0B),
          border: const Color(0xFFF59E0B).withValues(alpha: 0.5),
          icon: Icons.warning_amber_rounded,
        ),
      AppToastType.info => (
          bg: AppColors.navy,
          accent: const Color(0xFF38BDF8),
          border: const Color(0xFF38BDF8).withValues(alpha: 0.45),
          icon: Icons.info_rounded,
        ),
      AppToastType.chat => (
          bg: AppColors.navy,
          accent: const Color(0xFF38BDF8),
          border: const Color(0xFF38BDF8).withValues(alpha: 0.55),
          icon: Icons.chat_bubble_rounded,
        ),
      AppToastType.notification => (
          bg: AppColors.navy,
          accent: AppColors.orange,
          border: AppColors.orange.withValues(alpha: 0.65),
          icon: Icons.notifications_active_rounded,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(widget.type);
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      left: 14,
      right: 14,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Colors.transparent,
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismissed(),
                child: GestureDetector(
                  onTap: () {
                    final cb = widget.onTap;
                    _close();
                    cb?.call();
                  },
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: style.bg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: style.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: style.accent.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: style.accent.withValues(alpha: 0.55),
                                  ),
                                ),
                                child: Icon(
                                  style.icon,
                                  color: style.accent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    if (widget.message.trim().isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.message,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontSize: 12.2,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: _close,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: Colors.white.withValues(alpha: 0.65),
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // شريط التقدم السفلي الرقيق
                        AnimatedBuilder(
                          animation: _progressCtrl,
                          builder: (_, __) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FractionallySizedBox(
                              widthFactor:
                                  (1.0 - _progressCtrl.value).clamp(0.0, 1.0),
                              child: Container(
                                height: 3,
                                color: style.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}