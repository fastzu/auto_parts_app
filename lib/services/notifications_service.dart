import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';
import '../theme/app_theme.dart';

class NotificationsService {
  NotificationsService._internal();
  static final NotificationsService instance = NotificationsService._internal();
  factory NotificationsService() => instance;

  final SupabaseClient _db = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// عدادات فورية موحدة لجميع الشاشات (الجرس + أيقونة الدردشة)
  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadMessagesCount = ValueNotifier<int>(0);

  /// معرّف الطرف الآخر في المحادثة المفتوحة حالياً (حتى لا يظهر إشعار مكرر أثناء فتح نفس الدردشة)
  String? activeChatOtherUserId;

  bool _initialized = false;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _msgChannel;
  Timer? _fallbackPollTimer;
  String? _listeningUserId;
  final Set<String> _shownIds = {};
  final Map<String, String> _senderNameCache = {};

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

  /// حفظ Device Push Token (جاهز للربط المباشر مع APNs/FCM عند تفعيل حساب المطور)
  Future<void> registerPushToken(String token) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || token.trim().isEmpty) return;
    final platform = kIsWeb
        ? 'web'
        : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
    try {
      await _db.from('customers').update({
        'device_push_token': token.trim(),
        'device_platform': platform,
      }).eq('id', uid);
    } catch (_) {}
  }

  /// إظهار إشعار حقيقي على الهاتف (Banner + صوت + اهتزاز + مركز الإشعارات)
  Future<void> showLocalPhoneNotification({
    required String title,
    required String body,
    String? dedupeKey,
  }) async {
    if (!_isMobileNative) return;
    if (dedupeKey != null) {
      if (_shownIds.contains(dedupeKey)) return;
      _shownIds.add(dedupeKey);
      if (_shownIds.length > 300) {
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

  Future<String> _resolveSenderName(String? senderId) async {
    if (senderId == null || senderId.isEmpty) return 'مستخدم غيارك';
    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }
    try {
      final row = await _db
          .from('customers')
          .select('full_name, username')
          .eq('id', senderId)
          .maybeSingle();
      final name = (row?['full_name'] as String?)?.trim().isNotEmpty == true
          ? (row!['full_name'] as String).trim()
          : ((row?['username'] as String?)?.trim().isNotEmpty == true
              ? (row!['username'] as String).trim()
              : 'مستخدم غيارك');
      _senderNameCache[senderId] = name;
      return name;
    } catch (_) {
      return 'مستخدم غيارك';
    }
  }

  /// تشغيل المستمع العام (Realtime + فحص احتياطي كل 8 ثوانٍ) للإشعارات والرسائل
  Future<void> startRealtimeListener([String? explicitUserId]) async {
    final uid = explicitUserId ?? _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    if (_listeningUserId == uid && _notifChannel != null && _msgChannel != null) {
      await refreshUnreadCounts();
      return;
    }

    await stopRealtimeListener();
    await init();
    _listeningUserId = uid;

    // تسجيل المعرفات الموجودة مسبقاً حتى لا تتكرر الإشعارات القديمة عند فتح التطبيق
    await _seedExistingIds(uid);
    await refreshUnreadCounts();

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
            refreshUnreadCounts();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => refreshUnreadCounts(),
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
          callback: (payload) async {
            final row = payload.newRecord;
            final id = (row['id'] ?? '').toString();
            final senderId = row['sender_id'] as String?;
            final msg = (row['message'] as String?) ?? 'لديك رسالة جديدة';

            // إظهار إشعار على الهاتف دائماً ما لم يكن المستخدم داخل نفس المحادثة حالياً
            if (senderId == null || senderId != activeChatOtherUserId) {
              final senderName = await _resolveSenderName(senderId);
              await showLocalPhoneNotification(
                title: 'رسالة جديدة من $senderName 💬',
                body: msg,
                dedupeKey: id.isNotEmpty ? 'msg_$id' : null,
              );
            }
            await refreshUnreadCounts();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: uid,
          ),
          callback: (_) => refreshUnreadCounts(),
        )
        .subscribe();

    // فحص احتياطي كل 8 ثوانٍ يضمن وصول كل الإشعارات والرسائل على الهاتف حتى لو انقطع Realtime
    _fallbackPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _pollUnseenUpdates(uid),
    );
  }

  Future<void> _seedExistingIds(String uid) async {
    try {
      final results = await Future.wait([
        _db
            .from('notifications')
            .select('id')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(40),
        _db
            .from('messages')
            .select('id')
            .eq('receiver_id', uid)
            .order('created_at', ascending: false)
            .limit(40),
      ]);
      for (final n in (results[0] as List)) {
        final id = (n['id'] ?? '').toString();
        if (id.isNotEmpty) _shownIds.add('notif_$id');
      }
      for (final m in (results[1] as List)) {
        final id = (m['id'] ?? '').toString();
        if (id.isNotEmpty) _shownIds.add('msg_$id');
      }
    } catch (_) {}
  }

  Future<void> _pollUnseenUpdates(String uid) async {
    if (_listeningUserId != uid) return;
    try {
      final notifs = await _db
          .from('notifications')
          .select('id, title, body, is_read')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(15);

      for (final raw in notifs) {
        final id = (raw['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final key = 'notif_$id';
        if (!_shownIds.contains(key) && raw['is_read'] != true) {
          await showLocalPhoneNotification(
            title: (raw['title'] as String?) ?? 'إشعار جديد — غيارك',
            body: (raw['body'] as String?) ?? '',
            dedupeKey: key,
          );
        }
      }

      final msgs = await _db
          .from('messages')
          .select('id, sender_id, message, is_read')
          .eq('receiver_id', uid)
          .order('created_at', ascending: false)
          .limit(15);

      for (final raw in msgs) {
        final id = (raw['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final key = 'msg_$id';
        final senderId = raw['sender_id'] as String?;
        if (!_shownIds.contains(key) && raw['is_read'] != true) {
          if (senderId == null || senderId != activeChatOtherUserId) {
            final senderName = await _resolveSenderName(senderId);
            await showLocalPhoneNotification(
              title: 'رسالة جديدة من $senderName 💬',
              body: (raw['message'] as String?) ?? 'لديك رسالة جديدة',
              dedupeKey: key,
            );
          } else {
            _shownIds.add(key);
          }
        }
      }

      await refreshUnreadCounts();
    } catch (_) {}
  }

  /// تحديث عدّادات غير المقروءة (الجرس + أيقونة الدردشة)
  Future<void> refreshUnreadCounts() async {
    final uid = _listeningUserId ?? _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      unreadNotificationsCount.value = 0;
      unreadMessagesCount.value = 0;
      return;
    }

    try {
      final unreadNotifs = await _db
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false);
      unreadNotificationsCount.value = (unreadNotifs as List).length;
    } catch (_) {}

    try {
      final unreadMsgs = await _db
          .from('messages')
          .select('id')
          .eq('receiver_id', uid)
          .eq('is_read', false);
      unreadMessagesCount.value = (unreadMsgs as List).length;
    } catch (_) {}
  }

  /// تعليم جميع رسائل مرسل معيّن كمقروءة فور فتح المحادثة
  Future<void> markConversationAsRead(String otherUserId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      await _db
          .from('messages')
          .update({'is_read': true})
          .eq('receiver_id', uid)
          .eq('sender_id', otherUserId)
          .eq('is_read', false);
      await refreshUnreadCounts();
    } catch (_) {}
  }

  Future<void> stopRealtimeListener() async {
    _listeningUserId = null;
    activeChatOtherUserId = null;
    unreadNotificationsCount.value = 0;
    unreadMessagesCount.value = 0;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
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

    // إرسال Push خارجي (APNs / FCM) عند تفعيل remotePushEnabled بعد اشتراك حساب المطور
    if (EnvConfig.remotePushEnabled) {
      try {
        await _db.functions.invoke(
          'send-push-notification',
          body: {
            'target_user_id': targetUserId,
            'title': title,
            'body': body,
            'type': type,
            'reference_id': referenceId,
          },
        );
      } catch (_) {}
    }
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
    if (targetUserId != null && targetUserId.trim().isNotEmpty) {
      await sendNotification(
        targetUserId: targetUserId.trim(),
        title: title,
        body: body,
        type: type,
        referenceId: referenceId,
      );
      return 1;
    }

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
        .update({'is_read': true})
        .eq('id', notifId);
    await refreshUnreadCounts();
  }

  Future<void> markAllNotificationsAsRead() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _db
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
      unreadNotificationsCount.value = 0;
    } catch (_) {}
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
          final hasUnread = list.any((n) => n['is_read'] != true);
          return Padding(
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (hasUnread)
                      TextButton(
                        onPressed: markAllNotificationsAsRead,
                        child: const Text(
                          'تحديد الكل كمقروء',
                          style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
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
                            (n['title'] as String?) ?? '',
                            style: TextStyle(
                              fontWeight:
                                  read ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Text((n['body'] as String?) ?? ''),
                          onTap: () => markAsRead(n['id'] as String),
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

/// زر جرس الإشعارات مع الشارة الحمراء وتنبيه الهاتف الفوري
class NotificationBellButton extends StatefulWidget {
  final Color iconColor;
  const NotificationBellButton({super.key, this.iconColor = Colors.white});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _service = NotificationsService.instance;
  late final Stream<List<Map<String, dynamic>>> _stream;
  String? _lastAlertId;

  @override
  void initState() {
    super.initState();
    _stream = _service.streamMyNotifications();
    _service.refreshUnreadCounts();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
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

        return ValueListenableBuilder<int>(
          valueListenable: _service.unreadNotificationsCount,
          builder: (_, notifierCount, __) {
            final count = snap.hasData ? unreadList.length : notifierCount;
            return IconButton(
              tooltip: 'الإشعارات',
              onPressed: () => _service.openNotificationsSheet(context),
              icon: Badge(
                isLabelVisible: count > 0,
                backgroundColor: Colors.red,
                label: Text('$count'),
                child: Icon(Icons.notifications_none, color: widget.iconColor),
              ),
            );
          },
        );
      },
    );
  }
}

/// زر أيقونة الدردشة مع الشارة الحمراء بعدد الرسائل غير المقروءة (مثل الجرس تماماً)
class ChatBadgeButton extends StatefulWidget {
  final Color iconColor;
  final VoidCallback onPressed;
  final double iconSize;

  const ChatBadgeButton({
    super.key,
    this.iconColor = AppColors.navy,
    required this.onPressed,
    this.iconSize = 23,
  });

  @override
  State<ChatBadgeButton> createState() => _ChatBadgeButtonState();
}

class _ChatBadgeButtonState extends State<ChatBadgeButton> {
  final _service = NotificationsService.instance;

  @override
  void initState() {
    super.initState();
    _service.refreshUnreadCounts();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _service.unreadMessagesCount,
      builder: (_, count, __) {
        return IconButton(
          tooltip: 'الدردشات',
          onPressed: widget.onPressed,
          icon: Badge(
            isLabelVisible: count > 0,
            backgroundColor: Colors.red,
            label: Text(count > 99 ? '99+' : '$count'),
            child: Icon(
              Icons.chat_bubble_outline,
              color: widget.iconColor,
              size: widget.iconSize,
            ),
          ),
        );
      },
    );
  }
}