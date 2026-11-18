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
    final uid = _db.auth.currentUser!.id;
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
                const Text('الإشعارات',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                          title: Text(n['title'] ?? '',
                              style: TextStyle(
                                  fontWeight: read
                                      ? FontWeight.normal
                                      : FontWeight.bold)),
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
