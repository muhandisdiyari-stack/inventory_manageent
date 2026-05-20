import 'package:flutter/material.dart';
import '../../../core/services/admin_service.dart';

class UsersManagement extends StatefulWidget {
  final AdminService adminService;

  const UsersManagement({super.key, required this.adminService});

  @override
  State<UsersManagement> createState() => _UsersManagementState();
}

class _UsersManagementState extends State<UsersManagement> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, confirmed, pending, approved

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final users = await widget.adminService.getAllUsers();

    if (!mounted) return;
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  Future<void> _approveUser(String userId) async {
    final confirmed = await _showConfirmDialog(
      title: 'Approve User',
      content: 'Are you sure you want to approve this user?',
      confirmLabel: 'Approve',
      confirmColor: Colors.green,
    );
    if (!confirmed || !mounted) return;

    final success = await widget.adminService.approveUser(userId);
    if (!mounted) return;

    _showSnack(
      success ? 'User approved' : 'Failed to approve user',
      success ? Colors.green : Colors.red,
    );
    if (success) await _loadUsers();
  }

  Future<void> _forceConfirmUser(String userId) async {
    final confirmed = await _showConfirmDialog(
      title: 'Force Confirm User',
      content:
          'This will bypass email verification and approve the user immediately. Continue?',
      confirmLabel: 'Confirm',
      confirmColor: Colors.blue,
    );
    if (!confirmed || !mounted) return;

    final success =
        await widget.adminService.forceConfirmUser(userId);
    if (!mounted) return;

    _showSnack(
      success
          ? 'User confirmed and approved'
          : 'Failed to confirm user',
      success ? Colors.green : Colors.red,
    );
    if (success) await _loadUsers();
  }

  Future<void> _deactivateUser(
      String userId, String email) async {
    final confirmed = await _showConfirmDialog(
      title: 'Deactivate User',
      content: 'Deactivate $email? They will lose access immediately.',
      confirmLabel: 'Deactivate',
      confirmColor: Colors.red,
    );
    if (!confirmed || !mounted) return;

    final success =
        await widget.adminService.deactivateUser(userId);
    if (!mounted) return;

    _showSnack(
      success ? '$email deactivated' : 'Failed to deactivate user',
      success ? Colors.orange : Colors.red,
    );
    if (success) await _loadUsers();
  }

  Future<void> _changeRole(
      String userId, String currentRole, String email) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Change Role for $email'),
        children: ['staff', 'manager', 'admin', 'owner']
            .map((role) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, role),
                  child: Row(children: [
                    SizedBox(
                      width: 24,
                      child: role == currentRole
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.green)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(role[0].toUpperCase() + role.substring(1)),
                  ]),
                ))
            .toList(),
      ),
    );

    if (newRole == null || newRole == currentRole || !mounted) return;

    final success =
        await widget.adminService.updateUserRole(userId, newRole);
    if (!mounted) return;

    _showSnack(
      success
          ? 'Role updated to $newRole'
          : 'Failed to update role',
      success ? Colors.green : Colors.red,
    );
    if (success) await _loadUsers();
  }

  Future<void> _sendNotificationToUser(
      String userId, String email) async {
    final titleController = TextEditingController();
    final messageController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notify $email'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: messageController,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send')),
        ],
      ),
    );

    if (confirmed != true ||
        titleController.text.isEmpty ||
        !mounted) return;

    final success = await widget.adminService.sendNotification(
      userId,
      titleController.text,
      messageController.text,
    );
    if (!mounted) return;

    _showSnack(
      success ? 'Notification sent' : 'Failed to send notification',
      success ? Colors.green : Colors.red,
    );
  }

  Future<void> _viewUserDetails(String userId) async {
    final details =
        await widget.adminService.getUserDetails(userId);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('User Details'),
        content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Email',
                    details['profile']?['email']?.toString() ?? '—'),
                _detailRow(
                    'Display Name',
                    details['profile']?['display_name']
                            ?.toString() ??
                        '—'),
                _detailRow('Role',
                    details['profile']?['role']?.toString() ?? '—'),
                _detailRow(
                    'Approved',
                    details['profile']?['is_approved']
                            ?.toString() ??
                        '—'),
                _detailRow('Companies',
                    details['companies']?.toString() ?? '0'),
                _detailRow('Items Created',
                    details['items_created']?.toString() ?? '0'),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'))
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns true if the user confirmed, false otherwise.
  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 100,
                child: Text('$label:',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600))),
            Expanded(child: Text(value)),
          ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12))),
        Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _users.where((u) {
      final email = (u['email'] ?? '').toString().toLowerCase();
      final name =
          (u['display_name'] ?? '').toString().toLowerCase();
      final matchesSearch = _searchQuery.isEmpty ||
          email.contains(_searchQuery.toLowerCase()) ||
          name.contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      switch (_filterStatus) {
        case 'confirmed':
          return u['email_confirmed'] == true;
        case 'pending':
          return u['email_confirmed'] != true;
        case 'approved':
          return u['is_approved'] == true;
        default:
          return true;
      }
    }).toList();

    return Column(
      children: [
        // Search & Filter Bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _filterStatus,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                    value: 'all', child: Text('All')),
                DropdownMenuItem(
                    value: 'confirmed',
                    child: Text('Confirmed')),
                DropdownMenuItem(
                    value: 'pending', child: Text('Pending')),
                DropdownMenuItem(
                    value: 'approved', child: Text('Approved')),
              ],
              onChanged: (v) =>
                  setState(() => _filterStatus = v!),
            ),
          ]),
        ),

        // User count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('${filteredUsers.length} users',
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 13)),
            const Spacer(),
            if (_isLoading)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2)),
          ]),
        ),

        const SizedBox(height: 8),

        // Users List
        Expanded(
          child: filteredUsers.isEmpty
              ? Center(
                  child: Text(_isLoading
                      ? 'Loading...'
                      : 'No users found'))
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filteredUsers.length,
                  itemBuilder: (_, i) {
                    final user = filteredUsers[i];
                    final email =
                        user['email']?.toString() ?? '';
                    final name =
                        user['display_name']?.toString() ??
                            'User';
                    final isApproved =
                        user['is_approved'] == true;
                    final isConfirmed =
                        user['email_confirmed'] == true;
                    final role =
                        user['role']?.toString() ?? 'staff';
                    final userId =
                        user['id']?.toString() ?? '';
                    final companiesCount =
                        user['companies_count'] ?? 0;

                    return Card(
                      margin:
                          const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: isApproved
                              ? Colors.green
                              : (isConfirmed
                                  ? Colors.blue
                                  : Colors.orange),
                          child: Text(
                            name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontWeight:
                                    FontWeight.w600)),
                        subtitle: Text(email,
                            style: const TextStyle(
                                fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isConfirmed)
                              _statusBadge('PENDING',
                                  Colors.orange),
                            if (isConfirmed && !isApproved)
                              _statusBadge(
                                  'CONFIRMED', Colors.blue),
                            if (isApproved)
                              _statusBadge(
                                  'ACTIVE', Colors.green),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _infoRow('Email', email),
                                _infoRow('Role',
                                    role.toUpperCase()),
                                _infoRow('Companies',
                                    '$companiesCount'),
                                _infoRow(
                                    'Status',
                                    isApproved
                                        ? 'Active'
                                        : (isConfirmed
                                            ? 'Confirmed'
                                            : 'Pending')),
                                const Divider(),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (!isConfirmed)
                                      ActionChip(
                                        avatar: const Icon(
                                            Icons.verified,
                                            size: 16),
                                        label: const Text(
                                            'Force Confirm'),
                                        onPressed: () =>
                                            _forceConfirmUser(
                                                userId),
                                        backgroundColor:
                                            Colors.blue
                                                .shade50,
                                      ),
                                    if (!isApproved)
                                      ActionChip(
                                        avatar: const Icon(
                                            Icons.check,
                                            size: 16),
                                        label: const Text(
                                            'Approve'),
                                        onPressed: () =>
                                            _approveUser(
                                                userId),
                                        backgroundColor:
                                            Colors.green
                                                .shade50,
                                      ),
                                    ActionChip(
                                      avatar: const Icon(
                                          Icons.edit,
                                          size: 16),
                                      label: const Text(
                                          'Change Role'),
                                      onPressed: () =>
                                          _changeRole(userId,
                                              role, email),
                                    ),
                                    ActionChip(
                                      avatar: const Icon(
                                          Icons.notifications,
                                          size: 16),
                                      label: const Text(
                                          'Notify'),
                                      onPressed: () =>
                                          _sendNotificationToUser(
                                              userId, email),
                                    ),
                                    ActionChip(
                                      avatar: const Icon(
                                          Icons.info_outline,
                                          size: 16),
                                      label: const Text(
                                          'Details'),
                                      onPressed: () =>
                                          _viewUserDetails(
                                              userId),
                                    ),
                                    ActionChip(
                                      avatar: const Icon(
                                          Icons.block,
                                          size: 16,
                                          color: Colors.red),
                                      label: const Text(
                                          'Deactivate',
                                          style: TextStyle(
                                              color:
                                                  Colors.red)),
                                      onPressed: () =>
                                          _deactivateUser(
                                              userId, email),
                                      backgroundColor:
                                          Colors.red.shade50,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}