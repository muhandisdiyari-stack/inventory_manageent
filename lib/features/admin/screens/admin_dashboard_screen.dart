import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/admin_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AdminBloc>().add(const LoadAdminData());
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _signOut() {
    context.read<AuthBloc>().add(const SignOutRequested());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocListener<AdminBloc, AdminState>(
      listener: (context, state) {
        if (state.successMessage != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(state.successMessage!),
                behavior: SnackBarBehavior.floating),
          );
          context.read<AdminBloc>().add(const ClearAdminMessages());
        }
        if (state.error != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating),
          );
          context.read<AdminBloc>().add(const ClearAdminMessages());
        }
      },
      child: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state.isLoading && !state.isAdmin) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }

          if (!state.isAdmin && !state.isLoading) {
            return Scaffold(
              appBar: AppBar(title: const Text('Admin Dashboard')),
              body: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.security, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text('Access Denied',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ]),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('Admin Dashboard'),
              backgroundColor: colorScheme.primaryContainer,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      context.read<AdminBloc>().add(const LoadAdminData()),
                ),
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
                _buildOverview(state, colorScheme),
                const UsersManagement(),
                const CompaniesManagement(),
                const AuditLogViewer(),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _showCreateUserDialog(),
              icon: const Icon(Icons.person_add),
              label: const Text('Create User'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverview(AdminState state, ColorScheme colorScheme) {
    final stats = state.statistics;
    final hasData = stats.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        if (mounted) {
          context.read<AdminBloc>().add(const LoadAdminData());
        }
      },
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
                  Text('Could not load statistics',
                      style:
                          TextStyle(color: Colors.orange, fontSize: 13)),
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
                    value: '${stats['total_users'] ?? 0}',
                    icon: Icons.people,
                    color: Colors.blue),
                AdminStatsCard(
                    title: 'Pending Approval',
                    value: '${stats['pending_users'] ?? 0}',
                    icon: Icons.pending,
                    color: Colors.orange),
                AdminStatsCard(
                    title: 'Companies',
                    value: '${stats['total_companies'] ?? 0}',
                    icon: Icons.business,
                    color: Colors.purple),
                AdminStatsCard(
                    title: 'Items',
                    value: '${stats['total_items'] ?? 0}',
                    icon: Icons.inventory_2,
                    color: Colors.teal),
                AdminStatsCard(
                    title: 'Labels',
                    value: '${stats['total_labels'] ?? 0}',
                    icon: Icons.label,
                    color: Colors.indigo),
                AdminStatsCard(
                    title: 'Pending Invitations',
                    value: '${stats['pending_invitations'] ?? 0}',
                    icon: Icons.mail,
                    color: Colors.amber),
              ],
            ),
            const SizedBox(height: 24),
            Text('Today', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              _buildMiniStat('New Users', '${stats['users_today'] ?? 0}',
                  Icons.person_add, colorScheme.primary),
              const SizedBox(width: 16),
              _buildMiniStat('New Companies',
                  '${stats['companies_today'] ?? 0}',
                  Icons.add_business, colorScheme.secondary),
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
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              Text(label,
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: 12)),
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
    String selectedRole = 'data_operator';
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
                    labelText: 'Full Name',
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
                        value: 'data_operator',
                        child: Text('Data Operator')),
                    DropdownMenuItem(
                        value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                        value: 'viewer', child: Text('Viewer')),
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
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                context.read<AdminBloc>().add(CreateAdminUser(
                      email: emailController.text.trim(),
                      password: passwordController.text,
                      displayName: nameController.text.trim(),
                      role: selectedRole,
                    ));
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