import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _CompanySettingsScreenState
    extends State<CompanySettingsScreen> {
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Force reload to ensure we have latest data
      context.read<CompanyBloc>().add(const LoadCompanies());
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Checks if the current user can manage members.
  /// Returns true for owners and admins of the selected company.
  bool get _canManageMembers {
    final state = context.read<CompanyBloc>().state;
    final company = state.selectedCompany;

    if (company == null) {
      debugPrint(
          'CompanySettingsScreen: selectedCompany is null');
      return false;
    }

    // The role can be at the top level of the company map
    // or nested differently depending on the API response
    final role = (company['role'] ?? company['user_role'] ??
            company['membership_role'])
        .toString()
        .toLowerCase();

    debugPrint(
        'CompanySettingsScreen: company=${company['name']}, role=$role');

    return role == 'owner' || role == 'admin';
  }

  /// Gets the company ID from the selected company.
  String? get _selectedCompanyId {
    final state = context.read<CompanyBloc>().state;
    final company = state.selectedCompany;
    if (company == null) return null;

    // Try multiple possible key names for the company ID
    return (company['id'] ?? company['company_id'] ?? '')
        .toString();
  }

  void _inviteUser() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid email')),
      );
      return;
    }

    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) {
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

    debugPrint(
        'CompanySettingsScreen: Inviting $email to company $companyId');

    context.read<CompanyBloc>().add(CreateInvitation(
          companyId: companyId,
          email: email,
        ));
    _emailController.clear();
  }

  void _cancelInvitation(String invitationId) {
    context
        .read<CompanyBloc>()
        .add(CancelInvitation(invitationId));
  }

  void _removeMember(
      String memberId, String memberName) async {
    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $memberName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      context.read<CompanyBloc>().add(RemoveMember(
            memberId: memberId,
            companyId: companyId,
            memberName: memberName,
          ));
    }
  }

  void _changeRole(
      String memberId, String currentRole) async {
    final companyId = _selectedCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change Role'),
        children: ['staff', 'manager', 'admin']
            .map((role) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, role),
                  child: Row(
                    children: [
                      if (role == currentRole)
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Text(role[0].toUpperCase() +
                          role.substring(1)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (newRole != null && newRole != currentRole) {
      context.read<CompanyBloc>().add(ChangeMemberRole(
            memberId: memberId,
            companyId: companyId,
            newRole: newRole,
          ));
    }
  }

  void _showTokenDialog(String email, String token) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invitation Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sent to: $email'),
            const SizedBox(height: 16),
            const Text('Share this token:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  token,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: token));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<CompanyBloc, CompanyState>(
      listener: (context, state) {
        if (state.successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context
              .read<CompanyBloc>()
              .add(const ClearMessages());
        }
        if (state.invitationToken != null) {
          _showTokenDialog(
            _emailController.text.trim().isEmpty
                ? 'the user'
                : _emailController.text.trim(),
            state.invitationToken!,
          );
          context
              .read<CompanyBloc>()
              .add(const ClearMessages());
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context
              .read<CompanyBloc>()
              .add(const ClearMessages());
        }
      },
      child:
          BlocBuilder<CompanyBloc, CompanyState>(
        builder: (context, state) {
          if (state.isLoading && state.companies.isEmpty) {
            return Scaffold(
              appBar: AppBar(
                  title: const Text('Company Settings')),
              body: const Center(
                  child: CircularProgressIndicator()),
            );
          }

          if (state.selectedCompany == null &&
              !state.isLoading) {
            return Scaffold(
              appBar: AppBar(
                  title: const Text('Company Settings')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.business_outlined,
                          size: 64,
                          color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'No company selected',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please go back and select a company first.',
                        style: TextStyle(
                            color: Colors.grey),
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
                context
                    .read<CompanyBloc>()
                    .add(const LoadCompanies());
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Company: ${state.selectedCompany!['name'] ?? 'Unknown'}',
                                style: TextStyle(
                                    fontWeight:
                                        FontWeight.w600,
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
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.people,
                                  color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Joined Members (${state.members.length})',
                                style: theme
                                    .textTheme.titleMedium
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (state.members.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'No members yet',
                                  style: TextStyle(
                                      color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ...state.members.map((member) {
                              final name = (member['display_name'] ??
                                      member['email'] ??
                                      'Unknown')
                                  .toString();
                              final role = (member['role'] ??
                                      'staff')
                                  .toString();
                              final memberId =
                                  member['id']?.toString() ??
                                      '';
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
                                subtitle: Text(
                                    'Role: ${role.toUpperCase()}'),
                                trailing:
                                    _canManageMembers &&
                                            !isOwner
                                        ? PopupMenuButton<
                                            String>(
                                            onSelected:
                                                (action) {
                                              if (action ==
                                                  'change_role') {
                                                _changeRole(
                                                    memberId,
                                                    role);
                                              } else if (action ==
                                                  'remove') {
                                                _removeMember(
                                                    memberId,
                                                    name);
                                              }
                                            },
                                            itemBuilder:
                                                (ctx) => [
                                              const PopupMenuItem(
                                                value:
                                                    'change_role',
                                                child: Text(
                                                    'Change Role'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'remove',
                                                child: Text(
                                                  'Remove',
                                                  style: TextStyle(
                                                      color: Colors
                                                          .red),
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
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_add,
                                    color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Invite Member',
                                    style: theme
                                        .textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight:
                                                FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _emailController,
                              keyboardType:
                                  TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText:
                                    'Enter email address',
                                prefixIcon: const Icon(
                                    Icons.email),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          12),
                                ),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _inviteUser,
                                icon:
                                    const Icon(Icons.send),
                                label: const Text(
                                    'Send Invitation'),
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
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                    Icons.pending_actions,
                                    color: Colors.orange),
                                const SizedBox(width: 8),
                                Text(
                                  'Pending (${state.invitations.length})',
                                  style: theme
                                      .textTheme.titleMedium
                                      ?.copyWith(
                                          fontWeight:
                                              FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...state.invitations.map((inv) {
                              final email = (inv['email'] ?? '')
                                  .toString();
                              final invId =
                                  inv['id']?.toString() ?? '';
                              final status =
                                  (inv['status'] ?? 'pending')
                                      .toString();

                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    email.isNotEmpty
                                        ? email[0]
                                            .toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(email),
                                subtitle: Text(
                                    'Status: $status'),
                                trailing: _canManageMembers
                                    ? IconButton(
                                        icon: const Icon(
                                            Icons.cancel,
                                            color: Colors.red),
                                        onPressed: () =>
                                            _cancelInvitation(
                                                invId),
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