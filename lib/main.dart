import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/inventory_management/models/inventory_item.dart';
import 'features/inventory_management/models/inventory_settings.dart';
import 'features/inventory_management/services/inventory_service.dart';
import 'features/inventory_management/services/demo_data_service.dart';
import 'core/constants/app_constants.dart';
import 'core/services/activity_log_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Hive for Flutter
    await Hive.initFlutter();

    // Register Hive adapters
    Hive.registerAdapter(InventoryItemAdapter());
    Hive.registerAdapter(FieldConfigAdapter());
    Hive.registerAdapter(InventorySettingsAdapter());

    // Open required Hive boxes
    await Hive.openBox(AppConstants.appSettingsBox);
    await Hive.openBox(AppConstants.inventoriesListBox);
    await Hive.openBox(AppConstants.activityLogsBox);

    // Initialize activity log service
    await ActivityLogService().initialize();

    // Load demo data if demo mode is enabled
    if (AppConstants.autoLoadDemoData) {
      await DemoDataService.loadDemoData();
    }
  } catch (e) {
    runApp(_ErrorApp(error: e.toString()));
    return;
  }

  // Create the inventory service
  final inventoryService = InventoryService();

  // Check if onboarding has been completed
  final appSettings = Hive.box(AppConstants.appSettingsBox);
  final onboardingCompleted =
      appSettings.get(AppConstants.onboardingCompletedKey, defaultValue: false) as bool;

  // Run the app
  runApp(
    InventoryProApp(
      inventoryService: inventoryService,
      showOnboarding: !onboardingCompleted,
    ),
  );
}

/// Error screen displayed when app initialization fails
class _ErrorApp extends StatelessWidget {
  final String error;

  const _ErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}