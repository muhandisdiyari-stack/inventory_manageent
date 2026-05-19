import 'package:flutter/material.dart';
import '../../../core/services/admin_service.dart';

class AuditLogViewer extends StatefulWidget {
  const AuditLogViewer({super.key});

  @override
  State<AuditLogViewer> createState() => _AuditLogViewerState();
}

class _AuditLogViewerState extends State<AuditLogViewer> {
  final AdminService _adminService = AdminService();
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    _logs = await _adminService.getAuditLogs();
    setState(() => _isLoading = false);
  }

  String _formatAction(String action) {
    switch (action) {
      case 'approve_user':
        return 'Approved User';
      case 'deactivate_user':
        return 'Deactivated User';
      default:
        return action.replaceAll('_', ' ').toUpperCase();
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'approve_user':
        return Icons.check_circle;
      case 'deactivate_user':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('Audit Log', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadLogs,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? const Center(child: Text('No audit logs yet'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final log = _logs[i];
                        final action = log['action']?.toString() ?? '';
                        final admin = log['admin']?['email']?.toString() ?? 'System';
                        final targetEmail = log['details']?['email']?.toString() ?? '';
                        final createdAt = log['created_at']?.toString() ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade100,
                              child: Icon(_getActionIcon(action), size: 20),
                            ),
                            title: Text(_formatAction(action), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('By: $admin${targetEmail.isNotEmpty ? '\nTarget: $targetEmail' : ''}\n${createdAt.substring(0, 19)}'),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}