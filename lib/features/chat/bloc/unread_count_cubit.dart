import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global cubit that maintains the total unread message count.
/// Persists across all screens so the badge updates live.
class UnreadCountCubit extends Cubit<int> {
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _isDisposed = false;

  UnreadCountCubit() : super(0) {
    _loadCount();
    _setupRealtime();
  }

  Future<void> _loadCount() async {
    if (_isDisposed) return;
    try {
      final data = await Supabase.instance.client
          .rpc('get_companies_with_unread_chats');

      if (_isDisposed) return;

      final companies = List<Map<String, dynamic>>.from(data as List);
      final totalUnread = companies.fold<int>(
        0,
        (sum, c) => sum + ((c['total_unread'] as int?) ?? 0),
      );

      if (!_isDisposed) {
        emit(totalUnread);
      }
    } catch (e) {
      debugPrint('Failed to load unread count: $e');
      // Keep current count on error
    }
  }

  void _setupRealtime() {
    _channel?.unsubscribe();
    try {
      _channel = Supabase.instance.client
          .channel('unread_count_global')
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
              debugPrint('Unread count subscription error: $error');
            }
          });
    } catch (e) {
      debugPrint('Failed to setup unread count realtime: $e');
    }
  }

  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!_isDisposed) _loadCount();
    });
  }

  /// Manually refresh count (call after returning from chat screens)
  void refresh() {
    if (!_isDisposed) _loadCount();
  }

  @override
  Future<void> close() {
    _isDisposed = true;
    _channel?.unsubscribe();
    _debounce?.cancel();
    return super.close();
  }
}