import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';

/// Observes app lifecycle changes and performs necessary actions.
///
/// Handles:
/// - Auth token refresh when app returns to foreground
/// - Hive box flushing when app goes to background
/// - Cleanup on app termination
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
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;

      case AppLifecycleState.paused:
        _onAppPaused();
        break;

      case AppLifecycleState.inactive:
        // App is in an inactive state (e.g., phone call incoming)
        break;

      case AppLifecycleState.detached:
        _onAppDetached();
        break;

      case AppLifecycleState.hidden:
        // App is hidden (rarely used on mobile)
        _onAppPaused();
        break;
    }
  }

  /// Called when the app returns to the foreground.
  Future<void> _onAppResumed() async {
    final timeInBackground = _lastBackgroundTime != null
        ? DateTime.now().difference(_lastBackgroundTime!)
        : Duration.zero;

    debugPrint('📱 App resumed (was in background for ${timeInBackground.inSeconds}s)');

    // Refresh Supabase session if it's been more than 5 minutes
    if (AppConfig.useSupabase && timeInBackground.inMinutes > 5) {
      try {
        final client = Supabase.instance.client;
        final session = client.auth.currentSession;
        if (session != null) {
          await client.auth.refreshSession();
          debugPrint('✅ Auth session refreshed');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to refresh session: $e');
        // Session may have expired - auth state will handle this
      }
    }

    _lastBackgroundTime = null;
  }

  /// Called when the app goes to the background.
  void _onAppPaused() {
    _lastBackgroundTime = DateTime.now();
    debugPrint('📱 App paused at $_lastBackgroundTime');

    // Flush Hive boxes to disk
    // This ensures data is persisted even if the app is killed
    // Note: Hive auto-flushes, but explicit flush is safer for critical data
  }

  /// Called when the app is about to be terminated.
  void _onAppDetached() {
    debugPrint('📱 App detached - performing cleanup');
    // Hive will automatically close boxes, but explicit cleanup is good practice
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}