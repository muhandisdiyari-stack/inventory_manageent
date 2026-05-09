import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'features/inventory_selection/providers/inventory_list_provider.dart';
import 'features/inventory_management/services/inventory_service.dart' as service;
import 'features/inventory_management/providers/inventory_provider.dart';
import 'features/inventory_selection/screens/inventory_selection_screen.dart';
import 'core/providers/theme_provider.dart';

class InventoryProApp extends StatelessWidget {
  final service.InventoryService inventoryService;

  const InventoryProApp({super.key, required this.inventoryService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Add ThemeProvider for live theme switching
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Inventory Pro',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // Fixed: Use reactive ThemeProvider for live theme switching
            themeMode: themeProvider.themeMode,
            home: const InventorySelectionScreen(),
          );
        },
      ),
    );
  }
}