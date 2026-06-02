import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/snackbar_utils.dart';
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
  String? _error;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    _setupRealtime();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    if (_isDisposed) return;

    try {
      final data = await Supabase.instance.client
          .rpc('get_companies_with_unread_chats');

      if (_isDisposed) return;

      if (mounted) {
        setState(() {
          _companies = List<Map<String, dynamic>>.from(data as List);
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('Failed to load companies with chats: $e');
      if (_isDisposed) return;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load messages. Pull to refresh.';
        });
      }
    }
  }

  void _setupRealtime() {
    _channel?.unsubscribe();
    try {
      _channel = Supabase.instance.client
          .channel('messages_screen_global')
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
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('Messages screen subscription error: $error');
            }
          });
    } catch (e) {
      debugPrint('Failed to setup messages realtime: $e');
    }
  }

  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_isDisposed) _loadCompanies();
    });
  }

  int get _totalUnread =>
      _companies.fold<int>(0, (sum, c) => sum + ((c['total_unread'] as int?) ?? 0));

  Future<void> _onRefresh() async {
    await _loadCompanies();
  }

  void _openCompanyChat(Map<String, dynamic> company) {
    final companyId = company['company_id'] as String?;
    final companyName = company['company_name'] as String? ?? 'Unknown';

    if (companyId == null || companyId.isEmpty) {
      SnackBarUtils.error(context, 'Cannot open chat: Invalid company');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompanyChatScreen(
          companyId: companyId,
          companyName: companyName,
        ),
      ),
    ).then((_) {
      if (mounted && !_isDisposed) {
        _loadCompanies();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Messages'),
          if (_totalUnread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              : _companies.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _companies.length,
                        itemBuilder: (_, i) => _buildCompanyCard(
                          _companies[i],
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
                _loadCompanies();
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
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No messages yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join an inventory to start chatting with members',
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

  Widget _buildCompanyCard(Map<String, dynamic> company, ColorScheme colorScheme) {
    final unread = (company['total_unread'] as int?) ?? 0;
    final companyName = company['company_name'] as String? ?? 'Unknown';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCompanyChat(company),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: unread > 0
                      ? Colors.red.shade50
                      : colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business,
                  color: unread > 0 ? Colors.red : colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (unread > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$unread unread ${unread == 1 ? 'message' : 'messages'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}