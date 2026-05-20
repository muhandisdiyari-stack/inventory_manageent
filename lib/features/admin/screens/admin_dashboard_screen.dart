import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/admin_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/admin_stats_card.dart';
import '../widgets/users_management.dart';
import '../widgets/companies_management.dart';
import '../widgets/audit_log_viewer.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final AdminService _adminService;

  bool _isAdmin = false;
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _adminService = AdminService();
    _tabController = TabController(length: 4, vsync: this);
    _checkAdmin();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final isAdmin = await _adminService.isAdmin();

    if (!mounted) return;
    _isAdmin = isAdmin;

    if (_isAdmin) {
      final stats = await _adminService.getStatistics();
      if (!mounted) return;
      _stats = stats;

      // Notify the currently-logged-in admin (not a hardcoded ID).
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null) {
        await _adminService.sendNotification(
          currentUserId,
          'Admin Login',
          'You logged into the admin dashboard',
        );
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _refreshStats() async {
    final stats = await _adminService.getStatistics();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  void _signOut() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Dashboard')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.security, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _refreshStats),
          IconButton(
              icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          labelColor: colorScheme.primary,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Users', icon: Icon(Icons.people)),
            Tab(text: 'Companies', icon: Icon(Icons.business)),
            Tab(text: 'Audit Log', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverview(colorScheme),
          UsersManagement(adminService: _adminService),
          CompaniesManagement(adminService: _adminService),
          AuditLogViewer(adminService: _adminService),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUserDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Create User'),
      ),
    );
  }

  Widget _buildOverview(ColorScheme colorScheme) {
    final hasData = _stats.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _refreshStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dashboard Overview',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (!hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Could not load statistics',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [
                AdminStatsCard(
                    title: 'Total Users',
                    value: '${_stats['total_users'] ?? 0}',
                    icon: Icons.people,
                    color: Colors.blue),
                AdminStatsCard(
                    title: 'Pending Approval',
                    value: '${_stats['pending_users'] ?? 0}',
                    icon: Icons.pending,
                    color: Colors.orange),
                AdminStatsCard(
                    title: 'Companies',
                    value: '${_stats['total_companies'] ?? 0}',
                    icon: Icons.business,
                    color: Colors.purple),
                AdminStatsCard(
                    title: 'Items',
                    value: '${_stats['total_items'] ?? 0}',
                    icon: Icons.inventory_2,
                    color: Colors.teal),
                AdminStatsCard(
                    title: 'Labels',
                    value: '${_stats['total_labels'] ?? 0}',
                    icon: Icons.label,
                    color: Colors.indigo),
                AdminStatsCard(
                    title: 'Pending Invitations',
                    value: '${_stats['pending_invitations'] ?? 0}',
                    icon: Icons.mail,
                    color: Colors.amber),
              ],
            ),
            const SizedBox(height: 24),
            Text('Today',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              _buildMiniStat(
                  'New Users',
                  '${_stats['users_today'] ?? 0}',
                  Icons.person_add,
                  colorScheme.primary),
              const SizedBox(width: 16),
              _buildMiniStat(
                  'New Companies',
                  '${_stats['companies_today'] ?? 0}',
                  Icons.add_business,
                  colorScheme.secondary),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(label,
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 12)),
                ]),
          ]),
        ),
      ),
    );
  }

  void _showCreateUserDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    String selectedRole = 'staff';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.person_add),
            SizedBox(width: 8),
            Text('Create New User'),
          ]),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (v) => !(v?.contains('@') == true)
                      ? 'Valid email required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                    helperText: 'Min 8 characters',
                  ),
                  validator: (v) => (v?.length ?? 0) < 8
                      ? 'Min 8 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'staff', child: Text('Staff')),
                    DropdownMenuItem(
                        value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(
                        value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                        value: 'owner', child: Text('Owner')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedRole = v!),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                // Capture messenger before async gap.
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);

                final result = await _adminService.createUser(
                  emailController.text.trim(),
                  passwordController.text,
                  nameController.text.trim(),
                  selectedRole,
                );

                // Use outer widget's mounted, not the disposed dialog ctx.
                if (!mounted) return;
                final success = result['success'] == true;
                messenger.showSnackBar(SnackBar(
                  content:
                      Text(result['message'] ?? 'User created'),
                  backgroundColor:
                      success ? Colors.green : Colors.red,
                ));
                if (success) _refreshStats();
              },
              icon: const Icon(Icons.check),
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}