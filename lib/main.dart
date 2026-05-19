import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/inventory_management/models/inventory_item.dart';
import 'features/inventory_management/models/inventory_settings.dart';
import 'features/inventory_management/services/inventory_service.dart';
import 'features/inventory_management/services/demo_data_service.dart';
import 'core/constants/app_constants.dart';
import 'core/config/app_config.dart';
import 'core/services/activity_log_service.dart';
import 'core/di/injection_container.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Validate configuration
    AppConfig.validate();

    // Initialize Supabase with error handling
    if (AppConfig.useSupabase) {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
        debugPrint('✅ Supabase initialized successfully');
      } catch (e) {
        debugPrint('⚠️ Supabase initialization failed: $e');
        // Continue in offline mode if not production
        if (AppConfig.isProduction) {
          runApp(_ErrorApp(error: 'Failed to connect to server: $e'));
          return;
        }
      }
    }

    // Initialize Hive
    await Hive.initFlutter();
    
    // Register adapters
    Hive.registerAdapter(InventoryItemAdapter());
    Hive.registerAdapter(FieldConfigAdapter());
    Hive.registerAdapter(InventorySettingsAdapter());

    // Open required boxes with error handling for each
    final boxesToOpen = [
      AppConstants.appSettingsBox,
      AppConstants.inventoriesListBox,
      AppConstants.activityLogsBox,
    ];

    for (final boxName in boxesToOpen) {
      try {
        await Hive.openBox(boxName);
      } catch (e) {
        debugPrint('⚠️ Failed to open box $boxName: $e');
        // Create a fresh box if corrupted
        try {
          await Hive.deleteBoxFromDisk(boxName);
          await Hive.openBox(boxName);
          debugPrint('🔄 Recreated corrupted box: $boxName');
        } catch (e2) {
          debugPrint('❌ Fatal: Cannot create box $boxName: $e2');
          runApp(_ErrorApp(error: 'Storage initialization failed: $e2'));
          return;
        }
      }
    }

    // Initialize services
    try {
      await ActivityLogService().initialize();
      await InjectionContainer.initialize();
    } catch (e) {
      debugPrint('⚠️ Service initialization error: $e');
      if (AppConfig.isProduction) {
        runApp(_ErrorApp(error: 'Service initialization failed: $e'));
        return;
      }
    }

    // Load demo data if enabled (will only load if box is empty)
    try {
      if (AppConstants.autoLoadDemoData) {
        await DemoDataService.loadDemoData();
      }
    } catch (e) {
      debugPrint('⚠️ Demo data loading failed: $e');
      // Non-fatal - app can continue without demo data
    }
  } catch (e) {
    debugPrint('❌ Fatal initialization error: $e');
    runApp(_ErrorApp(error: e.toString()));
    return;
  }

  // Create inventory service
  final inventoryService = InventoryService();

  // Check onboarding status with null safety
  bool onboardingCompleted = false;
  try {
    final appSettings = Hive.box(AppConstants.appSettingsBox);
    onboardingCompleted = appSettings.get(
      AppConstants.onboardingCompletedKey, 
      defaultValue: false,
    ) as bool? ?? false;
  } catch (e) {
    debugPrint('⚠️ Could not read onboarding status: $e');
  }

  // Run the app
  runApp(
    InventoryProApp(
      inventoryService: inventoryService,
      showOnboarding: !onboardingCompleted,
    ),
  );

  // Log version info
  debugPrint('🚀 Inventory Pro v${AppConstants.appVersion} started');
}

/// Error screen shown when initialization fails
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
                  child: const Icon(
                    Icons.error_outline, 
                    size: 40, 
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Initialization Error',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    // Could add retry logic here
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