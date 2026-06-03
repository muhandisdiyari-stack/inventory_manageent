import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'features/theme/bloc/theme_bloc.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/company/screens/company_setup_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';

class InventoryProApp extends StatelessWidget {
  const InventoryProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeState.mode,
          home: const _AppEntryPoint(),
        );
      },
    );
  }
}

class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  bool _authCheckDispatched = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && !_authCheckDispatched) {
        _authCheckDispatched = true;
        context.read<AuthBloc>().add(const AuthCheckRequested());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        debugPrint('🔍 _AppEntryPoint: AuthStatus = ${state.status}');

        return switch (state.status) {
          AuthStatus.unknown ||
          AuthStatus.initializing =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
          AuthStatus.authenticating =>
            const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 16), Text('Please wait...'),
            ]))),
          AuthStatus.unauthenticated => const LoginScreen(),
          AuthStatus.authenticated => _buildAuthenticatedFlow(state),
          AuthStatus.emailUnconfirmed => const _EmailConfirmationScreen(),
          AuthStatus.emailConfirmed => const _EmailConfirmedScreen(),
          AuthStatus.error => Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red), const SizedBox(height: 16),
            Text(state.error ?? 'Unknown error'), const SizedBox(height: 24),
            FilledButton(onPressed: () => context.read<AuthBloc>().add(const AuthCheckRequested()), child: const Text('Retry')),
          ]))),
        };
      },
    );
  }

  Widget _buildAuthenticatedFlow(AuthState state) {
    final onboardingCompleted = _isOnboardingCompleted();

    if (!onboardingCompleted) {
      return const OnboardingScreen();
    }

    // FIX: Always show company setup first. Admin gate is shown inside company setup if needed.
    if (state.isAdmin) {
      return const _AdminGate();
    }
    return const CompanySetupScreen();
  }

  bool _isOnboardingCompleted() {
    try {
      final appSettings = Hive.box(AppConstants.appSettingsBox);
      return appSettings.get(AppConstants.onboardingCompletedKey, defaultValue: false) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }
}

class _AdminGate extends StatefulWidget {
  const _AdminGate();

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _showAdminDialog();
    });
  }

  void _showAdminDialog() {
    if (_dialogShown || !mounted) return;
    _dialogShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, color: Colors.blue), SizedBox(width: 8), Text('Admin Access'),
        ]),
        content: const Text('You have admin privileges. Where would you like to go?'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const CompanySetupScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('User Dashboard'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                  (route) => false,
                );
              }
            },
            icon: const Icon(Icons.dashboard),
            label: const Text('Admin Dashboard'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _EmailConfirmationScreen extends StatelessWidget {
  const _EmailConfirmationScreen();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthBloc>().state;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8), Theme.of(context).colorScheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Icon(Icons.email_rounded, size: 50, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 32),
                Text('Check Your Email', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                Text('We sent a confirmation email to:\n${state.pendingEmail ?? ""}\n\nTap the confirmation link in the email to verify your account.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, height: 1.6)),
                const SizedBox(height: 40),
                SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: () => context.read<AuthBloc>().add(const AuthCheckRequested()), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Back to Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailConfirmedScreen extends StatelessWidget {
  const _EmailConfirmedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.green.shade700, Colors.green.shade500, Theme.of(context).colorScheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: const Icon(Icons.check_circle_rounded, size: 60, color: Colors.green)),
                const SizedBox(height: 32),
                Text('Email Confirmed!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                Text('Your email has been successfully verified.\nYou can now sign in to your account.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, height: 1.6)),
                const SizedBox(height: 40),
                SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: () { context.read<AuthBloc>().add(const AuthCheckRequested()); }, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.green.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Sign In Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}