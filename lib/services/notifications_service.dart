import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class NotificationsService {
  final SupabaseClient _db = Supabase.instance.client;

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
                const Text('الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                            color: read ? AppColors.textSecondary : AppColors.orange,
                          ),
                          title: Text(
                            n['title'] ?? '',
                            style: TextStyle(
                              fontWeight: read ? FontWeight.normal : FontWeight.bold,
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
  final _service = NotificationsService();
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.orange,
                  content: Text('${newest['title']}: ${newest['body']}'),
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