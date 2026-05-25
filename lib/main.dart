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
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/onboarding/screens/splash_screen.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
              error: 'Failed to connect to server: $e'));
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
        try {
          await Hive.deleteBoxFromDisk(boxName);
          await Hive.openBox(boxName);
        } catch (e2) {
          runApp(_ErrorApp(
              error: 'Storage initialization failed: $e2'));
          return;
        }
      }
    }

    // ─── Initialize Services ─────────────────────────────────
    await ActivityLogService().initialize();
    await InjectionContainer.initialize();

    // ─── Check Onboarding ────────────────────────────────────
    bool onboardingCompleted = false;
    try {
      final appSettings =
          Hive.box(AppConstants.appSettingsBox);
      onboardingCompleted = appSettings.get(
            AppConstants.onboardingCompletedKey,
            defaultValue: false,
          ) as bool? ??
          false;
    } catch (_) {
      // If reading fails, show onboarding
      onboardingCompleted = false;
    }

    // ─── Run App ─────────────────────────────────────────────
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme:
              ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: onboardingCompleted
            ? const InventoryProApp()
            : SplashScreen(
                nextScreen: const OnboardingScreen()),
      ),
    );
  } catch (e) {
    runApp(_ErrorApp(error: e.toString()));
  }
}

// ─── Error App ────────────────────────────────────────────────────

class _ErrorApp extends StatelessWidget {
  final String error;
  const _ErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
                  'Initialization Error',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    // On web, reload the page
                    // On native, this is just a visual button
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