import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global cubit that maintains the total unread message count.
/// Persists across all screens so the badge updates live.
class UnreadCountCubit extends Cubit<int> {
  RealtimeChannel? _channel;
  Timer? _debounce;

  UnreadCountCubit() : super(0) {
    _loadCount();
    _setupRealtime();
  }

  Future<void> _loadCount() async {
    try {
      final data = await Supabase.instance.client.rpc('get_companies_with_unread_chats');
      final companies = List<Map<String, dynamic>>.from(data as List);
      emit(companies.fold<int>(0, (sum, c) => sum + ((c['total_unread'] as int?) ?? 0)));
    } catch (_) {}
  }

  void _setupRealtime() {
    _channel?.unsubscribe();
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
        .subscribe();
  }

  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _loadCount);
  }

  /// Manually refresh count (call after returning from chat screens)
  void refresh() => _loadCount();

  @override
  Future<void> close() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    return super.close();
  }
}