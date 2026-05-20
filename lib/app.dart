import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/providers/theme_provider.dart';
import 'core/config/app_config.dart';
import 'core/services/auth_service.dart';
import 'core/services/admin_service.dart';
import 'core/di/injection_container.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/company/screens/company_setup_screen.dart';
import 'features/inventory_selection/providers/inventory_list_provider.dart';
import 'features/inventory_management/services/inventory_service.dart' as service;
import 'features/inventory_management/providers/inventory_provider.dart';
import 'features/inventory_selection/screens/inventory_selection_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';

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

// ─── App Entry Point ──────────────────────────────────────────────
// Initialises auth then hands off to _AuthGate.

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
          body: Center(child: CircularProgressIndicator()));
    }
    return const _AuthGate();
  }
}

// ─── Auth Gate ────────────────────────────────────────────────────
// Decides which screen to show based on auth state.
//
// ✅ KEY BEHAVIOUR: When the user confirms their email (by tapping the
// link in Gmail or any email client), Supabase fires an
// onAuthStateChange event with AuthChangeEvent.signedIn.
//
// • On web (GitHub Pages): the Supabase JS SDK detects the token in
//   the URL hash automatically — no extra code needed here.
// • On native: app_links in login_screen.dart calls getSessionFromUrl()
//   which also fires onAuthStateChange.
//
// In BOTH cases the stream below triggers a rebuild of _AuthGate, which
// sees isAuthenticated == true and moves to _AdminCheckScreen /
// CompanySetupScreen — completing the confirmation flow transparently,
// regardless of which platform or email client the user clicked from.

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.requiresAuth) {
      return const InventorySelectionScreen();
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (!authProvider.isInitialized) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Please wait...'),
                ],
              ),
            ),
          );
        }

        if (!authProvider.isAuthenticated) {
          // ✅ LoginScreen handles deep links internally via app_links
          // and onAuthStateChange — no wrapper needed here.
          return const LoginScreen();
        }

        return const _AdminCheckScreen();
      },
    );
  }
}

// ─── Admin Check Screen ───────────────────────────────────────────

class _AdminCheckScreen extends StatefulWidget {
  const _AdminCheckScreen();

  @override
  State<_AdminCheckScreen> createState() => _AdminCheckScreenState();
}

class _AdminCheckScreenState extends State<_AdminCheckScreen> {
  bool _checking = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    try {
      final adminService = AdminService();
      _isAdmin = await adminService.isAdmin();
    } catch (_) {
      _isAdmin = false;
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    if (_isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.admin_panel_settings, color: Colors.blue),
              SizedBox(width: 8),
              Text('Admin Access'),
            ]),
            content: const Text(
                'You have admin privileges. Where would you like to go?'),
            actions: [
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const CompanySetupScreen()),
                    (route) => false,
                  );
                },
                child: const Text('User Dashboard'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const AdminDashboardScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.dashboard),
                label: const Text('Admin Dashboard'),
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.blue),
              ),
            ],
          ),
        );
      });
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return const CompanySetupScreen();
  }
}