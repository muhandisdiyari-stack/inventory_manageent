import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../company/screens/company_setup_screen.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../../core/services/admin_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showEmailSent = false;
  String _registeredEmail = '';
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

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

          // Check if user is admin
          final adminService = AdminService();
          final isAdmin = await adminService.isAdmin();

          if (!mounted) return;

          if (isAdmin) {
            // Ask admin where to go
            _showAdminNavigationDialog(navigator);
          } else {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const CompanySetupScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _errorMessage = authProvider.error ?? 'Invalid email or password';
            _isLoading = false;
          });
        }
      } else {
        final result = await authProvider.register(
          _emailController.text.trim(),
          _passwordController.text,
          _displayNameController.text.trim(),
        );

        if (!mounted) return;

        if (result.success) {
          if (result.requiresEmailConfirmation) {
            setState(() {
              _registeredEmail = result.email ?? _emailController.text.trim();
              _showEmailSent = true;
              _isLoading = false;
            });
          } else {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const CompanySetupScreen()),
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

  // NEW: Admin navigation dialog
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
        content: const Text('You have admin privileges. Where would you like to go?'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const CompanySetupScreen()),
                (route) => false,
              );
            },
            child: const Text('User Dashboard'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.dashboard),
            label: const Text('Admin Dashboard'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
    setState(() => _isLoading = false);
  }

  // NEW: Direct admin login
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_showEmailSent) {
      return _buildEmailConfirmationScreen(colorScheme);
    }

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
                      Container(
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
                        child: Icon(Icons.inventory_2_rounded, size: 40, color: colorScheme.primary),
                      ),
                      const SizedBox(height: 32),

                      Text('Inventory Pro',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? 'Welcome back! Sign in to continue' : 'Create your account',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16),
                      ),
                      const SizedBox(height: 40),

                      // Error message
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                            ],
                          ),
                        ),

                      // Login Form Card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              if (!_isLogin) ...[
                                TextFormField(
                                  controller: _displayNameController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: 'Display Name',
                                    prefixIcon: const Icon(Icons.person),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                  ),
                                  validator: (v) => (!_isLogin && (v == null || v.trim().isEmpty)) ? 'Enter your name' : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: const Icon(Icons.email),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Enter your email';
                                  if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                                onFieldSubmitted: _isLogin ? (_) => _submit() : null,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Enter your password';
                                  if (v.length < 6) return 'Password must be at least 6 characters';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: FilledButton(
                                  onPressed: _isLoading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : Text(_isLogin ? 'Sign In' : 'Create Account',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Toggle Login/Register
                      TextButton(
                        onPressed: () => setState(() {
                          _isLogin = !_isLogin;
                          _showEmailSent = false;
                          _errorMessage = null;
                        }),
                        child: Text(
                          _isLogin ? "Don't have an account? Sign Up" : 'Already have an account? Sign In',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                        ),
                      ),

                      // ─── NEW: Admin Access Button ─────────────────
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _goToAdminLogin,
                        icon: const Icon(Icons.admin_panel_settings, size: 18),
                        label: const Text('Admin Access'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.7),
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
                    width: 100, height: 100,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
                    child: Icon(Icons.email_rounded, size: 50, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 32),
                  Text('Check Your Email',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Text(
                    'We sent a confirmation email to:\n$_registeredEmail\n\nPlease check your inbox and click the confirmation link.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: FilledButton(
                      onPressed: () => setState(() { _showEmailSent = false; _isLogin = true; _errorMessage = null; }),
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Go to Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

// ─── NEW: Admin Login Dialog ─────────────────────────────────────

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
            const Text('Enter your admin credentials to access the dashboard.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Admin Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
          style: FilledButton.styleFrom(backgroundColor: Colors.blue),
        ),
      ],
    );
  }
}