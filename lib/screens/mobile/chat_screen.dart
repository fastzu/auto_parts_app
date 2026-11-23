import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/db_models.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import 'live_store_home_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _db = Supabase.instance.client;
  final Map<String, Map<String, dynamic>> _usersCache = {};
  final Map<String, Map<String, dynamic>> _productsCache = {};
  final Set<String> _fetchingUsers = {};
  final Set<String> _fetchingProducts = {};
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _messagesStream = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
    NotificationsService.instance.refreshUnreadCounts();
  }

  Future<void> _prefetchMetadata(List<Map<String, dynamic>> msgs, String myId) async {
    final missingUsers = <String>{};
    final missingProducts = <String>{};
    for (final m in msgs) {
      final otherId = m['sender_id'] == myId ? m['receiver_id'] : m['sender_id'];
      if (otherId is String &&
          !_usersCache.containsKey(otherId) &&
          !_fetchingUsers.contains(otherId)) {
        missingUsers.add(otherId);
        _fetchingUsers.add(otherId);
      }
      final prodId = m['product_id'];
      if (prodId is String &&
          !_productsCache.containsKey(prodId) &&
          !_fetchingProducts.contains(prodId)) {
        missingProducts.add(prodId);
        _fetchingProducts.add(prodId);
      }
    }
    try {
      if (missingUsers.isNotEmpty) {
        final users = await _db
            .from('customers')
            .select('id, full_name, username, phone, rating_avg, rating_count, is_trusted_merchant')
            .inFilter('id', missingUsers.toList());
        for (final u in users) {
          _usersCache[u['id'] as String] = Map<String, dynamic>.from(u);
        }
      }
      if (missingProducts.isNotEmpty) {
        final prods = await _db
            .from('products')
            .select('id, title, price, images')
            .inFilter('id', missingProducts.toList());
        for (final p in prods) {
          _productsCache[p['id'] as String] = Map<String, dynamic>.from(p);
        }
      }
    } finally {
      _fetchingUsers.removeAll(missingUsers);
      _fetchingProducts.removeAll(missingProducts);
    }
    if (mounted && (missingUsers.isNotEmpty || missingProducts.isNotEmpty)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _db.auth.currentUser?.id;
    if (myId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الدردشات')),
        body: const Center(child: Text('يرجى تسجيل الدخول لعرض المحادثات')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('الدردشات والرسائل')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _messagesStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final deduped = <String, Map<String, dynamic>>{};
          for (final m in snap.data!) {
            final id = (m['id'] ?? '').toString();
            if (id.isEmpty) continue;
            if (m['sender_id'] == myId || m['receiver_id'] == myId) {
              deduped[id] = m;
            }
          }
          final myMsgs = deduped.values.toList()
            ..sort((a, b) {
              final dtA = DateTime.tryParse((a['created_at'] as String?) ?? '') ?? DateTime(2000);
              final dtB = DateTime.tryParse((b['created_at'] as String?) ?? '') ?? DateTime(2000);
              return dtB.compareTo(dtA);
            });

          if (myMsgs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 54, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('لا توجد محادثات حتى الآن',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                ],
              ),
            );
          }
          _prefetchMetadata(myMsgs, myId);

          final Map<String, Map<String, dynamic>> threads = {};
          final Map<String, int> unreadByThread = {};
          for (final m in myMsgs) {
            final otherId =
                (m['sender_id'] == myId ? m['receiver_id'] : m['sender_id']) as String?;
            if (otherId == null) continue;
            final prodId = m['product_id'] as String? ?? 'general';
            final key = '${otherId}_$prodId';
            threads.putIfAbsent(key, () => m);
            if (m['receiver_id'] == myId && m['is_read'] != true) {
              unreadByThread[key] = (unreadByThread[key] ?? 0) + 1;
            }
          }

          final entries = threads.entries.toList();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final threadKey = entries[i].key;
              final lastMsg = entries[i].value;
              final unreadCount = unreadByThread[threadKey] ?? 0;
              final otherId =
                  (lastMsg['sender_id'] == myId ? lastMsg['receiver_id'] : lastMsg['sender_id'])
                      as String;
              final prodId = lastMsg['product_id'] as String?;
              final otherUser = _usersCache[otherId];
              final prod = prodId != null ? _productsCache[prodId] : null;
              final otherName = (otherUser?['full_name'] as String?) ?? 'مستخدم';
              final ratingAvg = ((otherUser?['rating_avg'] as num?) ?? 0).toDouble();
              final ratingCount = (otherUser?['rating_count'] as num?)?.toInt() ?? 0;
              final isTrusted = otherUser?['is_trusted_merchant'] == true;
              final prodTitle = prod?['title'] as String?;
              final isMe = lastMsg['sender_id'] == myId;

              return FadeSlideIn(
                index: i,
                child: Card(
                  color: unreadCount > 0 ? const Color(0xFFFFF7F2) : null,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: unreadCount > 0 ? AppColors.orange : AppColors.navy,
                      child: Text(
                        otherName.isNotEmpty ? otherName[0].toUpperCase() : '؟',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  otherName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              if (isTrusted) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, color: Colors.blue, size: 15),
                              ],
                              if (ratingCount > 0) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.star, color: Colors.amber, size: 14),
                                Text(
                                  ratingAvg.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          _formatTime(lastMsg['created_at'] as String?),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (prodTitle != null)
                          Text(
                            'بخصوص: $prodTitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          '${isMe ? "أنت: " : ""}${lastMsg['message'] ?? ""}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unreadCount > 0 ? AppColors.navy : AppColors.textSecondary,
                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    trailing: unreadCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        animatedRoute(
                          ChatConversationScreen(
                            otherUserId: otherId,
                            otherUserName: otherName,
                            otherUserPhone: otherUser?['phone'] as String?,
                            productId: prodId,
                            productTitle: prodTitle,
                            productPrice: (prod?['price'] as num?)?.toDouble(),
                          ),
                        ),
                      );
                      NotificationsService.instance.refreshUnreadCounts();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class ChatConversationScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhone;
  final String? productId;
  final String? productTitle;
  final double? productPrice;

  const ChatConversationScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhone,
    this.productId,
    this.productTitle,
    this.productPrice,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _db = Supabase.instance.client;
  final _notifs = NotificationsService.instance;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final Map<String, Map<String, dynamic>> _messagesById = {};
  List<Map<String, dynamic>> _sortedMessages = [];
  RealtimeChannel? _chatChannel;

  CustomerProfile? _otherProfile;
  CustomerProfile? _myProfile;
  bool _loadingMessages = true;
  bool _openingProfile = false;
  bool _sending = false;

  String? get _myId => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _notifs.activeChatOtherUserId = widget.otherUserId;
    _notifs.markConversationAsRead(widget.otherUserId);
    _loadProfiles();
    _loadMessages();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_notifs.activeChatOtherUserId == widget.otherUserId) {
      _notifs.activeChatOtherUserId = null;
    }
    if (_chatChannel != null) {
      try {
        _db.removeChannel(_chatChannel!);
      } catch (_) {}
      _chatChannel = null;
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _belongsToConversation(Map<String, dynamic> m) {
    final myId = _myId;
    if (myId == null) return false;
    final sender = m['sender_id'] as String?;
    final receiver = m['receiver_id'] as String?;
    final samePair = (sender == myId && receiver == widget.otherUserId) ||
        (sender == widget.otherUserId && receiver == myId);
    if (!samePair) return false;
    return widget.productId == null || m['product_id'] == widget.productId;
  }

  void _rebuildSortedMessages({bool scrollToBottom = false}) {
    final list = _messagesById.values.toList()
      ..sort((a, b) {
        final dtA = DateTime.tryParse((a['created_at'] as String?) ?? '') ?? DateTime(2000);
        final dtB = DateTime.tryParse((b['created_at'] as String?) ?? '') ?? DateTime(2000);
        final cmp = dtA.compareTo(dtB);
        if (cmp != 0) return cmp;
        return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
      });
    _sortedMessages = list;
    if (scrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _loadProfiles() async {
    final myId = _myId;
    try {
      final otherRow = await _db
          .from('customers')
          .select()
          .eq('id', widget.otherUserId)
          .maybeSingle();
      Map<String, dynamic>? myRow;
      if (myId != null) {
        myRow = await _db.from('customers').select().eq('id', myId).maybeSingle();
      }
      if (!mounted) return;
      setState(() {
        if (otherRow != null) {
          _otherProfile = CustomerProfile.fromMap(Map<String, dynamic>.from(otherRow));
        }
        if (myRow != null) {
          _myProfile = CustomerProfile.fromMap(Map<String, dynamic>.from(myRow));
        }
      });
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    final myId = _myId;
    if (myId == null) {
      if (mounted) setState(() => _loadingMessages = false);
      return;
    }
    try {
      var query = _db
          .from('messages')
          .select()
          .or(
            'and(sender_id.eq.$myId,receiver_id.eq.${widget.otherUserId}),'
            'and(sender_id.eq.${widget.otherUserId},receiver_id.eq.$myId)',
          );
      if (widget.productId != null) {
        query = query.eq('product_id', widget.productId!);
      }
      final rows = await query.order('created_at', ascending: true).limit(300);
      if (!mounted) return;
      setState(() {
        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw);
          final id = (row['id'] ?? '').toString();
          if (id.isNotEmpty) {
            _messagesById[id] = row;
          }
        }
        _loadingMessages = false;
        _rebuildSortedMessages(scrollToBottom: true);
      });
      await _notifs.markConversationAsRead(widget.otherUserId);
    } catch (_) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _subscribeRealtime() {
    final myId = _myId;
    if (myId == null) return;
    final channelName =
        'chat_${myId}_${widget.otherUserId}_${widget.productId ?? 'general'}_${DateTime.now().millisecondsSinceEpoch}';
    _chatChannel = _db
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (!_belongsToConversation(row)) return;
            final id = (row['id'] ?? '').toString();
            if (id.isEmpty || _messagesById.containsKey(id)) return;
            if (row['receiver_id'] == myId) {
              _notifs.markConversationAsRead(widget.otherUserId);
            }
            if (!mounted) return;
            setState(() {
              _messagesById[id] = row;
              _rebuildSortedMessages(scrollToBottom: true);
            });
          },
        )
        .subscribe();
  }

  Future<void> _openOtherProfile() async {
    if (_openingProfile) return;
    CustomerProfile? target = _otherProfile;
    if (target == null) {
      setState(() => _openingProfile = true);
      try {
        final row = await _db
            .from('customers')
            .select()
            .eq('id', widget.otherUserId)
            .maybeSingle();
        if (row != null) {
          target = CustomerProfile.fromMap(Map<String, dynamic>.from(row));
          if (mounted) setState(() => _otherProfile = target);
        }
      } catch (_) {
      } finally {
        if (mounted) setState(() => _openingProfile = false);
      }
    }

    target ??= CustomerProfile(
      id: widget.otherUserId,
      fullName: widget.otherUserName,
      phone: widget.otherUserPhone,
    );

    if (!mounted) return;
    await Navigator.push(
      context,
      animatedRoute(
        MerchantPublicProfileScreen(
          seller: target,
          viewerProfile: _myProfile,
        ),
      ),
    );
    if (mounted) _loadProfiles();
  }

  Future<void> _callOtherUser() async {
    final rawPhone = _otherProfile?.phone ?? widget.otherUserPhone ?? '';
    final cleaned = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الهاتف غير متوفر')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: cleaned), mode: LaunchMode.externalApplication);
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _msgCtrl.text.trim();
    final myId = _myId;
    if (text.isEmpty || myId == null) return;

    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      final inserted = await _db
          .from('messages')
          .insert({
            'sender_id': myId,
            'receiver_id': widget.otherUserId,
            'product_id': widget.productId,
            'message': text,
            'is_read': false,
          })
          .select();

      if (mounted && inserted.isNotEmpty) {
        final row = Map<String, dynamic>.from(inserted.first);
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) {
          setState(() {
            _messagesById[id] = row;
            _rebuildSortedMessages(scrollToBottom: true);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _msgCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الرسالة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _myId;
    final displayName = _otherProfile?.fullName?.trim().isNotEmpty == true
        ? _otherProfile!.fullName!
        : widget.otherUserName;
    final phone = (_otherProfile?.phone ?? widget.otherUserPhone ?? '').trim();
    final hasPhone = phone.isNotEmpty;
    final ratingAvg = _otherProfile?.ratingAvg ?? 0.0;
    final ratingCount = _otherProfile?.ratingCount ?? 0;
    final isTrusted = _otherProfile?.isTrustedMerchant == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        leading: const BackButton(color: Colors.white),
        titleSpacing: 0,
        title: InkWell(
          onTap: _openOtherProfile,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isTrusted) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, color: Colors.lightBlueAccent, size: 15),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.star, size: 13, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      ratingCount > 0
                          ? '${ratingAvg.toStringAsFixed(1)} ($ratingCount)'
                          : 'بدون تقييم',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasPhone) ...[
                      const Text(' · ', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                      const Icon(Icons.call, size: 11, color: AppColors.orange),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'عرض بروفايل التاجر وتقييمه',
            onPressed: _openingProfile ? null : _openOtherProfile,
            icon: _openingProfile
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.storefront_outlined, color: Colors.white),
          ),
          if (hasPhone)
            IconButton(
              tooltip: 'اتصال هاتفي',
              onPressed: _callOtherUser,
              icon: const Icon(Icons.phone, color: Colors.white),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.productTitle != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.orangeLight,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'القطعة: ${widget.productTitle}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  if (widget.productPrice != null)
                    Text(
                      '${widget.productPrice} د.أ',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.orange,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : _sortedMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'ابدأ المحادثة الآن...',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _sortedMessages.length,
                        itemBuilder: (_, i) {
                          final m = _sortedMessages[i];
                          final isMe = m['sender_id'] == myId;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.74,
                              ),
                              decoration: BoxDecoration(
                                color: isMe ? AppColors.orange : AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: isMe ? null : Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                (m['message'] as String?) ?? '',
                                style: TextStyle(
                                  color: isMe ? Colors.white : AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (!_sending) _send();
                      },
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك هنا...',
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.orange,
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 19),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}