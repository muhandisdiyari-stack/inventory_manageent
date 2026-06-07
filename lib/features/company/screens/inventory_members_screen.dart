import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/models/user.dart';

class InventoryMembersScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;

  const InventoryMembersScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
  });

  @override
  State<InventoryMembersScreen> createState() => _InventoryMembersScreenState();
}

class _InventoryMembersScreenState extends State<InventoryMembersScreen> {
  final _emailController = TextEditingController();
  String _selectedRole = 'data_operator';
  bool _isSending = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _pendingInvitations = [];
  InventoryPermissions? _permissions;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final permService = PermissionService();
      final perms = await permService.getInventoryPermissions(widget.inventoryId);
      final members = await permService.getInventoryMembers(widget.inventoryId);

      List<Map<String, dynamic>> invitations = [];
      try {
        final data = await Supabase.instance.client
            .rpc('get_pending_invitations', params: {'p_inventory_id': widget.inventoryId});
        if (data is List) {
          invitations = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (e) {
        debugPrint('Failed to load invitations: $e');
      }

      try {
        final invData = await Supabase.instance.client
            .from('inventories')
            .select('company_id')
            .eq('id', widget.inventoryId)
            .single();
        _companyId = invData['company_id']?.toString();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _permissions = perms;
          _members = members;
          _pendingInvitations = invitations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarUtils.error(context, 'Failed to load members: $e');
      }
    }
  }

  bool get _canManageMembers {
    if (_permissions == null) return false;
    return _permissions!.role == 'owner' || _permissions!.role == 'admin';
  }

  bool get _canInvite => _canManageMembers;

  bool get _isOwner {
    if (_permissions == null) return false;
    return _permissions!.role == 'owner';
  }

