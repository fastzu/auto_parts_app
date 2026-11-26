import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_toast.dart';

/// معالج رسائل Firebase في الخلفية أو عندما يكون التطبيق مغلقاً بالكامل
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final title = message.notification?.title ??
      (message.data['title'] as String?) ??
      'إشعار جديد — غيارك';
  final body = message.notification?.body ??
      (message.data['body'] as String?) ??
      '';

  if (message.notification == null && title.trim().isNotEmpty) {
    await NotificationsService.instance.showLocalPhoneNotification(
      title: title,
      body: body,
      dedupeKey:
          message.messageId != null ? 'fcm_bg_${message.messageId}' : null,
    );
  }
}

class NotificationsService {
  NotificationsService._internal();
  static final NotificationsService instance = NotificationsService._internal();
  factory NotificationsService() => instance;

  final SupabaseClient _db = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// عدادات الإشعارات والرسائل غير المقروءة للشارات الحمراء في كامل التطبيق
  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadMessagesCount = ValueNotifier<int>(0);

  /// معرّف الطرف المفتوحة محادثته حالياً (لمنع تكرار التنبيه داخل نفس المحادثة)
  String? activeChatOtherUserId;

  bool _initialized = false;
  bool _fcmListenersBound = false;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _msgChannel;
  Timer? _pollTimer;
  StreamSubscription<String>? _tokenRefreshSub;
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

  /// تهيئة الإشعارات المحلية + Firebase Messaging (للخلفية وإغلاق التطبيق)
  Future<void> init() async {
    if (_initialized) return;

    if (!_isMobileNative) {
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
    } catch (_) {}

    await _initFirebaseMessagingSafe();
    _initialized = true;
  }

