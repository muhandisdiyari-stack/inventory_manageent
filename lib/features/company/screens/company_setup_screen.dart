import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/company_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../inventory_selection/screens/inventory_selection_screen.dart';
import '../../chat/bloc/unread_count_cubit.dart';
import '../../chat/screens/messages_screen.dart';
import '../../../core/utils/snackbar_utils.dart';

class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final _companyNameController = TextEditingController();
  bool _showCreateForm = false;
  String? _deletingCompanyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CompanyBloc>().add(const LoadCompanies());
      }
    });
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    super.dispose();
  }

  void _createCompany() {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) {
      SnackBarUtils.error(context, 'Company name cannot be empty');
      return;
    }
    if (name.length < 2) {
      SnackBarUtils.error(
          context, 'Company name must be at least 2 characters');
      return;
    }
    context.read<CompanyBloc>().add(CreateCompany(name));
    setState(() {
      _showCreateForm = false;
      _companyNameController.clear();
    });
  }

  void _deleteCompany(String companyId, String companyName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Company'),
        content: Text(
            'Delete "$companyName"?\n\nThis cannot be undone. All inventories, items, and data will be permanently lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _deletingCompanyId = companyId);
      context.read<CompanyBloc>().add(DeleteCompany(companyId, companyName));
    }
  }

  void _openInventories(String companyId, String companyName) {
    context.read<CompanyBloc>().add(SelectCompany(companyId));
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InventorySelectionScreen()),
    );
  }

  void _openAdminDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
    );
  }

  void _signOut() {
    context.read<AuthBloc>().add(const SignOutRequested());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAdmin = context.watch<AuthBloc>().state.isAdmin;

    return BlocListener<CompanyBloc, CompanyState>(
      listener: (context, state) {
        if (state.successMessage != null && mounted) {
          SnackBarUtils.success(context, state.successMessage!);
          context.read<CompanyBloc>().add(const ClearMessages());
          setState(() => _deletingCompanyId = null);
        }
        if (state.error != null && mounted) {
          SnackBarUtils.error(context, state.error!);
          context.read<CompanyBloc>().add(const ClearMessages());
          setState(() => _deletingCompanyId = null);
        }
        if (!state.isLoading && state.companies.isEmpty && _showCreateForm) {
          setState(() => _showCreateForm = false);
        }
      },
      child: BlocBuilder<CompanyBloc, CompanyState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Your Companies'),
              actions: [
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings),
                    tooltip: 'Admin Dashboard',
                    onPressed: _openAdminDashboard,
                  ),
                BlocBuilder<UnreadCountCubit, int>(
                  builder: (context, unread) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.message),
                          tooltip: 'Messages',
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MessagesScreen()),
                            );
                            if (mounted) {
                              context.read<UnreadCountCubit>().refresh();
                            }
                          },
                        ),
                        if (unread > 0)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              child: Center(
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign Out',
                    onPressed: _signOut),
              ],
            ),
            body: state.isLoading && state.companies.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      if (mounted) {
                        context.read<CompanyBloc>().add(const LoadCompanies());
                      }
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (state.companies.isEmpty && !_showCreateForm)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      Colors.blue.withValues(alpha: 0.2)),
                            ),
                            child: const Row(children: [
                              Icon(Icons.info_outline,
                                  color: Colors.blue, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Create a company to get started. You\'ll be able to create inventories and invite team members.',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ]),
                          ),
                        if (state.companies.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${state.companies.length} ${state.companies.length == 1 ? 'Company' : 'Companies'}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ...state.companies.map((c) {
                          final name = c['name']?.toString() ?? '';
                          final isOwner = c['is_owner'] == true ||
                              c['role']?.toString().toUpperCase() == 'OWNER';
                          final roleText = isOwner
                              ? 'OWNER'
                              : (c['role']?.toString().toUpperCase() ?? 'MEMBER');
                          final companyId = c['id']?.toString() ?? '';
                          final isDeleting = _deletingCompanyId == companyId;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: isDeleting
                                  ? null
                                  : () =>
                                      _openInventories(companyId, name),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.business,
                                        color: colorScheme.primary,
                                        size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isOwner
                                                ? Colors.amber
                                                    .withValues(alpha: 0.2)
                                                : Colors.grey
                                                    .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            roleText,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isOwner
                                                  ? Colors.amber.shade800
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isDeleting)
                                    const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                  else if (isOwner)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      tooltip: 'Delete company',
                                      onPressed: () =>
                                          _deleteCompany(companyId, name),
                                    ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right,
                                      color: Colors.grey[400]),
                                ]),
                              ),
                            ),
                          );
                        }),
                        if (state.companies.isEmpty && !_showCreateForm)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(Icons.business_outlined,
                                    size: 40,
                                    color: colorScheme.primary),
                              ),
                              const SizedBox(height: 16),
                              Text('No Companies Yet',
                                  style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(
                                'Create a company to get started or wait for an invitation',
                                style: TextStyle(color: Colors.grey[500]),
                                textAlign: TextAlign.center,
                              ),
                            ]),
                          ),
                        if (_showCreateForm)
                          Card(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.add_business,
                                          color: colorScheme.primary,
                                          size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('New Company',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16)),
                                  ]),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _companyNameController,
                                    autofocus: true,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: InputDecoration(
                                      hintText: 'Enter company name',
                                      prefixIcon:
                                          const Icon(Icons.business),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      filled: true,
                                    ),
                                    onSubmitted: (_) => _createCompany(),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(() {
                                          _showCreateForm = false;
                                          _companyNameController.clear();
                                        }),
                                        style: OutlinedButton.styleFrom(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      12)),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _createCompany,
                                        style: FilledButton.styleFrom(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      12)),
                                        ),
                                        child: const Text('Create'),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        if (!_showCreateForm) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => setState(() {
                                _showCreateForm = true;
                                _companyNameController.clear();
                              }),
                              icon: const Icon(Icons.add_business),
                              label: const Text('Create New Company'),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}