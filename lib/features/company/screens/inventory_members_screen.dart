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
        final data = await Supabase.instance.client.rpc(
          'get_pending_invitations',
          params: {'p_inventory_id': widget.inventoryId},
        );
        if (data is List) {
          invitations = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
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
    return _permissions!.canInviteMembers ||
        _permissions!.canRemoveMembers ||
        _permissions!.role == 'owner' ||
        _permissions!.role == 'admin';
  }

  bool get _canInvite {
    if (_permissions == null) return false;
    return _permissions!.canInviteMembers ||
        _permissions!.role == 'owner' ||
        _permissions!.role == 'admin';
  }

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
      final result =
          await Supabase.instance.client.rpc('create_invitation', params: {
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
          SnackBarUtils.error(context,
              resultMap['message']?.toString() ?? 'Failed to send invitation');
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
        content:
            const Text('Are you sure you want to cancel this invitation?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await Supabase.instance.client.rpc(
          'cancel_invitation',
          params: {'p_invitation_id': invitationId},
        );
        if (mounted) {
          SnackBarUtils.success(context, 'Invitation cancelled');
          _loadData();
        }
      } catch (e) {
        if (mounted) SnackBarUtils.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _removeMember(String memberId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
            'Remove $memberName from this inventory?\n\nTheir historical data will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final permService = PermissionService();
        final result = await permService.removeMember(
          memberId: memberId,
          inventoryId: widget.inventoryId,
        );

        if (mounted) {
          if (result) {
            SnackBarUtils.success(context, '$memberName removed');
            _loadData();
          } else {
            SnackBarUtils.error(context, 'Failed to remove member.');
          }
        }
      } catch (e) {
        if (mounted) {
          final errorMsg = e.toString();
          if (errorMsg.contains('last admin') ||
              errorMsg.contains('Cannot remove')) {
            SnackBarUtils.error(context,
                'Cannot remove the last admin/owner of the inventory.');
          } else if (errorMsg.contains('Cannot delete the inventory owner')) {
            SnackBarUtils.error(context,
                'Cannot remove the owner. Transfer ownership first.');
          } else {
            SnackBarUtils.error(context, 'Error: $e');
          }
        }
      }
    }
  }

  Future<void> _changeRole(
      String memberId, String currentRole, String memberName) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Role for $memberName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['admin', 'data_operator', 'viewer']
              .where((r) => r != currentRole)
              .map((role) => ListTile(
                    title: Text(_getRoleDisplayName(role)),
                    subtitle: Text(_getRoleDescription(role),
                        style: const TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, role),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (newRole != null && newRole != currentRole && mounted) {
      try {
        final permService = PermissionService();
        final result = await permService.updateMemberPermissions(
          memberId: memberId,
          inventoryId: widget.inventoryId,
          role: newRole,
        );

        if (mounted) {
          if (result) {
            SnackBarUtils.success(
                context, 'Role updated to ${_getRoleDisplayName(newRole)}');
            _loadData();
          } else {
            SnackBarUtils.error(context, 'Failed to update role');
          }
        }
      } catch (e) {
        if (mounted) {
          final errorMsg = e.toString();
          if (errorMsg.contains('last admin') ||
              errorMsg.contains('Cannot downgrade')) {
            SnackBarUtils.error(
                context, 'Cannot downgrade the last admin.');
          } else if (errorMsg.contains('Cannot change owner role')) {
            SnackBarUtils.error(context,
                'Cannot change the owner\'s role. Transfer ownership first.');
          } else {
            SnackBarUtils.error(context, 'Error: $e');
          }
        }
      }
    }
  }

  Future<void> _transferOwnership(
      String currentOwnerId, String currentOwnerName) async {
    final eligibleMembers =
        _members.where((m) => m['id']?.toString() != currentOwnerId).toList();

    if (eligibleMembers.isEmpty) {
      SnackBarUtils.show(context,
          message: 'No other members to transfer ownership to',
          isError: true);
      return;
    }

    final newOwnerUserId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current owner: $currentOwnerName'),
            const SizedBox(height: 12),
            const Text('Select new owner:'),
            const SizedBox(height: 8),
            ...eligibleMembers.map((m) {
              final name =
                  (m['display_name'] ?? m['email'] ?? 'Unknown').toString();
              final userId = m['user_id']?.toString() ?? '';
              return ListTile(
                title: Text(name),
                subtitle: Text(
                    _getRoleDisplayName(m['role']?.toString() ?? 'viewer')),
                leading: CircleAvatar(
                  child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?'),
                ),
                onTap: () => Navigator.pop(ctx, userId),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (newOwnerUserId != null && mounted) {
      try {
        final result = await Supabase.instance.client.rpc(
          'transfer_inventory_ownership',
          params: {
            'p_inventory_id': widget.inventoryId,
            'p_new_owner_user_id': newOwnerUserId,
          },
        );

        final resultMap = Map<String, dynamic>.from(result as Map);
        if (mounted) {
          if (resultMap['success'] == true) {
            SnackBarUtils.success(
                context, 'Ownership transferred successfully');
            _loadData();
          } else {
            SnackBarUtils.error(context,
                resultMap['message']?.toString() ?? 'Failed to transfer');
          }
        }
      } catch (e) {
        if (mounted) SnackBarUtils.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _leaveInventory() async {
    if (_isOwner) {
      SnackBarUtils.show(context,
          message:
              'As the owner, you cannot leave. Transfer ownership first or delete the inventory.',
          isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Inventory'),
        content: const Text(
            'Are you sure you want to leave this inventory? You will lose access to all items and chat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final result = await Supabase.instance.client.rpc(
          'leave_inventory',
          params: {'p_inventory_id': widget.inventoryId},
        );

        final resultMap = Map<String, dynamic>.from(result as Map);
        if (mounted) {
          if (resultMap['success'] == true) {
            SnackBarUtils.success(context, 'You have left the inventory');
            Navigator.pop(context, true);
          } else {
            SnackBarUtils.error(context,
                resultMap['message']?.toString() ?? 'Failed to leave');
          }
        }
      } catch (e) {
        if (mounted) SnackBarUtils.error(context, 'Error: $e');
      }
    }
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

  String _getRoleDescription(String role) {
    switch (role) {
      case 'admin':
        return 'Full access. Can manage members, items, and settings.';
      case 'data_operator':
        return 'Can add and update items. Cannot manage members or settings.';
      case 'viewer':
        return 'View only. Can view items and participate in chat.';
      default:
        return '';
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.inventoryName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            Text('Members & Permissions',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Refresh'),
        ],
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
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: colorScheme.primary
                                .withValues(alpha: 0.1)),
                      ),
                      child: Row(children: [
                        Icon(Icons.badge,
                            color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                            'Your Role: ${_getRoleDisplayName(_permissions!.role)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary)),
                        const Spacer(),
                        if (!_isOwner)
                          TextButton.icon(
                            onPressed: _leaveInventory,
                            icon: const Icon(Icons.exit_to_app, size: 16),
                            label: const Text('Leave',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 12)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8)),
                          ),
                      ]),
                    ),
                  _buildMembersSection(theme),
                  const SizedBox(height: 16),
                  if (_pendingInvitations.isNotEmpty)
                    _buildPendingInvitationsSection(theme),
                  const SizedBox(height: 16),
                  if (_canInvite) _buildInviteSection(theme, colorScheme),
                  const SizedBox(height: 32),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.people, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Text('Inventory Members (${_members.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text('These users have access to this inventory.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            if (_members.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No members yet',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ..._members
                  .map((member) => _buildMemberTile(member, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingInvitationsSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pending_actions,
                    color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                  'Pending Invitations (${_pendingInvitations.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ..._pendingInvitations
                .map((inv) => _buildInvitationTile(inv, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteSection(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add,
                    color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Invite New Member',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            Text('They will automatically join when they sign in with this email.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'Enter email address',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: InputDecoration(
                labelText: 'Role',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
              items: const [
                DropdownMenuItem(
                    value: 'admin',
                    child:
                        Text('Admin - Full access, can manage members')),
                DropdownMenuItem(
                    value: 'data_operator',
                    child:
                        Text('Data Operator - Can add and update items')),
                DropdownMenuItem(
                    value: 'viewer',
                    child: Text('Viewer - View and chat only')),
              ],
              onChanged: (v) => setState(() => _selectedRole = v!),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isSending ? null : _inviteUser,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18),
                label: Text(_isSending ? 'Sending...' : 'Send Invitation',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member, ThemeData theme) {
    final name =
        (member['display_name'] ?? member['full_name'] ?? member['email'] ?? 'Unknown')
            .toString();
    final email = (member['email'] ?? '').toString();
    final role = (member['role'] ?? 'viewer').toString();
    final memberId = member['id']?.toString() ?? '';
    final userId = member['user_id']?.toString() ?? '';
    final isOwner = role == 'owner';
    final isCurrentUser =
        userId == Supabase.instance.client.auth.currentUser?.id;
    final roleColor = _getRoleColor(role);
    final joinedAt = _formatDate(member['joined_at']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isCurrentUser)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('You',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    if (email.isNotEmpty && email != name)
                      Text(email,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_getRoleDisplayName(role),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: roleColor)),
              ),
              if (_canManageMembers && !isOwner && !isCurrentUser)
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
                      child: Row(children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Change Role'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(children: [
                        Icon(Icons.person_remove,
                            size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Remove',
                            style: TextStyle(color: Colors.red)),
                      ]),
                    ),
                  ],
                ),
            ],
          ),
          if (isOwner && isCurrentUser)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 52),
              child: TextButton.icon(
                onPressed: () => _transferOwnership(memberId, name),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Transfer Ownership',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (joinedAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 52),
              child: Text('Joined: $joinedAt',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey[400])),
      )],
      ),
    );
  }

  Widget _buildInvitationTile(
      Map<String, dynamic> invitation, ThemeData theme) {
    final email = (invitation['email'] ?? '').toString();
    final role = (invitation['role'] ?? 'viewer').toString();
    final invId = invitation['id']?.toString() ?? '';
    final roleColor = _getRoleColor(role);
    final expiresAt = invitation['expires_at']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
            child: const Icon(Icons.person_outline,
                color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_getRoleDisplayName(role),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: roleColor)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Pending',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange)),
                  ),
                ]),
                if (expiresAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        'Expires: ${_formatDate(expiresAt)}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[400])),
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
                  minimumSize: const Size(36, 36)),
            ),
        ],
      ),
    );
  }
}