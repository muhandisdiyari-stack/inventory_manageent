import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../../company/screens/company_setup_screen.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../../core/services/admin_service.dart';

/// LoginScreen handles three states:
///
///  1. Normal login / sign-up form.
///  2. "Check your email" confirmation screen shown after successful sign-up.
///  3. "Email confirmed!" success screen shown when the deep-link callback
///     is received from Supabase (user clicked the link in their email).
///
/// Deep-link flow (Android / iOS):
///   User taps "Confirm Email" in Gmail / Mail app
///     → OS opens the app via the "inventory://auth/callback" scheme
///       (registered in AndroidManifest.xml / Info.plist)
///     → AppLinks picks up the URI in initState
///     → getSessionFromUrl() tells Supabase to exchange the token
///     → _onEmailConfirmed() is called and navigates to CompanySetupScreen.
///
/// Web flow:
///   Browser navigates to "<origin>/auth/callback?..."
///     → supabase_flutter JS SDK exchanges the token automatically
///     → onAuthStateChange fires with AuthChangeEvent.signedIn
///     → _onEmailConfirmed() is called.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ─── Controllers & keys ───────────────────────────────────────
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ─── UI state ─────────────────────────────────────────────────
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showEmailSent = false;
  bool _showEmailConfirmed = false; // ✅ NEW: deep-link confirmed state
  String _registeredEmail = '';
  String? _errorMessage;

  // ─── Deep-link listener ───────────────────────────────────────
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _listenToAuthChanges();
  }

  /// ✅ FIX: Listen for the "inventory://auth/callback" deep link that
  /// Supabase embeds in the confirmation email.  Works on Android, iOS,
  /// Windows, macOS and Linux.
  void _initDeepLinks() {
    _appLinks = AppLinks();

    // App was already running when the link was tapped.
    _appLinks.uriLinkStream.listen(
      (uri) => _handleDeepLink(uri),
      onError: (e) => debugPrint('Deep link stream error: $e'),
    );

    // App was cold-started by tapping the link.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    }).catchError((e) => debugPrint('Initial deep link error: $e'));
  }

  /// ✅ FIX: Listen for Supabase auth state changes.  On web the SDK
  /// automatically exchanges the token from the URL hash; we just need to
  /// react when it fires signedIn after email confirmation.
  void _listenToAuthChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.userUpdated) {
        final user = data.session?.user;
        if (user != null && user.emailConfirmedAt != null) {
          _onEmailConfirmed();
        }
      }
    });
  }

  /// Processes a deep link URI received from the OS.
  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint('📲 Deep link received: $uri');
    try {
      // Let supabase_flutter exchange the token and create a session.
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      // _listenToAuthChanges will call _onEmailConfirmed once the session
      // is established.
    } catch (e) {
      debugPrint('Deep link handling error: $e');
      if (mounted) {
        setState(() => _errorMessage =
            'Email confirmation failed. Please try again or contact support.');
      }
    }
  }

  /// Called once the Supabase session is confirmed (deep link or web).
  void _onEmailConfirmed() {
    if (!mounted) return;
    setState(() {
      _showEmailSent = false;
      _showEmailConfirmed = true;
      _isLoading = false;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  // ─── Submit ───────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final navigator = Navigator.of(context);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();

      if (_isLogin) {
        // ── Sign In ──────────────────────────────────────────────
        final success = await authProvider.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );

        if (!mounted) return;

        if (success) {
          final user = authProvider.currentUser;

          if (user != null && !user.isApproved) {
            setState(() {
              _errorMessage = 'Your account is pending approval.';
              _isLoading = false;
            });
            await authProvider.signOut();
            return;
          }

          final adminService = AdminService();
          final isAdmin = await adminService.isAdmin();

          if (!mounted) return;

          if (isAdmin) {
            _showAdminNavigationDialog(navigator);
          } else {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => const CompanySetupScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _errorMessage =
                authProvider.error ?? 'Invalid email or password';
            _isLoading = false;
          });
        }
      } else {
        // ── Register ─────────────────────────────────────────────
        final result = await authProvider.register(
          _emailController.text.trim(),
          _passwordController.text,
          _displayNameController.text.trim(),
        );

        if (!mounted) return;

        if (result.success) {
          if (result.requiresEmailConfirmation) {
            setState(() {
              _registeredEmail =
                  result.email ?? _emailController.text.trim();
              _showEmailSent = true;
              _isLoading = false;
            });
          } else {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => const CompanySetupScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Registration failed';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred';
          _isLoading = false;
        });
      }
    }
  }

  // ─── Admin helpers ────────────────────────────────────────────

  void _showAdminNavigationDialog(NavigatorState navigator) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.blue),
            SizedBox(width: 8),
            Text('Admin Access'),
          ],
        ),
        content: const Text(
            'You have admin privileges. Where would you like to go?'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              navigator.pushAndRemoveUntil(
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
              navigator.pushAndRemoveUntil(
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
    setState(() => _isLoading = false);
  }

  Future<void> _goToAdminLogin() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _AdminLoginDialog(),
    );

    if (result != null && mounted) {
      setState(() {
        _emailController.text = result['email'] ?? '';
        _passwordController.text = result['password'] ?? '';
        _isLogin = true;
      });
      _submit();
    }
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ✅ NEW: Email confirmed via deep link → show success screen.
    if (_showEmailConfirmed) {
      return _buildEmailConfirmedScreen(colorScheme);
    }

    // Waiting for user to click confirmation link.
    if (_showEmailSent) {
      return _buildEmailConfirmationScreen(colorScheme);
    }

    // Normal login / register form.
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.8),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(Icons.inventory_2_rounded,
                              size: 40, color: colorScheme.primary),
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text(
                        'Inventory Pro',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin
                            ? 'Welcome back! Sign in to continue'
                            : 'Create your account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                Colors.white.withValues(alpha: 0.8),
                            fontSize: 16),
                      ),
                      const SizedBox(height: 40),

                      // Error banner
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMessage!,
                                    style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                        ),

                      // Form card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              if (!_isLogin) ...[
                                TextFormField(
                                  controller:
                                      _displayNameController,
                                  textCapitalization:
                                      TextCapitalization.words,
                                  textInputAction:
                                      TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: 'Display Name',
                                    prefixIcon:
                                        const Icon(Icons.person),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                12)),
                                    filled: true,
                                  ),
                                  validator: (v) =>
                                      (!_isLogin &&
                                              (v == null ||
                                                  v.trim().isEmpty))
                                          ? 'Enter your name'
                                          : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _emailController,
                                keyboardType:
                                    TextInputType.emailAddress,
                                textInputAction:
                                    TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon:
                                      const Icon(Icons.email),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  filled: true,
                                ),
                                validator: (v) {
                                  if (v == null ||
                                      v.trim().isEmpty) {
                                    return 'Enter your email';
                                  }
                                  if (!v.contains('@') ||
                                      !v.contains('.')) {
                                    return 'Enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: _isLogin
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                onFieldSubmitted: _isLogin
                                    ? (_) => _submit()
                                    : null,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon:
                                      const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () => setState(() =>
                                        _obscurePassword =
                                            !_obscurePassword),
                                  ),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  filled: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Enter your password';
                                  }
                                  if (v.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: FilledButton(
                                  onPressed:
                                      _isLoading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                12)),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                        )
                                      : Text(
                                          _isLogin
                                              ? 'Sign In'
                                              : 'Create Account',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight:
                                                  FontWeight.w600),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Toggle login / register
                      TextButton(
                        onPressed: () => setState(() {
                          _isLogin = !_isLogin;
                          _showEmailSent = false;
                          _errorMessage = null;
                        }),
                        child: Text(
                          _isLogin
                              ? "Don't have an account? Sign Up"
                              : 'Already have an account? Sign In',
                          style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500),
                        ),
                      ),

                      // Admin access
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _goToAdminLogin,
                        icon: const Icon(
                            Icons.admin_panel_settings,
                            size: 18),
                        label: const Text('Admin Access'),
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── "Check your email" screen ────────────────────────────────

  Widget _buildEmailConfirmationScreen(ColorScheme colorScheme) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.8),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25)),
                    child: Icon(Icons.email_rounded,
                        size: 50, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Check Your Email',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We sent a confirmation email to:\n$_registeredEmail\n\n'
                    'Tap the confirmation link in the email to verify your account. '
                    'The app will open automatically and sign you in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  // Helpful tip about Gmail on Android
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline,
                            color:
                                Colors.white.withValues(alpha: 0.8),
                            size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Clicking the link in Gmail will open this app directly.',
                            style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.8),
                                fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => setState(() {
                        _showEmailSent = false;
                        _isLogin = true;
                        _errorMessage = null;
                      }),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Back to Sign In',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── ✅ NEW: "Email confirmed!" success screen ─────────────────
  // Shown after the deep link is received and Supabase session is created.

  Widget _buildEmailConfirmedScreen(ColorScheme colorScheme) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.green.shade700,
              Colors.green.shade500,
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25)),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 60, color: Colors.green),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Email Confirmed!',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your email has been successfully verified.\nYou can now sign in to your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.6),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        // Sign the user out of the auto-created session so
                        // they explicitly log in with their credentials.
                        Supabase.instance.client.auth.signOut();
                        setState(() {
                          _showEmailConfirmed = false;
                          _isLogin = true;
                          _errorMessage = null;
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sign In Now',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Admin Login Dialog ───────────────────────────────────────────

class _AdminLoginDialog extends StatefulWidget {
  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings, color: Colors.blue),
          SizedBox(width: 8),
          Text('Admin Login'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your admin credentials to access the dashboard.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Admin Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Required' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'email': _emailController.text.trim(),
                'password': _passwordController.text,
              });
            }
          },
          icon: const Icon(Icons.login),
          label: const Text('Sign In as Admin'),
          style:
              FilledButton.styleFrom(backgroundColor: Colors.blue),
        ),
      ],
    );
  }
}