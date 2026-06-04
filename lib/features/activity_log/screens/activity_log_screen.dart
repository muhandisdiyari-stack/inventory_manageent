import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../inventory_selection/bloc/inventory_list_bloc.dart';
import '../bloc/activity_log_bloc.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ActivityLogBloc>().add(const LoadActivityLogs());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final listState = context.watch<InventoryListBloc>().state;

    return BlocListener<ActivityLogBloc, ActivityLogState>(
      listener: (context, state) {
        if (state.exportedFilePath != null) {
          if (!mounted) return;
          SnackBarUtils.success(
            context,
            state.exportedFilePath == 'web_download'
                ? 'Log downloaded!'
                : 'Log saved',
          );
        }
        if (state.error != null) {
          if (!mounted) return;
          SnackBarUtils.error(context, state.error!);
        }
      },
      child: BlocBuilder<ActivityLogBloc, ActivityLogState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Activity Log'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.bar_chart),
                  tooltip: 'Statistics',
                  onPressed: () => context
                      .read<ActivityLogBloc>()
                      .add(const ToggleStatistics()),
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Export Log',
                  onPressed: _exportLogs,
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search logs...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: state.searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () => context
                                  .read<ActivityLogBloc>()
                                  .add(const SetSearchQuery('')),
                            )
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(40)),
                      filled: true,
                    ),
                    onChanged: (value) => context
                        .read<ActivityLogBloc>()
                        .add(SetSearchQuery(value)),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _buildFilterChip(context, 'All', null),
                      const SizedBox(width: 8),
                      _buildFilterChip(context, 'Created', 'created'),
                      const SizedBox(width: 8),
                      _buildFilterChip(context, 'Modified', 'modified'),
                      const SizedBox(width: 8),
                      _buildFilterChip(context, 'Deleted', 'deleted'),
                      if (listState.inventories.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        const VerticalDivider(width: 1),
                        const SizedBox(width: 8),
                        ...listState.inventories.map((inv) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(inv.name,
                                    style: const TextStyle(fontSize: 12)),
                                selected: state.filterInventoryId == inv.id,
                                onSelected: (selected) {
                                  context.read<ActivityLogBloc>().add(
                                      SetFilterInventory(selected ? inv.id : null));
                                },
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
                if (state.showStats)
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Statistics',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          _buildStatRow(
                              'Total Logs', state.statistics['totalLogs'].toString()),
                          _buildStatRow(
                              'Created', state.statistics['created'].toString()),
                          _buildStatRow(
                              'Modified', state.statistics['modified'].toString()),
                          _buildStatRow(
                              'Deleted', state.statistics['deleted'].toString()),
                          const Divider(),
                          ...(state.statistics['byType'] as Map<String, int>? ?? {})
                              .entries
                              .map((e) => _buildStatRow(e.key, e.value.toString())),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.logs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text('No activity logged yet',
                                      style: TextStyle(
                                          color: Colors.grey[600], fontSize: 16)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: state.logs.length,
                              itemBuilder: (context, index) {
                                return _buildLogCard(state.logs[index]);
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(
      BuildContext context, String label, String? entityType) {
    final state = context.watch<ActivityLogBloc>().state;
    final isSelected = (entityType == null &&
            state.filterEntityType == null &&
            state.filterInventoryId == null) ||
        (entityType != null && state.filterEntityType == entityType);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (selected) {
        context.read<ActivityLogBloc>().add(
              SetFilterEntityType(selected ? entityType : null),
            );
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
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
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
        break;
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
                  Text('Details:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text(log.details!, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                ],
                if (log.changes != null && log.changes!.isNotEmpty) ...[
                  Text('Changes:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.grey[700])),
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

  Future<void> _exportLogs() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Activity Log'),
        content: const Text('Download the activity log as a text file?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'download'),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (result == 'download' && mounted) {
      context.read<ActivityLogBloc>().add(const ExportActivityLogs());
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}