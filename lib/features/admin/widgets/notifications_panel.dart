import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/admin_bloc.dart';

class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({super.key});

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AdminBloc>().add(const LoadNotifications());
      }
    });
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'warning': return Icons.warning_amber;
      case 'success': return Icons.check_circle;
      case 'error': return Icons.error;
      default: return Icons.info;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'warning': return Colors.orange;
      case 'success': return Colors.green;
      case 'error': return Colors.red;
      default: return Colors.blue;
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
                Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<AdminBloc>().add(const LoadNotifications()),
                  tooltip: 'Refresh',
                ),
              ]),
            ),
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : state.notifications.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none, size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No notifications', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: state.notifications.length,
                          itemBuilder: (_, i) {
                            final notif = state.notifications[i];
                            final title = notif['title']?.toString() ?? '';
                            final message = notif['message']?.toString() ?? '';
                            final type = notif['type']?.toString() ?? 'info';
                            final isRead = notif['is_read'] == true;
                            final id = notif['id']?.toString() ?? '';
                            final color = _getTypeColor(type);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: isRead ? null : Colors.blue.withValues(alpha: 0.07),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.12),
                                  child: Icon(_getTypeIcon(type), color: color, size: 20),
                                ),
                                title: Text(title,
                                    style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.w600)),
                                subtitle: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: isRead
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.check, size: 18),
                                        tooltip: 'Mark as read',
                                        onPressed: () => context.read<AdminBloc>().add(MarkNotificationRead(id)),
                                      ),
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