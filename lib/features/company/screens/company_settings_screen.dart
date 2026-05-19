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
      if (!mounted) return;

      if (company != null) {
        final c = company['company'];
        if (c != null) {
          final companyId = c['id'] as String;
          final invitations = await authService.getPendingInvitations(companyId);
          final members = await authService.getCompanyMembers(companyId);

          if (!mounted) return;

          // FIX #3: _currentUserRole is now set inside setState so the role
          // assignment and the rebuild it triggers are atomic. Previously it
          // was assigned directly to the field outside setState, meaning a
          // rebuild wasn't guaranteed to pick up the new role value.
          setState(() {
            _company = company;
            _currentUserRole = company['role'] as String?;
            _invitations = invitations;
            _members = members;
            _isLoading = false;
          });
          return;
        }
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool get _canManageMembers =>
      _currentUserRole == 'owner' || _currentUserRole == 'admin';

  Future<void> _inviteUser() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid email')),
        );
      }
      return;
    }
    if (_company == null) return;

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final companyId = (_company!['company'] as Map)['id'] as String;
      final result = await authService.createInvitation(
        companyId: companyId,
        email: email,
        role: 'staff',
      );

      if (!mounted) return;

      if (result != null) {
        _showTokenDialog(email, result['token'] ?? '');
        _emailController.clear();
        // _loadData manages _isLoading internally; no need to reset it here.
        await _loadData();
      } else {
        // FIX #4: _isLoading is always reset on the failure path. Previously
        // the success branch delegated to _loadData() which handles _isLoading,
        // but if _loadData returned early due to !mounted, _isLoading was
        // left true. Now both paths always land in a known state.
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send invitation'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
              child: SelectableText(
                token,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'monospace',
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
            child: const Text('Copy & Close'),
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
    // FIX #5: authService captured before the await so it is never read from
    // context after an async gap (consistent with the other methods).
    final authService = context.read<AuthService>();
    await authService.cancelInvitation(invitationId);
    if (!mounted) return;
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation cancelled')),
      );
    }
  }

  Future<void> _removeMember(String memberId, String memberName) async {
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
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || _company == null) return;

    final authService = context.read<AuthService>();
    final companyId = (_company!['company'] as Map)['id'] as String;
    await authService.removeMember(memberId, companyId);

    if (!mounted) return;
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$memberName removed')),
      );
    }
  }

  Future<void> _changeRole(String memberId, String currentRole) async {
    if (_company == null) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change Role'),
        children: ['staff', 'manager', 'admin'].map((role) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, role),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: role == currentRole
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(role[0].toUpperCase() + role.substring(1)),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (newRole == null || newRole == currentRole) return;

    final authService = context.read<AuthService>();
    final companyId = (_company!['company'] as Map)['id'] as String;
    await authService.updateMemberRole(memberId, companyId, newRole);

    if (!mounted) return;
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_company == null && !_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Company Settings')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No company found.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.inventoryName.isNotEmpty
              ? '${widget.inventoryName} - Members'
              : 'Company Settings',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Members card ──────────────────────────────────
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
                        // FIX #6: Added explicit toList() on the spread to
                        // avoid the iterable being consumed multiple times.
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
                            final name = (member['display_name'] as String?)
                                    ?.isNotEmpty ==
                                    true
                                ? member['display_name'] as String
                                : (member['email'] as String?) ?? 'Unknown';
                            final role =
                                (member['role'] as String?) ?? 'staff';
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
                                          _changeRole(
                                              member['id'] as String, role);
                                        } else if (action == 'remove') {
                                          _removeMember(
                                              member['id'] as String, name);
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
                                            style:
                                                TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          }).toList(),
                      ],
                    ),
                  ),
                ),

                // ── Invite card (managers/owners only) ────────────
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
                              const Icon(Icons.person_add, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Invite Member',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
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
                            onSubmitted: (_) => _inviteUser(),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _inviteUser,
                              icon: const Icon(Icons.send),
                              label: const Text('Send Invitation'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── Pending invitations card ──────────────────────
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
                          // FIX #7: Guard against empty email string before
                          // indexing [0], which would throw a RangeError on a
                          // malformed DB record.
                          ..._invitations.map((inv) {
                            final email = (inv['email'] as String?) ?? '';
                            final initial =
                                email.isNotEmpty ? email[0].toUpperCase() : '?';
                            return ListTile(
                              leading: CircleAvatar(child: Text(initial)),
                              title: Text(
                                  email.isNotEmpty ? email : '(no email)'),
                              subtitle:
                                  Text('Status: ${inv['status'] ?? 'pending'}'),
                              trailing: _canManageMembers
                                  ? IconButton(
                                      icon: const Icon(Icons.cancel,
                                          color: Colors.red),
                                      tooltip: 'Cancel invitation',
                                      onPressed: () => _cancelInvitation(
                                          inv['id'] as String),
                                    )
                                  : null,
                            );
                          }).toList(),
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