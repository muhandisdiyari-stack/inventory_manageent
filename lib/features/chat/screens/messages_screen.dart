import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'company_chat_screen.dart';

/// Top-level messages screen showing companies with unread message counts.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _companies = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    _setupRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    try {
      final data = await Supabase.instance.client.rpc('get_companies_with_unread_chats');
      if (mounted) {
        setState(() {
          _companies = List<Map<String, dynamic>>.from(data as List);
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
        .channel('messages_screen')
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
          callback: (_) => _debouncedRefresh(),
        )
        .subscribe();
  }

  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadCompanies();
    });
  }

  int get _totalUnread =>
      _companies.fold<int>(0, (sum, c) => sum + ((c['total_unread'] as int?) ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Messages'),
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
          : _companies.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No messages yet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Join an inventory to start chatting',
                        style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _loadCompanies,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _companies.length,
                    itemBuilder: (_, i) => _buildCard(_companies[i]),
                  ),
                ),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final unread = (c['total_unread'] as int?) ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CompanyChatScreen(
                companyId: c['company_id'] as String,
                companyName: c['company_name'] as String? ?? 'Unknown',
              ),
            ),
          ).then((_) => _loadCompanies());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: unread > 0 ? Colors.red.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.business,
                  color: unread > 0 ? Colors.red : Colors.blue, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(c['company_name'] ?? 'Unknown',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500)),
            ),
            if (unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.red, borderRadius: BorderRadius.circular(12)),
                child: Text('$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}