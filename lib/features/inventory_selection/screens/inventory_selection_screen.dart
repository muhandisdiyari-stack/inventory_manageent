import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/inventory_list_bloc.dart';
import '../../inventory_management/bloc/inventory_bloc.dart';
import '../../inventory_management/screens/inventory_home_screen.dart';
import '../../activity_log/screens/activity_log_screen.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/inventory_list_widget.dart';
import '../widgets/create_inventory_dialog.dart';

class InventorySelectionScreen extends StatefulWidget {
  const InventorySelectionScreen({super.key});

  @override
  State<InventorySelectionScreen> createState() =>
      _InventorySelectionScreenState();
}

class _InventorySelectionScreenState extends State<InventorySelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryListBloc>().add(const LoadInventories());
    });
  }

  /// Opens an inventory by dispatching events to both BLoCs.
  /// This ensures InventoryBloc is initialized before the home screen loads.
  void _openInventory(String id) {
    // 1. Tell InventoryListBloc which inventory is selected
    context.read<InventoryListBloc>().add(SelectInventory(id));

    // 2. Tell InventoryBloc to initialize with this inventory ID
    //    This replaces the old ChangeNotifierProxyProvider auto-sync behavior.
    context.read<InventoryBloc>().add(InitializeInventory(id));

    // 3. Navigate to the inventory home screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InventoryHomeScreen(),
      ),
    ).then((_) {
      // Refresh inventory list when returning
      if (mounted) {
        context.read<InventoryListBloc>().add(const LoadInventories());
      }
    });
  }

  void _showCreateDialog() {
    CreateInventoryDialog.show(context);
  }

  void _openActivityLog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryListBloc, InventoryListState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventory Pro'),
            actions: [
              IconButton(
                tooltip: 'Activity Log',
                icon: const Icon(Icons.history),
                onPressed: _openActivityLog,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Inventory'),
            elevation: 4,
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          body: state.isLoading && state.inventories.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.inventories.isEmpty
                  ? _buildErrorState(state.error!)
                  : RefreshIndicator(
                      onRefresh: () async {
                        context
                            .read<InventoryListBloc>()
                            .add(const LoadInventories());
                      },
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      displacement: 60,
                      child: SafeArea(
                        child: state.inventories.isEmpty
                            ? EmptyStateWidget(
                                onCreateInventory: _showCreateDialog)
                            : InventoryListWidget(
                                inventories: state.inventories,
                                onOpenInventory: _openInventory,
                              ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  context.read<InventoryListBloc>().add(const LoadInventories()),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}