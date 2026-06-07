import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';
import '../core/constants/app_constants.dart';

class AppLifecycleObserver extends StatefulWidget {
  final Widget child;

  const AppLifecycleObserver({super.key, required this.child});

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  DateTime? _lastBackgroundTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('📱 App lifecycle state: $state');

    switch (state) {
      case AppLifecycleState.resumed: _onAppResumed();
      case AppLifecycleState.paused: _onAppPaused();
      case AppLifecycleState.inactive: break;
      case AppLifecycleState.detached: _onAppDetached();
      case AppLifecycleState.hidden: _onAppPaused();
    }
  }

  Future<void> _onAppResumed() async {
    final timeInBackground = _lastBackgroundTime != null
        ? DateTime.now().difference(_lastBackgroundTime!)
        : Duration.zero;

    debugPrint('📱 App resumed (was in background for ${timeInBackground.inSeconds}s)');

    if (AppConfig.useSupabase && timeInBackground.inMinutes > 5) {
      try {
        final client = Supabase.instance.client;
        final session = client.auth.currentSession;
        if (session != null) {
          await client.auth.refreshSession();
          debugPrint('✅ Auth session refreshed');
          try {
            await client.rpc('update_last_login');
          } catch (e) {
            debugPrint('⚠️ Update last login failed: $e');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Failed to refresh session: $e');
      }
    }

    _lastBackgroundTime = null;
  }

  void _onAppPaused() {
    _lastBackgroundTime = DateTime.now();
    debugPrint('📱 App paused at $_lastBackgroundTime');
    _flushAllBoxes();
  }

  void _onAppDetached() {
    debugPrint('📱 App detached - performing cleanup');
    _flushAllBoxes();
  }

  void _flushAllBoxes() {
    final boxNames = [
      AppConstants.appSettingsBox,
      AppConstants.inventoriesListBox,
      AppConstants.activityLogsBox,
    ];
    for (final name in boxNames) {
      try {
        if (Hive.isBoxOpen(name)) {
          Hive.box(name).flush();
        }
      } catch (e) {
        debugPrint('⚠️ Failed to flush Hive box $name: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}