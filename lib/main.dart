import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/inventory_management/models/inventory_item.dart';
import 'features/inventory_management/models/inventory_settings.dart';
import 'core/constants/app_constants.dart';
import 'core/config/app_config.dart';
import 'core/services/activity_log_service.dart';
import 'core/di/injection_container.dart';
import 'core/app_lifecycle_observer.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🔴 Flutter Error: ${details.exception}');
    debugPrint('    Stack: ${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🔴 Unhandled Error: $error');
    debugPrint('    Stack: $stack');
    return true;
  };

  try {
    AppConfig.validate();

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

    await Hive.initFlutter();

    Hive.registerAdapter(InventoryItemAdapter());
    Hive.registerAdapter(FieldConfigAdapter());
    Hive.registerAdapter(InventorySettingsAdapter());

    final boxesToOpen = [
      AppConstants.appSettingsBox,
      AppConstants.inventoriesListBox,
      AppConstants.activityLogsBox,
    ];

    for (final boxName in boxesToOpen) {
      try {
        await Hive.openBox(boxName);
      } catch (e) {
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

    // ✅ FIXED: Only clear auth cache if schema version changed (not on every launch)
    // This prevents forced re-login on every cold start
    try {
      final appSettings = Hive.box(AppConstants.appSettingsBox);
      final lastSchemaVersion = appSettings.get('schema_version', defaultValue: 0) as int? ?? 0;
      const currentSchemaVersion = 2; // Increment when DB schema changes

      if (lastSchemaVersion < currentSchemaVersion) {
        // Schema changed - clear auth to prevent stale session issues
        final authBox = await Hive.openBox('auth');
        await authBox.clear();
        await appSettings.put('schema_version', currentSchemaVersion);
        debugPrint('🧹 Auth cache cleared for schema migration v$currentSchemaVersion');
      }
    } catch (_) {}

    // Initialize onboarding key if not set
    try {
      final appSettings = Hive.box(AppConstants.appSettingsBox);
      if (!appSettings.containsKey(AppConstants.onboardingCompletedKey)) {
        await appSettings.put(AppConstants.onboardingCompletedKey, false);
      }
    } catch (_) {}

    await ActivityLogService().initialize();
    await InjectionContainer.initialize();

    AppConfig.logConfig();

    runApp(
      AppLifecycleObserver(
        child: MultiBlocProvider(
          providers: InjectionContainer.blocProviders,
          child: const InventoryProApp(),
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
                  child: const Icon(Icons.error_outline, size: 40, color: Colors.red),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}