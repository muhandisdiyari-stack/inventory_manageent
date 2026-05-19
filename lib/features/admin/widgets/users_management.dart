import 'package:flutter/material.dart';
import '../../../core/services/admin_service.dart';

class UsersManagement extends StatefulWidget {
  const UsersManagement({super.key});

  @override
  State<UsersManagement> createState() => _UsersManagementState();
}

class _UsersManagementState extends State<UsersManagement> {
  final AdminService _adminService = AdminService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    _users = await _adminService.getAllUsers();
    setState(() => _isLoading = false);
  }

  Future<void> _approveUser(String userId) async {
    await _adminService.approveUser(userId);
    await _loadUsers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User approved'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _deactivateUser(String userId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate User'),
        content: Text('Deactivate $email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deactivate', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await _adminService.deleteUser(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email deactivated'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _sendNotification(String userId, String email) async {
    final titleController = TextEditingController();
    final messageController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send Notification to $email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: messageController, maxLines: 3, decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );

    if (result == true && titleController.text.isNotEmpty) {
      await _adminService.sendNotification(userId, titleController.text, messageController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification sent'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _searchQuery.isEmpty
        ? _users
        : _users.where((u) {
            final email = (u['email'] ?? '').toString().toLowerCase();
            final name = (u['display_name'] ?? '').toString().toLowerCase();
            return email.contains(_searchQuery.toLowerCase()) || name.contains(_searchQuery.toLowerCase());
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredUsers.isEmpty
                  ? const Center(child: Text('No users found'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredUsers.length,
                      itemBuilder: (_, i) {
                        final user = filteredUsers[i];
                        final email = user['email']?.toString() ?? '';
                        final name = user['display_name']?.toString() ?? 'User';
                        final isApproved = user['is_approved'] == true;
                        final role = user['role']?.toString() ?? 'staff';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isApproved ? Colors.green : Colors.orange,
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('$email\nRole: $role'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                final userId = user['id']?.toString() ?? '';
                                if (action == 'approve' && !isApproved) _approveUser(userId);
                                if (action == 'deactivate') _deactivateUser(userId, email);
                                if (action == 'notify') _sendNotification(userId, email);
                              },
                              itemBuilder: (ctx) => [
                                if (!isApproved) const PopupMenuItem(value: 'approve', child: Text('Approve')),
                                const PopupMenuItem(value: 'notify', child: Text('Send Notification')),
                                const PopupMenuItem(value: 'deactivate', child: Text('Deactivate', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}