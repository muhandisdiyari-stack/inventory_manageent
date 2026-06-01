import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'inventory_chat_screen.dart';

/// Shows inventory chat rooms for a specific company.
class CompanyChatScreen extends StatefulWidget {
  final String companyId;
  final String companyName;

  const CompanyChatScreen({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<CompanyChatScreen> createState() => _CompanyChatScreenState();
}

class _CompanyChatScreenState extends State<CompanyChatScreen> {
  List<Map<String, dynamic>> _inventories = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadInventories();
    _setupRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInventories() async {
    try {
      final data = await Supabase.instance.client.rpc(
        'get_inventory_chats',
        params: {'p_company_id': widget.companyId},
      );
      if (mounted) {
        setState(() {
          _inventories = List<Map<String, dynamic>>.from(data as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRealtime() {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('company_chat_${widget.companyId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _debouncedRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: widget.companyId,
          ),
          callback: (_) => _debouncedRefresh(),
        )
        .subscribe();
  }

  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadInventories();
    });
  }

  int get _totalUnread =>
      _inventories.fold<int>(0, (sum, i) => sum + ((i['unread_count'] as int?) ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text(widget.companyName),
          if (_totalUnread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text('$_totalUnread',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _inventories.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No inventory chats',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Join an inventory to chat with its members',
                        style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _loadInventories,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _inventories.length,
                    itemBuilder: (_, i) => _buildCard(_inventories[i]),
                  ),
                ),
    );
  }

  Widget _buildCard(Map<String, dynamic> inv) {
    final unread = (inv['unread_count'] as int?) ?? 0;
    final name = inv['inventory_name'] as String? ?? 'Unknown';
    final lastMsg = inv['last_message'] as String?;
    final lastSender = inv['last_message_sender_name'] as String?;
    final memberCount = (inv['member_count'] as int?) ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InventoryChatScreen(
                inventoryId: inv['inventory_id'] as String,
                inventoryName: name,
                companyId: widget.companyId,
                companyName: widget.companyName,
              ),
            ),
          ).then((_) => _loadInventories());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Stack(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: unread > 0 ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.inventory_2,
                    color: unread > 0 ? Colors.red : Colors.green, size: 24),
              ),
              if (unread > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text('$unread',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500)),
                const SizedBox(height: 4),
                if (lastMsg != null)
                  Text(
                    lastSender != null ? '$lastSender: $lastMsg' : lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  )
                else
                  Text('$memberCount members',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}