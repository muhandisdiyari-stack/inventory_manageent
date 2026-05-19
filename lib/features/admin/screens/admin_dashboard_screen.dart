import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/admin_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/admin_stats_card.dart';
import '../widgets/users_management.dart';
import '../widgets/companies_management.dart';
import '../widgets/audit_log_viewer.dart';
import '../widgets/notifications_panel.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _adminService = AdminService();
  bool _isAdmin = false;
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _checkAdmin();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    setState(() => _isLoading = true);
    _isAdmin = await _adminService.isAdmin();
    if (_isAdmin) {
      _stats = await _adminService.getStatistics();
    }
    setState(() => _isLoading = false);
  }

  void _signOut() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
              Text('Access Denied', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('You do not have admin privileges.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => _isLoading = true);
              _stats = await _adminService.getStatistics();
              setState(() => _isLoading = false);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Users', icon: Icon(Icons.people)),
            Tab(text: 'Companies', icon: Icon(Icons.business)),
            Tab(text: 'Audit Log', icon: Icon(Icons.history)),
            Tab(text: 'Notifications', icon: Icon(Icons.notifications)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverview(),
          const UsersManagement(),
          const CompaniesManagement(),
          const AuditLogViewer(),
          const NotificationsPanel(),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          
          // Stats Grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              AdminStatsCard(
                title: 'Total Users',
                value: '${_stats['total_users'] ?? 0}',
                icon: Icons.people,
                color: Colors.blue,
              ),
              AdminStatsCard(
                title: 'Active Users',
                value: '${_stats['active_users'] ?? 0}',
                icon: Icons.person,
                color: Colors.green,
              ),
              AdminStatsCard(
                title: 'Pending Approval',
                value: '${_stats['pending_users'] ?? 0}',
                icon: Icons.pending,
                color: Colors.orange,
              ),
              AdminStatsCard(
                title: 'Companies',
                value: '${_stats['total_companies'] ?? 0}',
                icon: Icons.business,
                color: Colors.purple,
              ),
              AdminStatsCard(
                title: 'Items',
                value: '${_stats['total_items'] ?? 0}',
                icon: Icons.inventory_2,
                color: Colors.teal,
              ),
              AdminStatsCard(
                title: 'Labels',
                value: '${_stats['total_labels'] ?? 0}',
                icon: Icons.label,
                color: Colors.indigo,
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Recent activity
          Text('Today', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniStat('New Users', '${_stats['users_today'] ?? 0}', Icons.person_add, colorScheme.primary),
              const SizedBox(width: 16),
              _buildMiniStat('New Companies', '${_stats['companies_today'] ?? 0}', Icons.add_business, colorScheme.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}