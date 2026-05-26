import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/admin_bloc.dart';

class AuditLogViewer extends StatefulWidget {
  const AuditLogViewer({super.key});

  @override
  State<AuditLogViewer> createState() => _AuditLogViewerState();
}

class _AuditLogViewerState extends State<AuditLogViewer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AdminBloc>().add(const LoadAuditLogs());
      }
    });
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
    } catch (_) {
      return raw.length >= 19 ? raw.substring(0, 19) : raw;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatAction(String action) {
    switch (action) {
      case 'approve_user': return 'Approved User';
      case 'deactivate_user': return 'Deactivated User';
      case 'force_confirm_user': return 'Force Confirmed User';
      case 'create_user': return 'Created User';
      case 'update_user_role': return 'Updated User Role';
      default:
        return action.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : w).join(' ');
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'approve_user': return Icons.check_circle;
      case 'deactivate_user': return Icons.cancel;
      case 'force_confirm_user': return Icons.verified_user;
      case 'create_user': return Icons.person_add;
      case 'update_user_role': return Icons.manage_accounts;
      default: return Icons.info;
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'approve_user':
      case 'force_confirm_user':
      case 'create_user':
        return Colors.green;
      case 'deactivate_user':
        return Colors.red;
      case 'update_user_role':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Text('Audit Log', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<AdminBloc>().add(const LoadAuditLogs()),
                  tooltip: 'Refresh',
                ),
              ]),
            ),
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : state.auditLogs.isEmpty
                      ? const Center(child: Text('No audit logs yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: state.auditLogs.length,
                          itemBuilder: (_, i) {
                            final log = state.auditLogs[i];
                            final action = log['action']?.toString() ?? '';
                            final adminEmail = log['admin']?['email']?.toString() ?? 'System';
                            final targetEmail = log['details']?['email']?.toString() ?? '';
                            final timestamp = _formatDateTime(log['created_at']?.toString());
                            final color = _getActionColor(action);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.12),
                                  child: Icon(_getActionIcon(action), size: 20, color: color),
                                ),
                                title: Text(_formatAction(action), style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('By: $adminEmail${targetEmail.isNotEmpty ? '\nTarget: $targetEmail' : ''}\n$timestamp'),
                                isThreeLine: true,
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
}