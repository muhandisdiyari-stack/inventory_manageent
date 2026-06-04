import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/snackbar_utils.dart';
import 'inventory_chat_screen.dart';

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
  String? _error;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadInventories();
    _setupRealtime();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInventories() async {
    if (_isDisposed) return;

    try {
      final data = await Supabase.instance.client.rpc(
        'get_inventory_chats',
        params: {'p_company_id': widget.companyId},
      );

      if (_isDisposed) return;

      if (mounted) {
        setState(() {
          _inventories = List<Map<String, dynamic>>.from(data as List);
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('Failed to load inventory chats: $e');
      if (_isDisposed) return;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load chats. Pull to refresh.';
        });
      }
    }
  }

  void _setupRealtime() {
    _channel?.unsubscribe();
    try {
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
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('Company chat subscription error: $error');
            }
          });
    } catch (e) {
      debugPrint('Failed to setup company chat realtime: $e');
    }
  }

  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_isDisposed) _loadInventories();
    });
  }

  Future<void> _onRefresh() async {
    await _loadInventories();
  }

  int get _totalUnread => _inventories.fold<int>(
      0, (sum, i) => sum + ((i['unread_count'] as int?) ?? 0));

  void _openInventoryChat(Map<String, dynamic> inventory) {
    final inventoryId = inventory['inventory_id'] as String?;
    final inventoryName =
        inventory['inventory_name'] as String? ?? 'Unknown';

    if (inventoryId == null || inventoryId.isEmpty) {
      SnackBarUtils.error(context, 'Cannot open chat: Invalid inventory');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryChatScreen(
          inventoryId: inventoryId,
          inventoryName: inventoryName,
          companyId: widget.companyId,
          companyName: widget.companyName,
        ),
      ),
    ).then((_) {
      if (mounted && !_isDisposed) {
        _loadInventories();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text(widget.companyName),
          if (_totalUnread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_totalUnread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _onRefresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _inventories.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _inventories.length,
                        itemBuilder: (_, i) => _buildInventoryCard(
                          _inventories[i],
                          colorScheme,
                        ),
                      ),
                    ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadInventories();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No inventory chats',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join an inventory to chat with its members',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'Pull down to refresh',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryCard(
      Map<String, dynamic> inventory, ColorScheme colorScheme) {
    final unread = (inventory['unread_count'] as int?) ?? 0;
    final name = inventory['inventory_name'] as String? ?? 'Unknown';
    final lastMsg = inventory['last_message'] as String?;
    final lastSender = inventory['last_message_sender_name'] as String?;
    final lastMsgTime = inventory['last_message_at'] as String?;
    final memberCount = (inventory['member_count'] as int?) ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openInventoryChat(inventory),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: unread > 0
                          ? Colors.red.shade50
                          : colorScheme.primaryContainer
                              .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.inventory_2,
                      color: unread > 0 ? Colors.red : colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            unread > 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (lastMsg != null)
                      Text(
                        lastSender != null
                            ? '$lastSender: $lastMsg'
                            : lastMsg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: unread > 0
                              ? Colors.grey[800]
                              : Colors.grey[600],
                          fontWeight: unread > 0
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      )
                    else
                      Text(
                        '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500]),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (lastMsgTime != null)
                    Text(
                      _formatLastMessageTime(lastMsgTime),
                      style: TextStyle(
                        fontSize: 10,
                        color: unread > 0
                            ? Colors.red.shade600
                            : Colors.grey[500],
                        fontWeight: unread > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right,
                      color: Colors.grey[400], size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastMessageTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}