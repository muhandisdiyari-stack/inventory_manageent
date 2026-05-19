import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/providers/theme_provider.dart';
import 'core/config/app_config.dart';
import 'core/services/auth_service.dart';
import 'core/di/injection_container.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/company/screens/company_setup_screen.dart';
import 'features/inventory_selection/providers/inventory_list_provider.dart';
import 'features/inventory_management/services/inventory_service.dart' as service;
import 'features/inventory_management/providers/inventory_provider.dart';
import 'features/inventory_selection/screens/inventory_selection_screen.dart';

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
        Provider<AuthService>.value(value: InjectionContainer.authService),
        ...InjectionContainer.registerChangeNotifierProviders(),
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
            final newId = listProvider.selectedInventoryId;
            if (newId != null && newId != previous.currentInventoryId) {
              Future.microtask(() => previous.selectInventory(newId));
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
            home: const _AppEntryPoint(),
          );
        },
      ),
    );
  }
}

class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (AppConfig.requiresAuth) {
        final authProvider = context.read<AuthProvider>();
        await authProvider.initialize();
      }
    } catch (_) {}
    if (mounted) setState(() => _isInitializing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const _AuthGate();
  }
}

// FIXED: Proper auth gate that navigates on sign out
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.requiresAuth) {
      return const InventorySelectionScreen();
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Show loading while initializing
        if (!authProvider.isInitialized || authProvider.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If not authenticated, show login
        if (!authProvider.isAuthenticated) {
          return const LoginScreen();
        }

        // If authenticated, show company setup
        return const CompanySetupScreen();
      },
    );
  }
}