  Future<void> _inviteUser() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      SnackBarUtils.error(context, 'Enter a valid email address');
      return;
    }

    if (_companyId == null) {
      SnackBarUtils.error(context, 'Could not determine company');
      return;
    }

    setState(() => _isSending = true);

    try {
      final result = await Supabase.instance.client.rpc('create_invitation', params: {
        'p_company_id': _companyId,
        'p_inventory_id': widget.inventoryId,
        'p_email': email,
        'p_role': _selectedRole,
      });

      final resultMap = Map<String, dynamic>.from(result as Map);

      if (mounted) {
        if (resultMap['success'] == true) {
          _emailController.clear();
          SnackBarUtils.success(context, 'Invitation sent to $email');
          _loadData();
        } else {
          SnackBarUtils.error(context, resultMap['message']?.toString() ?? 'Failed to send invitation');
        }
      }
    } catch (e) {
      if (mounted) SnackBarUtils.error(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _cancelInvitation(String invitationId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Invitation'),
        content: const Text('Are you sure you want to cancel this invitation?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Yes')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await Supabase.instance.client.rpc('cancel_invitation', params: {'p_invitation_id': invitationId});
        if (mounted) { SnackBarUtils.success(context, 'Invitation cancelled'); _loadData(); }
      } catch (e) { if (mounted) SnackBarUtils.error(context, 'Error: $e'); }
    }
  }

  Future<void> _removeMember(String memberId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $memberName from this inventory?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final permService = PermissionService();
        final result = await permService.removeMember(memberId: memberId, inventoryId: widget.inventoryId);
        if (mounted) { if (result) { SnackBarUtils.success(context, '$memberName removed'); _loadData(); } else { SnackBarUtils.error(context, 'Failed to remove member'); } }
      } catch (e) { if (mounted) SnackBarUtils.error(context, e.toString().contains('last admin') ? 'Cannot remove the last admin' : 'Error: $e'); }
    }
  }

  Future<void> _changeRole(String memberId, String currentRole, String memberName) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Role for $memberName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['admin', 'data_operator', 'viewer'].where((r) => r != currentRole).map((role) => ListTile(
            title: Text(_getRoleDisplayName(role)),
            subtitle: Text(_getRoleDescription(role), style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, role),
          )).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );

    if (newRole != null && newRole != currentRole && mounted) {
      try {
        final permService = PermissionService();
        await permService.updateMemberPermissions(memberId: memberId, inventoryId: widget.inventoryId, role: newRole);
        if (mounted) { SnackBarUtils.success(context, 'Role updated'); _loadData(); }
      } catch (e) { if (mounted) SnackBarUtils.error(context, 'Error: $e'); }
    }
  }

  Future<void> _leaveInventory() async {
    if (_isOwner) { SnackBarUtils.error(context, 'Owner cannot leave. Transfer ownership first.'); return; }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Inventory'),
        content: const Text('Are you sure? You will lose access to all items and chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        final result = await Supabase.instance.client.rpc('leave_inventory', params: {'p_inventory_id': widget.inventoryId});
        final resultMap = Map<String, dynamic>.from(result as Map);
        if (mounted) { if (resultMap['success'] == true) { Navigator.pop(context, true); } else { SnackBarUtils.error(context, resultMap['message']?.toString() ?? 'Failed'); } }
      } catch (e) { if (mounted) SnackBarUtils.error(context, 'Error: $e'); }
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role) { case 'owner': return 'Owner'; case 'admin': return 'Admin'; case 'data_operator': return 'Data Operator'; case 'viewer': return 'Viewer'; default: return role; }
  }

  String _getRoleDescription(String role) {
    switch (role) { case 'admin': return 'Full access'; case 'data_operator': return 'Can add/update items'; case 'viewer': return 'View and chat only'; default: return ''; }
  }

  Color _getRoleColor(String role) {
    switch (role) { case 'owner': return Colors.amber; case 'admin': return Colors.blue; case 'data_operator': return Colors.teal; case 'viewer': return Colors.grey; default: return Colors.grey; }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.inventoryName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_permissions != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Icon(Icons.badge, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('Your Role: ${_getRoleDisplayName(_permissions!.role)}', style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                        const Spacer(),
                        if (!_isOwner) TextButton(onPressed: _leaveInventory, child: const Text('Leave', style: TextStyle(color: Colors.orange, fontSize: 12))),
                      ]),
                    ),
                  _buildMembersSection(theme),
                  const SizedBox(height: 16),
                  if (_pendingInvitations.isNotEmpty) _buildPendingSection(theme),
                  const SizedBox(height: 16),
                  if (_canInvite) _buildInviteSection(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildMembersSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.people, color: Colors.green, size: 20), const SizedBox(width: 8), Text('Members (${_members.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          if (_members.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No members yet', style: TextStyle(color: Colors.grey))))
          else ..._members.map((m) => _buildMemberTile(m, theme)),
        ]),
      ),
    );
  }

  Widget _buildPendingSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.pending_actions, color: Colors.orange, size: 20), const SizedBox(width: 8), Text('Pending (${_pendingInvitations.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          ..._pendingInvitations.map((inv) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              CircleAvatar(radius: 18, backgroundColor: Colors.orange.withValues(alpha: 0.1), child: const Icon(Icons.person_outline, color: Colors.orange, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv['email']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                Text(_getRoleDisplayName(inv['role']?.toString() ?? 'viewer'), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ])),
              if (_canManageMembers) IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: () => _cancelInvitation(inv['id']?.toString() ?? '')),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _buildInviteSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.person_add, color: Colors.blue, size: 20), const SizedBox(width: 8), const Text('Invite Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Enter email address',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
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
            ),
            items: const [
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
              DropdownMenuItem(value: 'data_operator', child: Text('Data Operator')),
              DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
            ],
            onChanged: (v) => setState(() => _selectedRole = v!),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSending ? null : _inviteUser,
              icon: _isSending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 18),
              label: Text(_isSending ? 'Sending...' : 'Send Invitation'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member, ThemeData theme) {
    final name = (member['display_name'] ?? member['email'] ?? 'Unknown').toString();
    final role = (member['role'] ?? 'viewer').toString();
    final memberId = member['id']?.toString() ?? '';
    final avatarUrl = member['avatar_url'] as String?;
    final isOwner = role == 'owner';
    final isCurrentUser = (member['user_id']?.toString() ?? '') == Supabase.instance.client.auth.currentUser?.id;
    final roleColor = _getRoleColor(role);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: roleColor.withValues(alpha: 0.15),
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(name[0].toUpperCase(), style: TextStyle(color: roleColor, fontWeight: FontWeight.w700, fontSize: 14))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
            if (isCurrentUser) const Text(' (You)', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Text(_getRoleDisplayName(role), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: roleColor))),
        if (_canManageMembers && !isOwner && !isCurrentUser)
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) { if (action == 'change_role') _changeRole(memberId, role, name); else if (action == 'remove') _removeMember(memberId, name); },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'change_role', child: Text('Change Role')),
              const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Colors.red))),
            ],
          ),
      ]),
    );
  }
}