  Future<void> _initFirebaseMessagingSafe() async {
    if (_fcmListenersBound || !_isMobileNative) return;
    try {
      if (Firebase.apps.isEmpty) return;

      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // السماح لـ iOS بعرض الإشعار بالصوت والبانر حتى والتطبيق مفتوح
      await fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ??
            (message.data['title'] as String?) ??
            'إشعار جديد — غيارك';
        final body = message.notification?.body ??
            (message.data['body'] as String?) ??
            '';
        final type = (message.data['type'] as String?) ?? 'general';
        final refId = (message.data['reference_id'] as String?) ?? '';
        final isChat = type == 'chat';
        final dedupeKey = message.messageId != null
            ? 'fcm_${message.messageId}'
            : 'fcm_${title}_${body.hashCode}';

        if (isChat &&
            activeChatOtherUserId != null &&
            activeChatOtherUserId == refId) {
          refreshUnreadCounts();
          return;
        }

        // إشعار داخلي أنيق ينزل من أعلى الشاشة
        AppTopToast.notification(
          title: title,
          body: body,
          isChat: isChat,
        );

        // على Android نظهر إشعار النظام أيضاً؛ على iOS يعرضه النظام تلقائياً إن كان هناك notification payload
        if (defaultTargetPlatform == TargetPlatform.android ||
            message.notification == null) {
          showLocalPhoneNotification(
            title: title,
            body: body,
            dedupeKey: dedupeKey,
          );
        }

        refreshUnreadCounts();
      });

      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        refreshUnreadCounts();
      });

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = fcm.onRegistered.listen((newToken) {
        registerPushToken(newToken);
      });

      _fcmListenersBound = true;
    } catch (_) {
      // في حال عدم إضافة ملفات Firebase بعد، يواصل التطبيق العمل بشكل طبيعي بدون أخطاء
    }
  }

  Future<void> _syncFcmToken() async {
    if (!_isMobileNative) return;
    try {
      if (Firebase.apps.isEmpty) return;
      await FirebaseMessaging.instance.register();
    } catch (_) {}
  }

  /// حفظ توكن الإشعارات للجهاز في Supabase لإيصال الـ Push والتطبيق مغلق
  Future<void> registerPushToken(String token) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || token.trim().isEmpty) return;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'other',
    };
    try {
      await _db.from('customers').update({
        'device_push_token': token.trim(),
        'device_platform': platform,
      }).eq('id', uid);
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

  /// تشغيل مستمع Supabase Realtime + Polling الاحتياطي + مزامنة FCM Token
  Future<void> startRealtimeListener([String? explicitUserId]) async {
    final uid = explicitUserId ?? _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    if (_listeningUserId == uid && _notifChannel != null) {
      await refreshUnreadCounts();
      return;
    }

    await stopRealtimeListener();
    await init();
    _listeningUserId = uid;

    await _syncFcmToken();
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
            _handleIncomingNotificationRow(row);
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
          callback: (payload) {
            final row = payload.newRecord;
            _handleIncomingMessageRow(row);
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

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _pollUnseenUpdates(uid),
    );
  }

  Future<void> _seedExistingIds(String uid) async {
    try {
      final notifs = await _db
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(40);
      for (final r in (notifs as List)) {
        final id = (r['id'] ?? '').toString();
        if (id.isNotEmpty) _shownIds.add('notif_$id');
      }
    } catch (_) {}

    try {
      final msgs = await _db
          .from('messages')
          .select('id')
          .eq('receiver_id', uid)
          .order('created_at', ascending: false)
          .limit(40);
      for (final r in (msgs as List)) {
        final id = (r['id'] ?? '').toString();
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
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(10);
      final notifList = List<Map<String, dynamic>>.from(notifs);
      for (final row in notifList.reversed) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty && !_shownIds.contains('notif_$id')) {
          _handleIncomingNotificationRow(row);
        }
      }
    } catch (_) {}

    try {
      final msgs = await _db
          .from('messages')
          .select('id, sender_id, receiver_id, message, is_read')
          .eq('receiver_id', uid)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(10);
      final msgList = List<Map<String, dynamic>>.from(msgs);
      for (final row in msgList.reversed) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty && !_shownIds.contains('msg_$id')) {
          _handleIncomingMessageRow(row);
        }
      }
    } catch (_) {}

    await refreshUnreadCounts();
  }

  void _handleIncomingNotificationRow(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final key = id.isNotEmpty ? 'notif_$id' : null;
    if (key != null && _shownIds.contains(key)) {
      refreshUnreadCounts();
      return;
    }
    if (key != null) _shownIds.add(key);

    final title = (row['title'] as String?) ?? 'إشعار جديد — غيارك';
    final body = (row['body'] as String?) ?? '';

    // إشعار داخلي أنيق ينزل من الأعلى
    AppTopToast.notification(
      title: title,
      body: body,
      isChat: false,
    );

    // إشعار حقيقي في شريط الهاتف
    showLocalPhoneNotification(
      title: title,
      body: body,
    );

    refreshUnreadCounts();
  }

  Future<void> _handleIncomingMessageRow(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    final key = id.isNotEmpty ? 'msg_$id' : null;
    if (key != null && _shownIds.contains(key)) {
      refreshUnreadCounts();
      return;
    }
    if (key != null) _shownIds.add(key);

    final senderId = (row['sender_id'] ?? '').toString();
    final msg = (row['message'] as String?) ?? 'لديك رسالة جديدة';

    if (senderId.isNotEmpty && senderId == activeChatOtherUserId) {
      await markConversationAsRead(senderId);
      return;
    }

    final senderName = await _resolveSenderName(senderId);
    final title = 'رسالة جديدة من $senderName';

    // إشعار داخلي أنيق ينزل من الأعلى
    AppTopToast.notification(
      title: title,
      body: msg,
      isChat: true,
    );

    // إشعار حقيقي في شريط الهاتف
    await showLocalPhoneNotification(
      title: title,
      body: msg,
    );

    await refreshUnreadCounts();
  }

  Future<String> _resolveSenderName(String senderId) async {
    if (senderId.isEmpty) return 'مستخدم غيارك';
    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }
    try {
      final row = await _db
          .from('customers')
          .select('full_name, username')
          .eq('id', senderId)
          .maybeSingle();
      final full = (row?['full_name'] as String?)?.trim() ?? '';
      final user = (row?['username'] as String?)?.trim() ?? '';
      final name = full.isNotEmpty
          ? full
          : (user.isNotEmpty ? user : 'مستخدم غيارك');
      _senderNameCache[senderId] = name;
      return name;
    } catch (_) {
      return 'مستخدم غيارك';
    }
  }

  Future<void> refreshUnreadCounts() async {
    final uid = _listeningUserId ?? _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      unreadNotificationsCount.value = 0;
      unreadMessagesCount.value = 0;
      return;
    }

    try {
      final notifRows = await _db
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false);
      unreadNotificationsCount.value = (notifRows as List).length;
    } catch (_) {}

    try {
      final msgRows = await _db
          .from('messages')
          .select('id')
          .eq('receiver_id', uid)
          .eq('is_read', false);
      unreadMessagesCount.value = (msgRows as List).length;
    } catch (_) {}
  }

  Future<void> markConversationAsRead(String otherUserId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || otherUserId.isEmpty) return;
    try {
      await _db
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', otherUserId)
          .eq('receiver_id', uid)
          .eq('is_read', false);
    } catch (_) {}
    await refreshUnreadCounts();
  }

  Future<void> stopRealtimeListener() async {
    _listeningUserId = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    unreadNotificationsCount.value = 0;
    unreadMessagesCount.value = 0;

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
      final end =
          (i + chunkSize < inserts.length) ? i + chunkSize : inserts.length;
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
    await refreshUnreadCounts();
  }

  Future<void> markAllNotificationsAsRead() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
    await refreshUnreadCounts();
  }

  void openNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                      TextButton.icon(
                        onPressed: () async {
                          await markAllNotificationsAsRead();
                          if (!ctx.mounted) return;
                          AppTopToast.success(
                            'تم تحديد جميع الإشعارات كمقروءة',
                            context: ctx,
                          );
                        },
                        icon: const Icon(Icons.done_all, size: 17),
                        label: const Text('قراءة الكل'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('لا توجد إشعارات حالياً')),
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
                        return ListTile(
                          tileColor: read
                              ? Colors.transparent
                              : AppColors.orangeLight.withValues(alpha: 0.45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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

/// زر جرس الإشعارات مع شارة حمراء للعدد غير المقروء
class NotificationBellButton extends StatelessWidget {
  final Color iconColor;
  final VoidCallback? onPressed;

  const NotificationBellButton({
    super.key,
    this.iconColor = Colors.white,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final service = NotificationsService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: service.unreadNotificationsCount,
      builder: (_, count, __) {
        return IconButton(
          tooltip: 'الإشعارات',
          onPressed: onPressed ?? () => service.openNotificationsSheet(context),
          icon: Badge(
            isLabelVisible: count > 0,
            backgroundColor: Colors.red,
            label: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: Icon(Icons.notifications_none, color: iconColor),
          ),
        );
      },
    );
  }
}

/// زر الشات مع شارة حمراء لعدد الرسائل غير المقروءة
class ChatBadgeButton extends StatelessWidget {
  final Color iconColor;
  final VoidCallback onPressed;

  const ChatBadgeButton({
    super.key,
    required this.onPressed,
    this.iconColor = AppColors.navy,
  });

  @override
  Widget build(BuildContext context) {
    final service = NotificationsService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: service.unreadMessagesCount,
      builder: (_, count, __) {
        return IconButton(
          tooltip: 'الدردشات',
          onPressed: onPressed,
          icon: Badge(
            isLabelVisible: count > 0,
            backgroundColor: Colors.red,
            label: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: Icon(Icons.chat_bubble_outline, color: iconColor, size: 23),
          ),
        );
      },
    );
  }
}