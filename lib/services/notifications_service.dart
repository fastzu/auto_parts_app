import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show appNavigatorKey;
import '../theme/app_theme.dart';

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();
  factory NotificationsService() => instance;

  static const String _channelId = 'ghayarak_heads_up_v3';
  static const String _channelName = 'إشعارات غيارك الفورية';

  final SupabaseClient _db = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  StreamSubscription<List<Map<String, dynamic>>>? _globalSub;
  String? _listeningUserId;
  final Set<String> _seenIds = {};
  bool _initialSnapshotLoaded = false;
  OverlayEntry? _activeBanner;

  Future<void> initLocalNotifications() async {
    if (_initialized || kIsWeb) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifications.initialize(settings: initSettings);

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'تنبيهات الطلبات والمواعيد والعروض الفورية من غيارك',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        await androidPlugin.createNotificationChannel(channel);
      }

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      _initialized = true;
    } catch (_) {}
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) {
      await initLocalNotifications();
    }
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'تنبيهات الطلبات والمواعيد والعروض الفورية من غيارك',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        ticker: 'غيارك',
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
        presentBadge: true,
        presentList: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  void showTopBanner({
    BuildContext? context,
    required String title,
    required String body,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay ??
        (context != null ? Overlay.maybeOf(context, rootOverlay: true) : null);
    if (overlay == null) return;

    _activeBanner?.remove();
    _activeBanner = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopNotificationDropBanner(
        title: title,
        body: body,
        onDismiss: () {
          if (_activeBanner == entry) {
            entry.remove();
            _activeBanner = null;
          }
        },
      ),
    );
    _activeBanner = entry;
    overlay.insert(entry);
  }

  void startGlobalListener([BuildContext? context]) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    if (_listeningUserId == uid && _globalSub != null) return;

    stopGlobalListener();
    _listeningUserId = uid;
    _seenIds.clear();
    _initialSnapshotLoaded = false;

    initLocalNotifications();

    _globalSub = _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!_initialSnapshotLoaded) {
              for (final r in rows) {
                final id = r['id']?.toString();
                if (id != null) _seenIds.add(id);
              }
              _initialSnapshotLoaded = true;
              return;
            }

            for (final r in rows.reversed) {
              final id = r['id']?.toString();
              if (id == null || _seenIds.contains(id)) continue;
              _seenIds.add(id);
              if (r['is_read'] == true) continue;

              final title = (r['title'] as String?) ?? 'إشعار جديد من غيارك';
              final body = (r['body'] as String?) ?? '';

              // 1) إشعار النظام (ينزل من أعلى الهاتف)
              showLocalNotification(title: title, body: body);

              // 2) بانر علوي داخل التطبيق (أبيض أنيق)
              showTopBanner(context: context, title: title, body: body);
            }
          },
          onError: (_) {},
        );
  }

  void stopGlobalListener() {
    _globalSub?.cancel();
    _globalSub = null;
    _listeningUserId = null;
    _seenIds.clear();
    _initialSnapshotLoaded = false;
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
    String type = 'promo',
    String targetRole = 'all',
    String? targetUserId,
    String? referenceId,
  }) async {
    if (targetUserId != null && targetUserId.isNotEmpty) {
      await sendNotification(
        targetUserId: targetUserId,
        title: title,
        body: body,
        type: type,
        referenceId: referenceId,
      );
      return 1;
    }

    var query = _db.from('customers').select('id');
    if (targetRole != 'all') {
      query = query.eq('role', targetRole);
    }
    final users = List<Map<String, dynamic>>.from(await query);
    if (users.isEmpty) return 0;

    final payloads = users
        .map((u) => {
              'user_id': u['id'],
              'title': title,
              'body': body,
              'type': type,
              'reference_id': referenceId,
            })
        .toList();

    for (var i = 0; i < payloads.length; i += 100) {
      final end = (i + 100 < payloads.length) ? i + 100 : payloads.length;
      await _db.from('notifications').insert(payloads.sublist(i, end));
    }
    return payloads.length;
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
    if (uid == null) return;
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: streamMyNotifications(),
        builder: (ctx, snap) {
          final list = snap.data ?? [];
          final hasUnread = list.any((n) => n['is_read'] != true);
          return Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإشعارات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    if (hasUnread)
                      TextButton(
                        onPressed: markAllAsRead,
                        child: const Text(
                          'تحديد الكل كمقروء',
                          style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 34),
                    child: Center(
                      child: Text(
                        'لا توجد إشعارات حالياً',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (_, i) {
                        final n = list[i];
                        final read = n['is_read'] == true;
                        return Container(
                          color: read
                              ? Colors.white
                              : AppColors.orange.withValues(alpha: 0.06),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: read
                                  ? Colors.grey.shade100
                                  : AppColors.orange.withValues(alpha: 0.14),
                              child: Icon(
                                Icons.notifications_active,
                                size: 20,
                                color: read
                                    ? AppColors.textSecondary
                                    : AppColors.orange,
                              ),
                            ),
                            title: Text(
                              (n['title'] as String?) ?? '',
                              style: TextStyle(
                                color: AppColors.navy,
                                fontWeight:
                                    read ? FontWeight.w500 : FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              (n['body'] as String?) ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => markAsRead(n['id'].toString()),
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
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 4), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
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
    final topPad = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: topPad,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _close,
            onVerticalDragEnd: (_) => _close(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.orange.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active,
                      color: AppColors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                            color: AppColors.navy,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        if (widget.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.close, size: 16, color: Colors.black38),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationBellButton extends StatelessWidget {
  final Color iconColor;
  const NotificationBellButton({super.key, this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    final service = NotificationsService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.streamMyNotifications(),
      builder: (context, snap) {
        final list = snap.data ?? [];
        final unreadCount = list.where((n) => n['is_read'] != true).length;

        return IconButton(
          onPressed: () => service.openNotificationsSheet(context),
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            child: Icon(Icons.notifications_none, color: iconColor),
          ),
        );
      },
    );
  }
}