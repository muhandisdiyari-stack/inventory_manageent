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
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _emailController = TextEditingController();
  String _selectedRole = 'data_operator';

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
    final role = (company['role'] ?? company['user_role'] ?? company['membership_role'])
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
        const SnackBar(content: Text('Enter a valid email address')),
      );
      return;
    }

    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No company selected. Please go back and select a company first.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    context.read<CompanyBloc>().add(CreateInvitation(
          companyId: companyId,
          email: email,
          role: _selectedRole,
        ));
    _emailController.clear();
    setState(() => _selectedRole = 'data_operator');
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
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

  void _changeRole(String memberId, String currentRole, String memberName) async {
    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Role for $memberName'),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRoleOption(ctx, 'admin', 'Admin', 'Full access except deleting company', currentRole),
            const Divider(height: 1),
            _buildRoleOption(ctx, 'data_operator', 'Data Operator', 'Create and update items only', currentRole),
            const Divider(height: 1),
            _buildRoleOption(ctx, 'viewer', 'Viewer', 'View only, no modifications', currentRole),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
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

  Widget _buildRoleOption(
      BuildContext ctx, String value, String title, String subtitle, String currentRole) {
    final isSelected = value == currentRole;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected ? Theme.of(ctx).colorScheme.primary : Colors.grey,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      selectedTileColor: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      case 'data_operator':
        return 'Data Operator';
      case 'viewer':
        return 'Viewer';
      default:
        return role;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.amber;
      case 'admin':
        return Colors.blue;
      case 'data_operator':
        return Colors.teal;
      case 'viewer':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocListener<CompanyBloc, CompanyState>(
      listener: (context, state) {
        if (state.successMessage != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<CompanyBloc>().add(const ClearMessages());
        }
        if (state.error != null && mounted) {
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
                      Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('No company selected',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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

          final companyName = state.selectedCompany!['name']?.toString() ?? 'Unknown';

          return Scaffold(
            appBar: AppBar(
              title: Text('$companyName - Members'),
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
                  // ─── Company info card ────────────────────────
                  Card(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.business, color: colorScheme.primary, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  companyName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${state.members.length} ${state.members.length == 1 ? 'member' : 'members'}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Members Card ─────────────────────────────
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.people, color: Colors.green, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Company Members',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Company-level members can see all inventories.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          if (state.members.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text('No members yet', style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          else
                            ...state.members.map((member) {
                              final name =
                                  (member['display_name'] ?? member['email'] ?? 'Unknown').toString();
                              final email = (member['email'] ?? '').toString();
                              final role = (member['role'] ?? 'viewer').toString();
                              final memberId = member['id']?.toString() ?? '';
                              final isOwner = role == 'owner';
                              final roleColor = _getRoleColor(role);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: roleColor.withValues(alpha: 0.15),
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: roleColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          ),
                                          if (email.isNotEmpty && email != name)
                                            Text(
                                              email,
                                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _getRoleDisplayName(role),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: roleColor,
                                        ),
                                      ),
                                    ),
                                    if (_canManageMembers && !isOwner)
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.more_vert, size: 20),
                                        onSelected: (action) {
                                          if (action == 'change_role') {
                                            _changeRole(memberId, role, name);
                                          } else if (action == 'remove') {
                                            _removeMember(memberId, name);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'change_role',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit, size: 18),
                                                SizedBox(width: 8),
                                                Text('Change Role'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Row(
                                              children: [
                                                Icon(Icons.person_remove, size: 18, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Remove', style: TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  // ─── Invite Member Card ──────────────────────
                  if (_canManageMembers) ...[
                    const SizedBox(height: 16),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.person_add, color: Colors.blue, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Invite Company Member',
                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'They will automatically join when they sign in with this email',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                hintText: 'Enter email address',
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedRole,
                              decoration: InputDecoration(
                                labelText: 'Role',
                                prefixIcon: const Icon(Icons.badge_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                              items: [
                                _buildDropdownItem('admin', 'Admin', 'Full access except deleting company'),
                                _buildDropdownItem(
                                    'data_operator', 'Data Operator', 'Create and update items only'),
                                _buildDropdownItem('viewer', 'Viewer', 'View only, no modifications'),
                              ],
                              onChanged: (v) => setState(() => _selectedRole = v!),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: _inviteUser,
                                icon: const Icon(Icons.send, size: 18),
                                label: const Text('Send Invitation',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ─── Pending Invitations Card ────────────────
                  if (state.invitations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.pending_actions, color: Colors.orange, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Pending Invitations (${state.invitations.length})',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...state.invitations.map((inv) {
                              final email = (inv['email'] ?? '').toString();
                              final invId = inv['id']?.toString() ?? '';
                              final role = (inv['role'] ?? 'viewer').toString();
                              final roleColor = _getRoleColor(role);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                                      child: const Icon(Icons.person_outline, color: Colors.orange, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(email,
                                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: roleColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _getRoleDisplayName(role),
                                              style:
                                                  TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: roleColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_canManageMembers)
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                        tooltip: 'Cancel invitation',
                                        onPressed: () => _cancelInvitation(invId),
                                        style: IconButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(36, 36),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
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

  DropdownMenuItem<String> _buildDropdownItem(String value, String title, String subtitle) {
    return DropdownMenuItem<String>(
      value: value,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}