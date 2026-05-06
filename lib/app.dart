import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'features/inventory_selection/providers/inventory_list_provider.dart';
import 'features/inventory_management/services/inventory_service.dart' as service;
import 'features/inventory_management/providers/inventory_provider.dart';
import 'features/inventory_selection/screens/inventory_selection_screen.dart';

class InventoryProApp extends StatelessWidget {
  final service.InventoryService inventoryService;

  const InventoryProApp({super.key, required this.inventoryService});

  @override
  Widget build(BuildContext context) {
    // ── Read persisted dark-mode preference ───────────────────────
    final appSettings = Hive.box('app_settings');
    final isDarkMode =
        appSettings.get(AppConstants.darkModeKey, defaultValue: false) as bool;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InventoryListProvider()),
        Provider<service.InventoryService>.value(value: inventoryService),
        ChangeNotifierProxyProvider<InventoryListProvider, InventoryProvider>(
          create: (context) => InventoryProvider(
            context.read<service.InventoryService>(),
            context.read<InventoryListProvider>(),
          ),
          update: (context, listProvider, previous) {
            // SAFE: handle null on first frame / hot reload
            if (previous == null) {
              return InventoryProvider(
                context.read<service.InventoryService>(),
                listProvider,
              );
            }
            
            final id = listProvider.selectedInventoryId;
            if (id != null) {
              // Defer the selectInventory call to avoid build-phase state changes
              WidgetsBinding.instance.addPostFrameCallback((_) {
                previous.selectInventory(id);
              });
            }
            return previous;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Inventory Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: const InventorySelectionScreen(),
      ),
    );
  }
}