import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/admin_bloc.dart';

class UsersManagement extends StatefulWidget {
  const UsersManagement({super.key});

  @override
  State<UsersManagement> createState() => _UsersManagementState();
}

class _UsersManagementState extends State<UsersManagement> {
  String _searchQuery = '';
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AdminBloc>().add(const LoadUsers());
      }
    });
  }

  void _changeRole(String userId, String currentRole, String email) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Change Role for $email'),
        children: ['owner', 'admin', 'data_operator', 'viewer']
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
                    Text(role
                        .replaceAll('_', ' ')
                        .split(' ')
                        .map((w) => w.isNotEmpty
                            ? w[0].toUpperCase() + w.substring(1)
                            : w)
                        .join(' ')),
                  ]),
                ))
            .toList(),
      ),
    );

    if (newRole != null && newRole != currentRole && mounted) {
      context
          .read<AdminBloc>()
          .add(UpdateUserRole(userId, newRole));
    }
  }

  void _sendNotificationToUser(String userId, String email) async {
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

    if (confirmed == true &&
        titleController.text.isNotEmpty &&
        mounted) {
      context.read<AdminBloc>().add(SendNotificationToUser(
            userId: userId,
            title: titleController.text,
            message: messageController.text,
          ));
    }
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) {
        final filteredUsers = state.users.where((u) {
          final email =
              (u['email'] ?? '').toString().toLowerCase();
          final name = (u['display_name'] ?? u['full_name'] ?? '')
              .toString()
              .toLowerCase();
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search users...',
                      prefixIcon:
                          const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
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
                        value: 'pending',
                        child: Text('Pending')),
                    DropdownMenuItem(
                        value: 'approved',
                        child: Text('Approved')),
                  ],
                  onChanged: (v) =>
                      setState(() => _filterStatus = v!),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text('${filteredUsers.length} users',
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13)),
                const Spacer(),
                if (state.isLoading)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2)),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredUsers.isEmpty
                  ? Center(
                      child: Text(state.isLoading
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
                        final name = user['display_name']?.toString() ??
                            user['full_name']?.toString() ??
                            'User';
                        final isApproved =
                            user['is_approved'] == true;
                        final isConfirmed =
                            user['email_confirmed'] == true;
                        final role =
                            user['role']?.toString() ?? 'viewer';
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
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(email,
                                style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isConfirmed)
                                  _statusBadge(
                                      'PENDING', Colors.orange),
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
                                            onPressed: () => context
                                                .read<AdminBloc>()
                                                .add(ForceConfirmUser(
                                                    userId)),
                                            backgroundColor:
                                                Colors.blue.shade50,
                                          ),
                                        if (!isApproved)
                                          ActionChip(
                                            avatar: const Icon(
                                                Icons.check,
                                                size: 16),
                                            label: const Text(
                                                'Approve'),
                                            onPressed: () => context
                                                .read<AdminBloc>()
                                                .add(ApproveUser(
                                                    userId)),
                                            backgroundColor:
                                                Colors.green.shade50,
                                          ),
                                        ActionChip(
                                          avatar: const Icon(
                                              Icons.edit,
                                              size: 16),
                                          label: const Text(
                                              'Change Role'),
                                          onPressed: () =>
                                              _changeRole(
                                                  userId,
                                                  role,
                                                  email),
                                        ),
                                        ActionChip(
                                          avatar: const Icon(
                                              Icons.notifications,
                                              size: 16),
                                          label:
                                              const Text('Notify'),
                                          onPressed: () =>
                                              _sendNotificationToUser(
                                                  userId, email),
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
                                          onPressed: () => context
                                              .read<AdminBloc>()
                                              .add(DeactivateUser(
                                                  userId, email)),
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
      },
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
}