import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/inventory_list_bloc.dart';
import '../../inventory_management/bloc/inventory_bloc.dart';
import '../../inventory_management/screens/inventory_home_screen.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/inventory_list_widget.dart';
import '../widgets/create_inventory_dialog.dart';
import '../../../core/utils/snackbar_utils.dart';

class InventorySelectionScreen extends StatefulWidget {
  const InventorySelectionScreen({super.key});

  @override
  State<InventorySelectionScreen> createState() => _InventorySelectionScreenState();
}

class _InventorySelectionScreenState extends State<InventorySelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryListBloc>().add(const LoadInventories());
    });
  }

  void _openInventory(String id) {
    context.read<InventoryListBloc>().add(SelectInventory(id));
    context.read<InventoryBloc>().add(InitializeInventory(id));
    Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryHomeScreen())).then((_) {
      if (mounted) context.read<InventoryListBloc>().add(const ClearSelection());
    });
  }

  void _showCreateDialog() {
    CreateInventoryDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<InventoryListBloc, InventoryListState>(
      listener: (context, state) {
        if (state.error != null && mounted) SnackBarUtils.error(context, state.error!);
        if (state.successMessage != null && mounted) {
          SnackBarUtils.success(context, state.successMessage!);
        }
      },
      child: BlocBuilder<InventoryListBloc, InventoryListState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Inventories'),
              actions: [
                if (state.isOffline)
                  const Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('Offline', style: TextStyle(fontSize: 10)), backgroundColor: Colors.orange, labelStyle: TextStyle(color: Colors.white), avatar: Icon(Icons.cloud_off, size: 14, color: Colors.white))),
                if (state.isCacheOnly && !state.isOffline)
                  const Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('Cached', style: TextStyle(fontSize: 10)), backgroundColor: Colors.blue, labelStyle: TextStyle(color: Colors.white), avatar: Icon(Icons.cloud_outlined, size: 14, color: Colors.white))),
              ],
            ),
            floatingActionButton: state.isOffline ? null : FloatingActionButton.extended(onPressed: _showCreateDialog, icon: const Icon(Icons.add_rounded), label: const Text('New Inventory'), elevation: 4),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
            body: RefreshIndicator(
              onRefresh: () async { if (mounted) context.read<InventoryListBloc>().add(const RefreshInventories()); },
              child: state.isLoading && state.inventories.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : state.error != null && state.inventories.isEmpty
                      ? _buildError(state.error!)
                      : state.inventories.isEmpty
                          ? EmptyStateWidget(onCreateInventory: state.isOffline ? null : _showCreateDialog)
                          : InventoryListWidget(inventories: state.inventories, onOpenInventory: _openInventory),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(error, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: () => context.read<InventoryListBloc>().add(const RefreshInventories()), icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ),
    );
  }
}