import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/inventory_management/models/inventory_item.dart';
import 'features/inventory_management/models/inventory_settings.dart';
import 'features/inventory_management/services/inventory_service.dart';
import 'features/inventory_management/services/demo_data_service.dart';
import 'core/constants/app_constants.dart';
import 'app.dart';

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Hive for Flutter
    // This works for all platforms including web (IndexedDB)
    await Hive.initFlutter();

    // Register Hive adapters
    // These must be registered before opening any boxes
    Hive.registerAdapter(InventoryItemAdapter());
    Hive.registerAdapter(FieldConfigAdapter());
    Hive.registerAdapter(InventorySettingsAdapter());

    // Open required Hive boxes
    // These boxes persist data locally on the device
    await Hive.openBox(AppConstants.appSettingsBox);
    await Hive.openBox(AppConstants.inventoriesListBox);

    // Load demo data if demo mode is enabled
    if (AppConstants.autoLoadDemoData) {
      await DemoDataService.loadDemoData();
    }
  } catch (e) {
    // If Hive initialization fails, show an error screen
    runApp(_ErrorApp(error: e.toString()));
    return;
  }

  // Create the inventory service
  // This service manages all business logic and data operations
  final inventoryService = InventoryService();

  // Run the app
  runApp(InventoryProApp(inventoryService: inventoryService));
}

/// Error screen displayed when app initialization fails
class _ErrorApp extends StatelessWidget {
  final String error;

  const _ErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Error icon
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

                // Error title
                Text(
                  'Initialization Error',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 12),

                // Error message
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 24),

                // Retry button
                FilledButton.icon(
                  onPressed: () {
                    // Reload the app
                    // In a real app, you might want to restart the initialization
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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