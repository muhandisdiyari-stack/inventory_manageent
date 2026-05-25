import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/inventory_management/models/inventory_item.dart';
import 'features/inventory_management/models/inventory_settings.dart';
import 'core/constants/app_constants.dart';
import 'core/config/app_config.dart';
import 'core/services/activity_log_service.dart';
import 'core/di/injection_container.dart';
import 'core/app_lifecycle_observer.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/onboarding/screens/splash_screen.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── Global Error Handling ──────────────────────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🔴 Flutter Error: ${details.exception}');
    debugPrint('    Stack: ${details.stack}');
    // In production, send to crash reporting service (Sentry, Firebase Crashlytics, etc.)
    if (AppConfig.isProduction) {
      // CrashReportingService.recordError(details.exception, details.stack);
    }
  };

  // Catch unhandled async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🔴 Unhandled Error: $error');
    debugPrint('    Stack: $stack');
    // In production, send to crash reporting service
    if (AppConfig.isProduction) {
      // CrashReportingService.recordError(error, stack);
    }
    return true; // Prevent app from crashing in production
  };

  try {
    AppConfig.validate();

    // ─── Initialize Supabase ──────────────────────────────────
    if (AppConfig.useSupabase) {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.implicit,
          ),
        );
        debugPrint('✅ Supabase initialized');
      } catch (e) {
        debugPrint('⚠️ Supabase initialization failed: $e');
        if (AppConfig.isProduction) {
          runApp(_ErrorApp(
              title: 'Connection Error',
              error: 'Failed to connect to server. Please check your internet connection and try again.',
              canRetry: true));
          return;
        }
      }
    }

    // ─── Initialize Hive ─────────────────────────────────────
    await Hive.initFlutter();

    // Register adapters BEFORE opening any boxes
    Hive.registerAdapter(InventoryItemAdapter());
    Hive.registerAdapter(FieldConfigAdapter());
    Hive.registerAdapter(InventorySettingsAdapter());

    // Open required boxes
    final boxesToOpen = [
      AppConstants.appSettingsBox,
      AppConstants.inventoriesListBox,
      AppConstants.activityLogsBox,
    ];

    for (final boxName in boxesToOpen) {
      try {
        await Hive.openBox(boxName);
      } catch (e) {
        // Box might be corrupted, try to recover
        debugPrint('⚠️ Box $boxName failed to open: $e. Attempting recovery...');
        try {
          await Hive.deleteBoxFromDisk(boxName);
          await Hive.openBox(boxName);
          debugPrint('✅ Box $boxName recovered');
        } catch (e2) {
          debugPrint('❌ Box $boxName recovery failed: $e2');
          runApp(_ErrorApp(
              title: 'Storage Error',
              error: 'Failed to initialize local storage. Please restart the app.',
              canRetry: false));
          return;
        }
      }
    }

    // ─── Initialize Services ─────────────────────────────────
    await ActivityLogService().initialize();
    await InjectionContainer.initialize();

    // ─── Log App Version ─────────────────────────────────────
    debugPrint('📱 App Version: ${AppConfig.appVersion}');
    debugPrint('🔧 Environment: ${AppConfig.environment}');
    debugPrint('☁️ Supabase: ${AppConfig.useSupabase ? "Enabled" : "Disabled"}');

    // ─── Check Onboarding ────────────────────────────────────
    bool onboardingCompleted = false;
    try {
      final appSettings = Hive.box(AppConstants.appSettingsBox);
      onboardingCompleted = appSettings.get(
            AppConstants.onboardingCompletedKey,
            defaultValue: false,
          ) as bool? ??
          false;
    } catch (_) {
      onboardingCompleted = false;
    }

    // ─── Run App ─────────────────────────────────────────────
    runApp(
      AppLifecycleObserver(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppConfig.appName,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          home: onboardingCompleted
              ? const InventoryProApp()
              : SplashScreen(nextScreen: const OnboardingScreen()),
        ),
      ),
    );
  } catch (e, stack) {
    debugPrint('❌ Fatal initialization error: $e');
    debugPrint('    Stack: $stack');
    runApp(_ErrorApp(
        title: 'Initialization Error',
        error: 'An unexpected error occurred: $e',
        canRetry: true));
  }
}

// ─── Error App ────────────────────────────────────────────────────

class _ErrorApp extends StatelessWidget {
  final String title;
  final String error;
  final bool canRetry;

  const _ErrorApp({
    required this.title,
    required this.error,
    required this.canRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 40, color: Colors.red),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 32),
                if (canRetry)
                  FilledButton.icon(
                    onPressed: () {
                      // Re-run the app by calling main() again
                      // This is handled by the platform restart mechanism
                      debugPrint('Retry requested - restarting app');
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}