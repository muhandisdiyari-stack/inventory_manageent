import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chat screen for a specific inventory.
/// Accepts inventoryId and resolves the chat room internally.
/// Desktop: sidebar with inventory list + chat. Mobile: chat with drawer.
class InventoryChatScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;
  final String companyId;
  final String companyName;

  const InventoryChatScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<InventoryChatScreen> createState() => _InventoryChatScreenState();
}

class _InventoryChatScreenState extends State<InventoryChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  String? _roomId;
  String? _selInvName;
  List<Map<String, dynamic>> _inventories = [];
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DateTime? _cursor;
  RealtimeChannel? _channel;

  String get _uid => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _selInvName = widget.inventoryName;
    _init();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadInventories();
    final inv = _inventories.firstWhere(
      (i) => i['inventory_id'] == widget.inventoryId,
      orElse: () => _inventories.isNotEmpty ? _inventories.first : {},
    );
    if (inv.isNotEmpty) {
      _roomId = inv['room_id'] as String;
      _selInvName = inv['inventory_name'] as String;
      _setupRealtime();
      _loadMessages();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadInventories() async {
    try {
      final data = await Supabase.instance.client.rpc(
        'get_inventory_chats',
        params: {'p_company_id': widget.companyId},
      );
      if (mounted) {
        setState(() => _inventories = List<Map<String, dynamic>>.from(data as List));
      }
    } catch (_) {}
  }

  Future<void> _loadMessages({DateTime? cursor}) async {
    if (_roomId == null) return;
    try {
      final data = await Supabase.instance.client.rpc('get_chat_room_messages', params: {
        'p_room_id': _roomId!,
        'p_cursor': cursor?.toUtc().toIso8601String(),
      });
      final msgs = List<Map<String, dynamic>>.from(data as List).reversed.toList();
      if (mounted) {
        setState(() {
          _messages = cursor != null ? [...msgs, ..._messages] : msgs;
          _hasMore = msgs.length >= 50;
          _cursor = msgs.isNotEmpty ? DateTime.parse(msgs.first['created_at'] as String) : null;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _setupRealtime() {
    if (_roomId == null) return;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('room_$_roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: _roomId!,
          ),
          callback: (p) {
            final m = Map<String, dynamic>.from(p.newRecord);
            if (mounted && !_messages.any((x) => x['id'] == m['id'])) {
              setState(() {
                _messages.add(m);
                _scrollDown();
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: _roomId!,
          ),
          callback: (p) {
            final m = Map<String, dynamic>.from(p.newRecord);
            if (mounted) {
              setState(() {
                final i = _messages.indexWhere((x) => x['id'] == m['id']);
                if (i >= 0) _messages[i] = m;
              });
            }
          },
        )
        .subscribe();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _switchRoom(String rid, String name) {
    if (rid == _roomId) return;
    setState(() {
      _roomId = rid;
      _selInvName = name;
      _messages = [];
      _loading = true;
      _hasMore = true;
      _cursor = null;
    });
    _setupRealtime();
    _loadMessages();
    _loadInventories();
  }

  Future<void> _send() async {
    if (_roomId == null) return;
    final c = _msgCtrl.text.trim();
    if (c.isEmpty) return;
    _msgCtrl.clear();

    final oid = 'opt_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _messages.add({
        'id': oid,
        'room_id': _roomId,
        'sender_id': _uid,
        'sender_name': 'You',
        'content': c,
        'status': 'sending',
        'is_edited': false,
        'is_deleted': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _scrollDown();

    try {
      await Supabase.instance.client.rpc('send_chat_message', params: {
        'p_room_id': _roomId!,
        'p_content': c,
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m['id'] == oid);
          if (i >= 0) _messages[i]['status'] = 'failed';
        });
      }
    }
  }

  void _edit(String id, String cur) async {
    final ctrl = TextEditingController(text: cur);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (r != null && r.isNotEmpty) {
      await Supabase.instance.client.rpc('edit_chat_message', params: {
        'p_message_id': id,
        'p_content': r,
      });
    }
  }

  void _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Delete this message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Supabase.instance.client.rpc('delete_chat_message', params: {
        'p_message_id': id,
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final wide = MediaQuery.of(c).size.width > 900;
    return Scaffold(
      appBar: AppBar(
        leading: wide
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.inventory_2),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_selInvName ?? widget.inventoryName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.companyName,
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ],
        ),
      ),
      drawer: wide ? null : _drawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _roomId == null
              ? _noRoom()
              : (wide ? _desktop() : _chat()),
    );
  }

  Widget _noRoom() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        const Text('No chat room found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('This inventory does not have a chat room yet.',
            style: TextStyle(color: Colors.grey)),
      ]),
    );
  }

  Widget _drawer() {
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: const Text('Inventories',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _inventories.length,
              itemBuilder: (_, i) {
                final inv = _inventories[i];
                final ur = (inv['unread_count'] as int?) ?? 0;
                final sel = inv['room_id'] == _roomId;
                return ListTile(
                  selected: sel,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  leading: Stack(children: [
                    Icon(Icons.inventory_2,
                        size: 20,
                        color: sel
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey),
                    if (ur > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: Center(
                            child: Text('$ur',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ]),
                  title: Text(inv['inventory_name'] ?? '',
                      style: TextStyle(
                          fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  onTap: () {
                    _switchRoom(
                        inv['room_id'] as String, inv['inventory_name'] as String);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _desktop() {
    return Row(children: [
      SizedBox(
        width: 280,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: const Text('Inventories',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _inventories.length,
              itemBuilder: (_, i) {
                final inv = _inventories[i];
                final ur = (inv['unread_count'] as int?) ?? 0;
                final sel = inv['room_id'] == _roomId;
                return ListTile(
                  selected: sel,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  leading: Stack(children: [
                    Icon(Icons.inventory_2,
                        size: 20,
                        color: sel
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey),
                    if (ur > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: Center(
                            child: Text('$ur',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ]),
                  title: Text(inv['inventory_name'] ?? '',
                      style: TextStyle(
                          fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  subtitle: inv['last_message'] != null
                      ? Text(inv['last_message'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11))
                      : null,
                  onTap: () => _switchRoom(
                      inv['room_id'] as String, inv['inventory_name'] as String),
                );
              },
            ),
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: _chat()),
    ]);
  }

  Widget _chat() {
    final groups = _groupMsgs(_messages);
    return Column(children: [
      Expanded(
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(8),
          itemCount: groups.length + (_hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == 0 && _hasMore) {
              return Center(
                child: TextButton(
                  onPressed: _loadingMore
                      ? null
                      : () {
                          setState(() => _loadingMore = true);
                          _loadMessages(cursor: _cursor);
                        },
                  child: _loadingMore
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Load older messages'),
                ),
              );
            }
            final gi = _hasMore ? i - 1 : i;
            if (gi < 0 || gi >= groups.length) return const SizedBox.shrink();
            return _buildGroup(groups[gi]);
          },
        ),
      ),
      _buildInputBar(),
    ]);
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: _send,
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Message Grouping ──────────────────────────────────────────

  List<_MsgGroup> _groupMsgs(List<Map<String, dynamic>> msgs) {
    if (msgs.isEmpty) return [];
    final groups = <_MsgGroup>[];
    List<Map<String, dynamic>> cur = [];
    String? lastDate;
    String? lastSender;

    for (final m in msgs) {
      final dt = DateTime.parse(m['created_at'] as String);
      final dl = _fmtDate(dt);
      final si = m['sender_id'] as String;

      if (dl != lastDate || (si != lastSender && cur.isNotEmpty)) {
        if (cur.isNotEmpty) {
          groups.add(_MsgGroup(date: lastDate, msgs: List.from(cur)));
        }
        cur = [];
      }
      cur.add(m);
      lastDate = dl;
      lastSender = si;
    }
    if (cur.isNotEmpty) {
      groups.add(_MsgGroup(date: lastDate, msgs: List.from(cur)));
    }
    return groups;
  }

  Widget _buildGroup(_MsgGroup g) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (g.date != null)
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
            child: Text(g.date!,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ),
        ),
      ...g.msgs.map((m) => _buildBubble(m)),
    ]);
  }

  Widget _buildBubble(Map<String, dynamic> m) {
    final isMine = m['sender_id'] == _uid;
    final isDel = m['is_deleted'] == true;
    final isEdit = m['is_edited'] == true;
    final isOpt = (m['id'] as String).startsWith('opt_');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.blue.withValues(alpha: 0.1),
                child: Text(
                  (m['sender_name'] ?? '?')[0].toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700),
                ),
              ),
            ),
          Flexible(
            child: GestureDetector(
              onLongPress: isMine && !isDel ? () => _showOptions(m) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: isDel
                      ? Colors.grey.shade200
                      : isMine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
                    bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(m['sender_name'] ?? '',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                  Text(m['content'] ?? '',
                      style: TextStyle(
                          fontSize: 14,
                          fontStyle: isDel ? FontStyle.italic : null,
                          color: isDel
                              ? Colors.grey
                              : (isOpt ? Colors.grey.shade600 : null))),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_fmtTime(m['created_at']),
                        style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    if (isEdit && !isDel) ...[
                      const SizedBox(width: 4),
                      Text('edited',
                          style: TextStyle(
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[500])),
                    ],
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _statusIcon(m['status'] as String?),
                    ],
                  ]),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(String? s) {
    switch (s) {
      case 'sending':
        return const SizedBox(
            width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5));
      case 'sent':
        return Icon(Icons.check, size: 14, color: Colors.grey[400]);
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
      case 'seen':
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      case 'failed':
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
      default:
        return const SizedBox.shrink();
    }
  }

  void _showOptions(Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit'),
            onTap: () {
              Navigator.pop(ctx);
              _edit(m['id'] as String, m['content'] as String);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              _delete(m['id'] as String);
            },
          ),
        ]),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _fmtTime(String? ts) {
    if (ts == null) return '';
    final dt = DateTime.parse(ts).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _MsgGroup {
  final String? date;
  final List<Map<String, dynamic>> msgs;
  const _MsgGroup({this.date, required this.msgs});
}