import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_list_provider.dart';
import '../models/inventory_list_item.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../inventory_management/screens/inventory_home_screen.dart';
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
      if (mounted) {
        context.read<InventoryListProvider>().initialize();
      }
    });
  }

  Future<void> _refreshInventories() async {
    if (!mounted) return;
    await context.read<InventoryListProvider>().refreshInventories();
  }

  void _openInventory(String id) {
    if (!mounted) return;
    
    final listProvider = context.read<InventoryListProvider>();
    listProvider.selectInventory(id);
    
    Future.microtask(() {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const InventoryHomeScreen(),
          ),
        );
      }
    });
  }

  void _showCreateDialog() {
    if (!mounted) return;
    final listProvider = context.read<InventoryListProvider>();
    final service = context.read<InventoryService>();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        CreateInventoryDialog.show(context, listProvider, service);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final listProvider = context.watch<InventoryListProvider>();
    final service = context.read<InventoryService>();
    final inventories = listProvider.inventories;
    final isLoading = listProvider.isLoading;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Inventory'),
        elevation: 4,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: RefreshIndicator(
        onRefresh: _refreshInventories,
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: Theme.of(context).colorScheme.surface,
        displacement: 60,
        child: SafeArea(
          child: _buildBody(context, inventories, isLoading, listProvider, service),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<InventoryListItem> inventories,
    bool isLoading,
    InventoryListProvider listProvider,
    InventoryService service,
  ) {
    // Show loading indicator when loading
    if (isLoading && inventories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading inventories...'),
          ],
        ),
      );
    }

    // Show empty state when no inventories
    if (inventories.isEmpty) {
      return EmptyStateWidget(
        onCreateInventory: _showCreateDialog,
      );
    }

    // Show inventory list
    return InventoryListWidget(
      inventories: inventories,
      listProvider: listProvider,
      service: service,
      onOpenInventory: (String id, dynamic provider) {
        _openInventory(id);
      },
    );
  }
}