import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class NotificationsService {
  NotificationsService._internal();
  static final NotificationsService instance = NotificationsService._internal();
  factory NotificationsService() => instance;

  final SupabaseClient _db = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _msgChannel;
  String? _listeningUserId;
  final Set<String> _shownIds = {};

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'ghyarak_high_importance',
    'إشعارات غيارك المهمة',
    description: 'تنبيهات الطلبات والمواعيد والطوارئ والرسائل',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  bool get _isMobileNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// تهيئة نظام الإشعارات المحلية على الهاتف وطلب الصلاحيات (iOS & Android)
  Future<void> init() async {
    if (_initialized || !_isMobileNative) {
      _initialized = true;
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    try {
      await _local.initialize(settings: initSettings);

      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_androidChannel);
      await androidPlugin?.requestNotificationsPermission();

      final iosPlugin = _local.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      _initialized = true;
    } catch (_) {}
  }

  /// إظهار إشعار حقيقي في شريط الهاتف (Banner + صوت + اهتزاز)
  Future<void> showLocalPhoneNotification({
    required String title,
    required String body,
    String? dedupeKey,
  }) async {
    if (!_isMobileNative) return;
    if (dedupeKey != null) {
      if (_shownIds.contains(dedupeKey)) return;
      _shownIds.add(dedupeKey);
      if (_shownIds.length > 200) {
        _shownIds.remove(_shownIds.first);
      }
    }

    if (!_initialized) {
      await init();
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    final notifId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    try {
      await _local.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  /// تشغيل مستمع Supabase Realtime العام للإشعارات والرسائل الواردة للمستخدم
  Future<void> startRealtimeListener([String? explicitUserId]) async {
    final uid = explicitUserId ?? _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    if (_listeningUserId == uid && _notifChannel != null) return;

    await stopRealtimeListener();
    await init();
    _listeningUserId = uid;

    _notifChannel = _db
        .channel('user_notifs_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = (row['id'] ?? '').toString();
            final title = (row['title'] as String?) ?? 'إشعار جديد — غيارك';
            final body = (row['body'] as String?) ?? '';
            showLocalPhoneNotification(
              title: title,
              body: body,
              dedupeKey: id.isNotEmpty ? 'notif_$id' : null,
            );
          },
        )
        .subscribe();

    _msgChannel = _db
        .channel('user_msgs_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = (row['id'] ?? '').toString();
            final msg = (row['message'] as String?) ?? 'لديك رسالة جديدة';
            showLocalPhoneNotification(
              title: 'رسالة جديدة في غيارك 💬',
              body: msg,
              dedupeKey: id.isNotEmpty ? 'msg_$id' : null,
            );
          },
        )
        .subscribe();
  }

  Future<void> stopRealtimeListener() async {
    _listeningUserId = null;
    if (_notifChannel != null) {
      try {
        await _db.removeChannel(_notifChannel!);
      } catch (_) {}
      _notifChannel = null;
    }
    if (_msgChannel != null) {
      try {
        await _db.removeChannel(_msgChannel!);
      } catch (_) {}
      _msgChannel = null;
    }
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

  /// إرسال إشعار جماعي حسب الدور أو لمستخدم محدد عبر targetUserId
  Future<int> sendBroadcastNotification({
    required String title,
    required String body,
    String targetRole = 'all',
    String? targetUserId,
    String type = 'broadcast',
    String? referenceId,
  }) async {
    // 1) إذا تم تحديد مستخدم معيّن نرسل له مباشرة
    if (targetUserId != null && targetUserId.trim().isNotEmpty) {
      await _db.from('notifications').insert({
        'user_id': targetUserId.trim(),
        'title': title,
        'body': body,
        'type': type,
        'reference_id': referenceId,
      });
      return 1;
    }

    // 2) إرسال جماعي للكل أو لفئة محددة (merchant / mechanic / towing / user)
    var query = _db.from('customers').select('id');
    if (targetRole != 'all' && targetRole.trim().isNotEmpty) {
      query = query.eq('role', targetRole.trim());
    }
    final rows = await query;
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return 0;

    final inserts = list
        .map(
          (r) => {
            'user_id': r['id'],
            'title': title,
            'body': body,
            'type': type,
            'reference_id': referenceId,
          },
        )
        .toList();

    // إدراج على دفعات لتجنب حدود الحجم
    const chunkSize = 100;
    for (var i = 0; i < inserts.length; i += chunkSize) {
      final end = (i + chunkSize < inserts.length)
          ? i + chunkSize
          : inserts.length;
      await _db.from('notifications').insert(inserts.sublist(i, end));
    }
    return inserts.length;
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
    await _db
        .from('notifications')
        .update({'is_read': true}).eq('id', notifId);
  }

  void openNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: streamMyNotifications(),
        builder: (ctx, snap) {
          final list = snap.data ?? [];
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الإشعارات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('لا توجد إشعارات حالياً')),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, i) {
                        final n = list[i];
                        final read = n['is_read'] == true;
                        return ListTile(
                          leading: Icon(
                            Icons.notifications_active,
                            color: read
                                ? AppColors.textSecondary
                                : AppColors.orange,
                          ),
                          title: Text(
                            n['title'] ?? '',
                            style: TextStyle(
                              fontWeight:
                                  read ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(n['body'] ?? ''),
                          onTap: () => markAsRead(n['id']),
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

class NotificationBellButton extends StatefulWidget {
  final Color iconColor;
  const NotificationBellButton({super.key, this.iconColor = Colors.white});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _service = NotificationsService.instance;
  String? _lastAlertId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamMyNotifications(),
      builder: (context, snap) {
        final list = snap.data ?? [];
        final unreadList = list.where((n) => n['is_read'] != true).toList();
        if (unreadList.isNotEmpty) {
          final newest = unreadList.first;
          final id = newest['id'] as String?;
          if (id != null && _lastAlertId != null && _lastAlertId != id) {
            final title = (newest['title'] as String?) ?? 'إشعار جديد';
            final body = (newest['body'] as String?) ?? '';
            _service.showLocalPhoneNotification(
              title: title,
              body: body,
              dedupeKey: 'notif_$id',
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.orange,
                  content: Text('$title: $body'),
                ),
              );
            });
          }
          _lastAlertId ??= id;
          if (id != null) {
            _lastAlertId = id;
          }
        }

        return IconButton(
          onPressed: () => _service.openNotificationsSheet(context),
          icon: Badge(
            isLabelVisible: unreadList.isNotEmpty,
            label: Text('${unreadList.length}'),
            child: Icon(Icons.notifications_none, color: widget.iconColor),
          ),
        );
      },
    );
  }
}