import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();
  factory NotificationsService() => instance;

  final SupabaseClient _db = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  bool _localInitDone = false;
  StreamSubscription<List<Map<String, dynamic>>>? _globalSub;
  String? _listeningUserId;
  final Set<String> _shownNotifIds = {};
  bool _initialLoadDone = false;
  OverlayEntry? _activeOverlay;

  bool get _supportsSystemNotifications =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initLocalNotifications() async {
    if (_localInitDone || !_supportsSystemNotifications) {
      return;
    }
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _localPlugin.initialize(
        settings:
            const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _localPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _localInitDone = true;
    } catch (_) {}
  }

  Future<void> showPhoneHeadUpNotification({
    required String id,
    required String title,
    required String body,
    BuildContext? context,
  }) async {
    if (_supportsSystemNotifications) {
      await initLocalNotifications();
      try {
        const androidDetails = AndroidNotificationDetails(
          'ghyarak_high_channel',
          'إشعارات غيارك',
          channelDescription: 'إشعارات الطلبات والمواعيد والخصومات',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
        );
        await _localPlugin.show(
          id: id.hashCode,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
              android: androidDetails, iOS: iosDetails),
        );
      } catch (_) {}
    }

    if (context != null && context.mounted) {
      showTopDropBanner(context, title: title, body: body);
    }
  }

  void showTopDropBanner(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    try {
      _activeOverlay?.remove();
      _activeOverlay = null;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        return;
      }
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) => _TopNotificationDropBanner(
          title: title,
          body: body,
          onDismiss: () {
            if (_activeOverlay == entry) {
              _activeOverlay = null;
            }
            if (entry.mounted) {
              entry.remove();
            }
          },
        ),
      );
      _activeOverlay = entry;
      overlay.insert(entry);
    } catch (_) {}
  }

  void startGlobalListener(BuildContext context) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      stopGlobalListener();
      return;
    }
    if (_listeningUserId == uid && _globalSub != null) {
      return;
    }
    stopGlobalListener();
    _listeningUserId = uid;
    _initialLoadDone = false;
    initLocalNotifications();

    _globalSub = _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .listen((rows) {
          if (!_initialLoadDone) {
            for (final r in rows) {
              final id = r['id'] as String?;
              if (id != null) {
                _shownNotifIds.add(id);
              }
            }
            _initialLoadDone = true;
            return;
          }

          for (final r in rows) {
            final id = r['id'] as String?;
            final isRead = r['is_read'] == true;
            if (id == null || isRead || _shownNotifIds.contains(id)) {
              continue;
            }
            _shownNotifIds.add(id);
            showPhoneHeadUpNotification(
              id: id,
              title: (r['title'] as String?) ?? 'إشعار جديد',
              body: (r['body'] as String?) ?? '',
              context: context.mounted ? context : null,
            );
          }
        }, onError: (_) {});
  }

  void stopGlobalListener() {
    _globalSub?.cancel();
    _globalSub = null;
    _listeningUserId = null;
    _initialLoadDone = false;
  }

  Future<void> sendNotification({
    required String targetUserId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) async {
    await _db.from('notifications').insert({
      'user_id': targetUserId,
      'title': title,
      'body': body,
      'type': type,
      'reference_id': referenceId,
    });
  }

  Future<int> sendBroadcastNotification({
    required String title,
    required String body,
    required String
        targetRole, // 'all' | 'user' | 'merchant' | 'mechanic' | 'towing' | 'customer_pro'
    String type = 'promo',
    String? referenceId,
  }) async {
    var query = _db.from('customers').select('id, role, subscription_plan');
    final rows = await query;
    final matched = rows.where((u) {
      if (targetRole == 'all') {
        return true;
      }
      if (targetRole == 'customer_pro') {
        return u['subscription_plan'] == 'customer_pro';
      }
      return u['role'] == targetRole;
    }).toList();

    if (matched.isEmpty) {
      return 0;
    }

    final payload = matched
        .map((u) => {
              'user_id': u['id'],
              'title': title,
              'body': body,
              'type': type,
              'reference_id': referenceId,
            })
        .toList();

    await _db.from('notifications').insert(payload);
    return payload.length;
  }

  Stream<List<Map<String, dynamic>>> streamMyNotifications() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return const Stream.empty();
    }
    return _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false);
  }

  Future<void> markAsRead(String notifId) async {
    await _db.from('notifications').update({'is_read': true}).eq('id', notifId);
  }

  Future<void> markAllAsRead() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      return;
    }
    await _db
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  void openNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: streamMyNotifications(),
        builder: (ctx, snap) {
          final list = snap.data ?? [];
          return Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإشعارات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (list.any((n) => n['is_read'] != true))
                      TextButton(
                        onPressed: markAllAsRead,
                        child: const Text(
                          'تحديد الكل كمقروء',
                          style:
                              TextStyle(color: AppColors.orange, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'لا توجد إشعارات حالياً',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = list[i];
                        final read = n['is_read'] == true;
                        final isPromo =
                            n['type'] == 'promo' || n['type'] == 'discount';
                        return Material(
                          color: Colors.white,
                          child: ListTile(
                            tileColor: read
                                ? Colors.white
                                : AppColors.orangeLight.withValues(alpha: 0.45),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            leading: CircleAvatar(
                              backgroundColor: isPromo
                                  ? AppColors.orangeLight
                                  : (read
                                      ? AppColors.background
                                      : AppColors.orangeLight),
                              child: Icon(
                                isPromo
                                    ? Icons.local_offer
                                    : Icons.notifications_active,
                                color: read
                                    ? AppColors.textSecondary
                                    : AppColors.orange,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              n['title'] ?? '',
                              style: TextStyle(
                                fontWeight:
                                    read ? FontWeight.normal : FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              n['body'] ?? '',
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                            ),
                            onTap: () => markAsRead(n['id']),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TopNotificationDropBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onDismiss;

  const _TopNotificationDropBanner({
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationDropBanner> createState() =>
      _TopNotificationDropBannerState();
}

class _TopNotificationDropBannerState extends State<_TopNotificationDropBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 4), _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) {
      return;
    }
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.white,
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _close,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.orange, width: 1.2),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.orangeLight,
                    child: Icon(Icons.notifications_active,
                        color: AppColors.orange, size: 20),
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
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: _close,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationBellButton extends StatefulWidget {
  final Color iconColor;
  const NotificationBellButton({super.key, this.iconColor = Colors.white});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _service = NotificationsService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _service.startGlobalListener(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamMyNotifications(),
      builder: (context, snap) {
        final list = snap.data ?? [];
        final unreadCount = list.where((n) => n['is_read'] != true).length;

        return IconButton(
          onPressed: () => _service.openNotificationsSheet(context),
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            child: Icon(Icons.notifications_none, color: widget.iconColor),
          ),
        );
      },
    );
  }
}
