import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';

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
  bool _isLoading = false;
  List<Map<String, dynamic>> _invitations = [];
  List<Map<String, dynamic>> _members = [];
  Map<String, dynamic>? _company;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    final authService = context.read<AuthService>();
    setState(() => _isLoading = true);

    try {
      final company = await authService.getUserCompany();
      if (!mounted) {
        setState(() => _isLoading = false);
        return;
      }

      if (company != null) {
        final c = company['company'];
        if (c is Map) {
          final companyId = c['id']?.toString() ?? '';
          _currentUserRole = company['role']?.toString();

          final invitations =
              await authService.getPendingInvitations(companyId);
          final members = await authService.getCompanyMembers(companyId);

          if (mounted) {
            setState(() {
              _company = company;
              _invitations = invitations;
              _members = members;
              _isLoading = false;
            });
          }
          return;
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canManageMembers =>
      _currentUserRole == 'owner' || _currentUserRole == 'admin';

  Future<void> _inviteUser() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid email')),
        );
      }
      return;
    }
    if (_company == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final authService = context.read<AuthService>();

    setState(() => _isLoading = true);

    try {
      final companyData = _company!['company'];
      if (companyData is! Map) {
        setState(() => _isLoading = false);
        return;
      }
      final companyId = companyData['id']?.toString() ?? '';

      if (companyId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final result = await authService.createInvitation(
        companyId: companyId,
        email: email,
        role: 'staff',
      );

      if (!mounted) return;

      // FIXED: Proper type-safe access to result Map
      if (result is Map<String, dynamic> && result['success'] == true) {
        final token = result['token']?.toString() ?? '';

        if (token.isNotEmpty) {
          _showTokenDialog(email, token);
          _emailController.clear();
          await _loadData();
        } else {
          setState(() => _isLoading = false);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to generate invitation token'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        // FIXED: Safe access to message without nullable index error
        final message = result is Map<String, dynamic>
            ? (result['message']?.toString() ?? 'Failed to create invitation')
            : 'Failed to create invitation';

        setState(() => _isLoading = false);
        messenger.showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
              // FIXED: Wrap in SingleChildScrollView to prevent overflow
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
              Clipboard.setData(ClipboardData(text: token));
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

  Future<void> _cancelInvitation(String invitationId) async {
    final messenger = ScaffoldMessenger.of(context);
    final authService = context.read<AuthService>();

    await authService.cancelInvitation(invitationId);
    if (!mounted) return;

    await _loadData();
    if (mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('Cancelled')));
    }
  }

  Future<void> _removeMember(String memberId, String memberName) async {
    final messenger = ScaffoldMessenger.of(context);

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
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && _company != null && mounted) {
      final authService = context.read<AuthService>();
      final companyData = _company!['company'];
      if (companyData is! Map) return;
      final companyId = companyData['id']?.toString() ?? '';

      if (companyId.isEmpty) return;

      await authService.removeMember(memberId, companyId);
      if (!mounted) return;

      await _loadData();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('$memberName removed')),
        );
      }
    }
  }

  Future<void> _changeRole(String memberId, String currentRole) async {
    if (_company == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final companyData = _company!['company'];
    if (companyData is! Map) return;
    final companyId = companyData['id']?.toString() ?? '';

    if (companyId.isEmpty) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change Role'),
        children: ['staff', 'manager', 'admin']
            .map(
              (role) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, role),
                child: Row(
                  children: [
                    if (role == currentRole)
                      const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Text(role[0].toUpperCase() + role.substring(1)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );

    if (newRole != null && newRole != currentRole && mounted) {
      final authService = context.read<AuthService>();
      await authService.updateMemberRole(memberId, companyId, newRole);
      if (!mounted) return;

      await _loadData();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Role updated')));
      }
    }
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_company == null && !_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Company Settings')),
        body: const Center(child: Text('No company found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.inventoryName.isNotEmpty
            ? '${widget.inventoryName} - Members'
            : 'Company Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── Members Card ─────────────────────────────────
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
                              'Joined Members (${_members.length})',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_members.isEmpty)
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
                          ..._members.map((member) {
                            // FIXED: Safe conversion of dynamic fields
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
                              subtitle:
                                  Text('Role: ${role.toUpperCase()}'),
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

                // ─── Invite Member Card ──────────────────────────
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
                                child: Text(
                                  'Invite Member',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold),
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

                // ─── Pending Invitations Card ────────────────────
                if (_invitations.isNotEmpty) ...[
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
                                'Pending (${_invitations.length})',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._invitations.map((inv) {
                            final email =
                                (inv['email'] ?? '').toString();
                            final invId =
                                inv['id']?.toString() ?? '';
                            final status =
                                (inv['status'] ?? 'pending').toString();

                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  email.isNotEmpty
                                      ? email[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(email),
                              subtitle: Text('Status: $status'),
                              trailing: _canManageMembers
                                  ? IconButton(
                                      icon: const Icon(Icons.cancel,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _cancelInvitation(invId),
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
    );
  }
}