import 'package:flutter/material.dart';
import '../../../core/services/admin_service.dart';

class NotificationsPanel extends StatefulWidget {
  final AdminService adminService;

  const NotificationsPanel({super.key, required this.adminService});

  @override
  State<NotificationsPanel> createState() =>
      _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final notifications =
        await widget.adminService.getNotifications();

    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });
  }

  Future<void> _markAsRead(String id) async {
    await widget.adminService.markNotificationRead(id);
    if (!mounted) return;
    await _loadNotifications();
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'warning':
        return Icons.warning_amber;
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'warning':
        return Colors.orange;
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text('Notifications',
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadNotifications,
              tooltip: 'Refresh',
            ),
          ]),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No notifications',
                              style:
                                  TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) {
                        final notif = _notifications[i];
                        final title =
                            notif['title']?.toString() ?? '';
                        final message =
                            notif['message']?.toString() ?? '';
                        final type =
                            notif['type']?.toString() ?? 'info';
                        final isRead = notif['is_read'] == true;
                        final id =
                            notif['id']?.toString() ?? '';
                        final color = _getTypeColor(type);

                        return Card(
                          margin:
                              const EdgeInsets.only(bottom: 8),
                          // Use withOpacity instead of the
                          // non-existent withValues(alpha:).
                          color: isRead
                              ? null
                              : Colors.blue.withOpacity(0.07),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  color.withOpacity(0.12),
                              child: Icon(
                                _getTypeIcon(type),
                                color: color,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isRead
                                ? null
                                : IconButton(
                                    icon: const Icon(
                                        Icons.check,
                                        size: 18),
                                    tooltip: 'Mark as read',
                                    onPressed: () =>
                                        _markAsRead(id),
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