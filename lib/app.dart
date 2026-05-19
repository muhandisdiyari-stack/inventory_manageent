import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
import 'features/onboarding/screens/splash_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';

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
        // Theme provider
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        
        // Inventory list provider
        ChangeNotifierProvider(create: (_) => InventoryListProvider()),
        
        // Core services as value providers
        Provider<service.InventoryService>.value(value: inventoryService),
        Provider<AuthService>.value(value: InjectionContainer.authService),
        
        // Auth provider (from DI)
        ...InjectionContainer.registerChangeNotifierProviders(),
        
        // Inventory provider with proper proxy
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
            
            // Only trigger inventory selection if it actually changed
            final currentId = previous.currentInventoryId;
            final newId = listProvider.selectedInventoryId;
            
            if (newId != null && newId != currentId) {
              // Use microtask to avoid build-during-build issues
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
            // Global error handler
            builder: (context, child) {
              // Wrap everything in a safe area
              return child ?? const SizedBox.shrink();
            },
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
  String? _error;

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
        
        // Verify session if we have a cached user
        if (authProvider.isAuthenticated && AppConfig.useSupabase) {
          try {
            final isValid = await InjectionContainer
                .supabaseClient
                .verifySession();
            
            if (!isValid && mounted) {
              await authProvider.signOut();
            }
          } catch (e) {
            debugPrint('Session verification error: $e');
            // Allow offline use
          }
        }
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('Initialization error: $e');
    }
    
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Failed to initialize'),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _isInitializing = true;
                    _error = null;
                  });
                  _initialize();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return const _HomeScreen();
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    // Auth check
    if (AppConfig.requiresAuth) {
      final authProvider = context.watch<AuthProvider>();
      
      if (!authProvider.isAuthenticated) {
        return const LoginScreen();
      }
      
      return const CompanySetupScreen();
    }

    // Onboarding check
    bool onboardingCompleted = false;
    try {
      final appSettings = Hive.box(AppConstants.appSettingsBox);
      onboardingCompleted = appSettings.get(
        AppConstants.onboardingCompletedKey, 
        defaultValue: false,
      ) as bool? ?? false;
    } catch (e) {
      debugPrint('Error reading onboarding status: $e');
    }

    if (!onboardingCompleted) {
      return const SplashScreen(nextScreen: OnboardingScreen());
    }

    return const SplashScreen(nextScreen: InventorySelectionScreen());
  }
}