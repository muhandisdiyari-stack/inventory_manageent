import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/company_bloc.dart';

class CompanySettingsScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;
  const CompanySettingsScreen({
    super.key,
    this.inventoryId = 'default',
    this.inventoryName = '',
  });

  @override
  State<CompanySettingsScreen> createState() =>
      _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _emailController = TextEditingController();

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
    _emailController.dispose();
    super.dispose();
  }

  bool get _canManageMembers {
    final state = context.read<CompanyBloc>().state;
    final company = state.selectedCompany;
    if (company == null) return false;

    final role = (company['role'] ?? company['user_role'] ??
            company['membership_role'])
        .toString()
        .toLowerCase();

    return role == 'owner' || role == 'admin';
  }

  String? get _selectedCompanyId {
    final state = context.read<CompanyBloc>().state;
    final company = state.selectedCompany;
    if (company == null) return null;

    return (company['id'] ?? company['company_id'] ?? '').toString();
  }

  void _inviteUser() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid email')),
      );
      return;
    }

    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No company selected. Please go back and select a company first.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    context.read<CompanyBloc>().add(CreateInvitation(
          companyId: companyId,
          email: email,
        ));
    _emailController.clear();
  }

  void _cancelInvitation(String invitationId) {
    context.read<CompanyBloc>().add(CancelInvitation(invitationId));
  }

  void _removeMember(String memberId, String memberName) async {
    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $memberName from this company?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<CompanyBloc>().add(RemoveMember(
            memberId: memberId,
            companyId: companyId,
            memberName: memberName,
          ));
    }
  }

void _changeRole(String memberId, String currentRole) async {
    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change Role'),
        children: ['data_operator', 'admin', 'viewer']  // ✅ FIXED: was 'staff', 'manager', 'admin'
            .map((role) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, role),
                  child: Row(
                    children: [
                      if (role == currentRole)
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Text(role == 'data_operator' 
                          ? 'Data Operator' 
                          : role[0].toUpperCase() + role.substring(1)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (newRole != null && newRole != currentRole && mounted) {
      context.read<CompanyBloc>().add(ChangeMemberRole(
            memberId: memberId,
            companyId: companyId,
            newRole: newRole,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<CompanyBloc, CompanyState>(
      listener: (context, state) {
        if (state.successMessage != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<CompanyBloc>().add(const ClearMessages());
        }
        if (state.error != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<CompanyBloc>().add(const ClearMessages());
        }
      },
      child: BlocBuilder<CompanyBloc, CompanyState>(
        builder: (context, state) {
          if (state.isLoading && state.companies.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Company Settings')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (state.selectedCompany == null && !state.isLoading) {
            return Scaffold(
              appBar: AppBar(title: const Text('Company Settings')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.business_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'No company selected',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please go back and select a company first.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(widget.inventoryName.isNotEmpty
                  ? '${widget.inventoryName} - Members'
                  : 'Company Settings'),
            ),
            body: RefreshIndicator(
              onRefresh: () async {
                if (mounted) {
                  context.read<CompanyBloc>().add(const LoadCompanies());
                }
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Company info card
                  if (state.selectedCompany != null)
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.business,
                                color:
                                    Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Company: ${state.selectedCompany!['name'] ?? 'Unknown'}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Members Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.people, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Company Members (${state.members.length})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Company-level members can see all inventories. '
                            'Use Inventory Settings to set per-inventory permissions.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 12),
                          if (state.members.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'No members yet',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ...state.members.map((member) {
                              final name = (member['display_name'] ??
                                      member['email'] ??
                                      'Unknown')
                                  .toString();
                              final role =
                                  (member['role'] ?? 'staff').toString();
                              final memberId =
                                  member['id']?.toString() ?? '';
                              final isOwner = role == 'owner';

                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(name),
                                subtitle: Text('Role: ${role.toUpperCase()}'),
                                trailing: _canManageMembers && !isOwner
                                    ? PopupMenuButton<String>(
                                        onSelected: (action) {
                                          if (action == 'change_role') {
                                            _changeRole(memberId, role);
                                          } else if (action == 'remove') {
                                            _removeMember(memberId, name);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'change_role',
                                            child: Text('Change Role'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text(
                                              'Remove',
                                              style: TextStyle(
                                                  color: Colors.red),
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  // Invite Member Card
                  if (_canManageMembers) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_add,
                                    color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Invite Company Member',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'They will automatically join when they sign in with this email',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: 'Enter email address',
                                prefixIcon: const Icon(Icons.email),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _inviteUser,
                                icon: const Icon(Icons.send),
                                label: const Text('Send Invitation'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Pending Invitations Card
                  if (state.invitations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.pending_actions,
                                    color: Colors.orange),
                                const SizedBox(width: 8),
                                Text(
                                  'Pending Invitations (${state.invitations.length})',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...state.invitations.map((inv) {
                              final email =
                                  (inv['email'] ?? '').toString();
                              final invId = inv['id']?.toString() ?? '';
                              final status =
                                  (inv['status'] ?? 'pending').toString();

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Colors.orange.withValues(alpha: 0.1),
                                  child: const Icon(Icons.person_outline,
                                      color: Colors.orange, size: 20),
                                ),
                                title: Text(email),
                                subtitle: Text('Status: $status'),
                                trailing: _canManageMembers
                                    ? IconButton(
                                        icon: const Icon(Icons.cancel,
                                            color: Colors.red),
                                        onPressed: () =>
                                            _cancelInvitation(invId),
                                        tooltip: 'Cancel invitation',
                                      )
                                    : null,
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}