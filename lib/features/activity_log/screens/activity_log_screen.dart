import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  String? _filterInventoryId;
  String? _filterEntityType;
  String _searchQuery = '';
  bool _showStats = false;

  @override
  Widget build(BuildContext context) {
    final listProvider = context.watch<InventoryListProvider>();
    final logService = ActivityLogService();
    final allLogs = logService.getLogs(
      inventoryId: _filterInventoryId,
      entityType: _filterEntityType,
    );
    
    final logs = allLogs.where((log) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return log.entityName.toLowerCase().contains(q) ||
          (log.details?.toLowerCase().contains(q) ?? false) ||
          (log.inventoryName?.toLowerCase().contains(q) ?? false);
    }).toList();

    final stats = logService.getStatistics(inventoryId: _filterInventoryId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistics',
            onPressed: () => setState(() => _showStats = !_showStats),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Log',
            onPressed: () => _exportLogs(logService),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search logs...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(40)),
                filled: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildFilterChip('All', null),
                const SizedBox(width: 8),
                _buildFilterChip('Created', 'created'),
                const SizedBox(width: 8),
                _buildFilterChip('Modified', 'modified'),
                const SizedBox(width: 8),
                _buildFilterChip('Deleted', 'deleted'),
                if (listProvider.inventories.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 8),
                  ...listProvider.inventories.map((inv) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(inv.name, style: const TextStyle(fontSize: 12)),
                      selected: _filterInventoryId == inv.id,
                      onSelected: (selected) {
                        setState(() {
                          _filterInventoryId = selected ? inv.id : null;
                        });
                      },
                    ),
                  )),
                ],
              ],
            ),
          ),
          // Statistics card
          if (_showStats)
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Statistics', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _buildStatRow('Total Logs', stats['totalLogs'].toString()),
                    _buildStatRow('Created', stats['created'].toString()),
                    _buildStatRow('Modified', stats['modified'].toString()),
                    _buildStatRow('Deleted', stats['deleted'].toString()),
                    const Divider(),
                    ...(stats['byType'] as Map<String, int>).entries.map(
                      (e) => _buildStatRow(e.key, e.value.toString()),
                    ),
                  ],
                ),
              ),
            ),
          // Logs list
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('No activity logged yet',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      return _buildLogCard(logs[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? entityType) {
    final isSelected = (entityType == null && _filterEntityType == null && _filterInventoryId == null) ||
        (entityType != null && _filterEntityType == entityType);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterEntityType = selected ? entityType : null;
        });
      },
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.capitalize(), style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLogCard(ActivityLogEntry log) {
    final theme = Theme.of(context);
    IconData icon;
    Color color;

    switch (log.action) {
      case 'created':
        icon = Icons.add_circle;
        color = Colors.green;
        break;
      case 'modified':
        icon = Icons.edit;
        color = Colors.orange;
        break;
      case 'deleted':
        icon = Icons.delete;
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 24),
        title: Text(
          '${log.entityType.toUpperCase()}: ${log.entityName}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (log.inventoryName != null)
              Text('📦 ${log.inventoryName}', style: const TextStyle(fontSize: 11)),
            if (log.labelName != null)
              Text('🏷️ ${log.labelName}', style: const TextStyle(fontSize: 11)),
            Text(
              _formatTimestamp(log.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (log.details != null) ...[
                  Text('Details:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text(log.details!, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                ],
                if (log.changes != null && log.changes!.isNotEmpty) ...[
                  Text('Changes:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  const SizedBox(height: 8),
                  ...log.changes!.entries.map((change) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(change.key,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          color: Colors.grey[600])),
                                  const SizedBox(height: 4),
                                  Text('Old: ${change.value.oldValue}',
                                      style: const TextStyle(fontSize: 12)),
                                  Text('New: ${change.value.newValue}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.primary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Future<void> _exportLogs(ActivityLogService logService) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Activity Log'),
        content: const Text('Download the activity log as a text file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, 'download');
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (result == 'download' && mounted) {
      final filePath = await logService.saveLogsToFile(
        inventoryId: _filterInventoryId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(filePath == 'web_download'
                ? 'Log downloaded!'
                : 'Log saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}