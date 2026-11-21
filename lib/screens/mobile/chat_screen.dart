import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _db = Supabase.instance.client;
  final Map<String, Map<String, dynamic>> _usersCache = {};
  final Map<String, Map<String, dynamic>> _productsCache = {};

  Future<void> _prefetchMetadata(List<Map<String, dynamic>> msgs, String myId) async {
    final missingUsers = <String>{};
    final missingProducts = <String>{};
    for (final m in msgs) {
      final otherId = m['sender_id'] == myId ? m['receiver_id'] : m['sender_id'];
      if (otherId is String && !_usersCache.containsKey(otherId)) {
        missingUsers.add(otherId);
      }
      final prodId = m['product_id'];
      if (prodId is String && !_productsCache.containsKey(prodId)) {
        missingProducts.add(prodId);
      }
    }
    if (missingUsers.isNotEmpty) {
      final users = await _db.from('customers').select('id, full_name, username, phone').inFilter('id', missingUsers.toList());
      for (final u in users) {
        _usersCache[u['id'] as String] = u;
      }
    }
    if (missingProducts.isNotEmpty) {
      final prods = await _db.from('products').select('id, title, price, images').inFilter('id', missingProducts.toList());
      for (final p in prods) {
        _productsCache[p['id'] as String] = p;
      }
    }
    if (mounted && (missingUsers.isNotEmpty || missingProducts.isNotEmpty)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _db.auth.currentUser?.id;
    if (myId == null) {
      return Scaffold(appBar: AppBar(title: const Text('الدردشات')), body: const Center(child: Text('يرجى تسجيل الدخول لعرض المحادثات')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('الدردشات والرسائل')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.from('messages').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final myMsgs = snap.data!.where((m) => m['sender_id'] == myId || m['receiver_id'] == myId).toList();
          if (myMsgs.isEmpty) {
            return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.chat_bubble_outline, size: 54, color: AppColors.textSecondary), SizedBox(height: 12), Text('لا توجد محادثات حتى الآن', style: TextStyle(color: AppColors.textSecondary, fontSize: 15))]));
          }
          _prefetchMetadata(myMsgs, myId);

          final Map<String, Map<String, dynamic>> threads = {};
          for (final m in myMsgs) {
            final otherId = (m['sender_id'] == myId ? m['receiver_id'] : m['sender_id']) as String?;
            if (otherId == null) {
              continue;
            }
            final prodId = m['product_id'] as String? ?? 'general';
            threads.putIfAbsent('${otherId}_$prodId', () => m);
          }

          final list = threads.values.toList();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final lastMsg = list[i];
              final otherId = (lastMsg['sender_id'] == myId ? lastMsg['receiver_id'] : lastMsg['sender_id']) as String;
              final prodId = lastMsg['product_id'] as String?;
              final otherUser = _usersCache[otherId];
              final prod = prodId != null ? _productsCache[prodId] : null;
              final otherName = (otherUser?['full_name'] as String?) ?? 'مستخدم';
              final prodTitle = prod?['title'] as String?;
              final isMe = lastMsg['sender_id'] == myId;

              return FadeSlideIn(
                index: i,
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: CircleAvatar(radius: 24, backgroundColor: AppColors.navy, child: Text(otherName.isNotEmpty ? otherName[0].toUpperCase() : '؟', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(otherName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))), Text(_formatTime(lastMsg['created_at'] as String?), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))]),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (prodTitle != null) Text('بخصوص: $prodTitle', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${isMe ? "أنت: " : ""}${lastMsg['message'] ?? ""}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () => Navigator.push(context, animatedRoute(ChatConversationScreen(otherUserId: otherId, otherUserName: otherName, otherUserPhone: otherUser?['phone'] as String?, productId: prodId, productTitle: prodTitle, productPrice: (prod?['price'] as num?)?.toDouble()))),
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

  const ChatConversationScreen({super.key, required this.otherUserId, required this.otherUserName, this.otherUserPhone, this.productId, this.productTitle, this.productPrice});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _db = Supabase.instance.client;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _callOtherUser() async {
    final cleaned = (widget.otherUserPhone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الهاتف غير متوفر')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: cleaned), mode: LaunchMode.externalApplication);
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    final myId = _db.auth.currentUser?.id;
    if (text.isEmpty || myId == null) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await _db.from('messages').insert({'sender_id': myId, 'receiver_id': widget.otherUserId, 'product_id': widget.productId, 'message': text});
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _db.auth.currentUser?.id;
    final hasPhone = (widget.otherUserPhone ?? '').trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherUserName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (hasPhone)
              GestureDetector(
                onTap: _callOtherUser,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call, size: 12, color: AppColors.orange),
                    const SizedBox(width: 4),
                    Text(widget.otherUserPhone!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
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
              decoration: const BoxDecoration(color: AppColors.orangeLight, border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('القطعة: ${widget.productTitle}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navy))),
                  if (widget.productPrice != null) Text('${widget.productPrice} د.أ', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.orange)),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _db.from('messages').stream(primaryKey: ['id']).order('created_at', ascending: true),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snap.data!.where((m) {
                  final samePair = (m['sender_id'] == myId && m['receiver_id'] == widget.otherUserId) || (m['sender_id'] == widget.otherUserId && m['receiver_id'] == myId);
                  if (!samePair) return false;
                  return widget.productId == null || m['product_id'] == widget.productId;
                }).toList();
                if (msgs.isEmpty) return const Center(child: Text('ابدأ المحادثة الآن...', style: TextStyle(color: AppColors.textSecondary)));
                WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent); });

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final isMe = m['sender_id'] == myId;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
                        decoration: BoxDecoration(color: isMe ? AppColors.orange : AppColors.surface, borderRadius: BorderRadius.circular(14), border: isMe ? null : Border.all(color: AppColors.border)),
                        child: Text(m['message'] ?? '', style: TextStyle(color: isMe ? Colors.white : AppColors.textPrimary, fontSize: 14)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: _msgCtrl, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: 'اكتب رسالتك هنا...', filled: true, fillColor: AppColors.background, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)))),
                  const SizedBox(width: 8),
                  CircleAvatar(backgroundColor: AppColors.orange, child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 19), onPressed: _sending ? null : _send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}