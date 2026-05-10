import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'features/inventory_selection/providers/inventory_list_provider.dart';
import 'features/inventory_management/services/inventory_service.dart' as service;
import 'features/inventory_management/providers/inventory_provider.dart';
import 'features/inventory_selection/screens/inventory_selection_screen.dart';
import 'features/onboarding/screens/splash_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'core/providers/theme_provider.dart';

class InventoryProApp extends StatelessWidget {
  final service.InventoryService inventoryService;
  final bool showOnboarding;

  const InventoryProApp({
    super.key,
    required this.inventoryService,
    this.showOnboarding = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => InventoryListProvider()),
        Provider<service.InventoryService>.value(value: inventoryService),
        ChangeNotifierProxyProvider<InventoryListProvider, InventoryProvider>(
          create: (context) => InventoryProvider(
            context.read<service.InventoryService>(),
            context.read<InventoryListProvider>(),
          ),
          update: (context, listProvider, previous) {
            if (previous == null) {
              return InventoryProvider(
                context.read<service.InventoryService>(),
                listProvider,
              );
            }

            final id = listProvider.selectedInventoryId;
            if (id != null) {
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
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: _buildHomeScreen(),
          );
        },
      ),
    );
  }

  Widget _buildHomeScreen() {
    // Always show splash screen first
    final mainScreen = showOnboarding
        ? const OnboardingScreen()
        : const InventorySelectionScreen();

    return SplashScreen(nextScreen: mainScreen);
  }
}