import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_list_provider.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../inventory_management/screens/inventory_home_screen.dart';
import '../../activity_log/screens/activity_log_screen.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/inventory_list_widget.dart';
import '../widgets/create_inventory_dialog.dart';

class InventorySelectionScreen extends StatefulWidget {
  const InventorySelectionScreen({super.key});

  @override
  State<InventorySelectionScreen> createState() => _InventorySelectionScreenState();
}

class _InventorySelectionScreenState extends State<InventorySelectionScreen> {
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      final listProvider = context.read<InventoryListProvider>();
      listProvider.initialize();
      
      if (!mounted) return;
      setState(() => _isInitializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'Failed to load inventories: ${e.toString()}';
      });
    }
  }

  Future<void> _refreshInventories() async {
    if (!mounted) return;

    setState(() => _error = null);

    try {
      await context.read<InventoryListProvider>().refreshInventories();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to refresh: ${e.toString()}');
    }
  }

  void _openInventory(String id) {
    if (!mounted) return;

    final listProvider = context.read<InventoryListProvider>();
    final service = context.read<InventoryService>();
    
    listProvider.selectInventory(id);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InventoryHomeScreen(),
      ),
    ).then((_) {
      // Refresh list when returning
      if (mounted) {
        _refreshInventories();
      }
    });
  }

  void _showCreateDialog() {
    if (!mounted) return;
    final listProvider = context.read<InventoryListProvider>();
    final service = context.read<InventoryService>();

    CreateInventoryDialog.show(context, listProvider, service);
  }

  void _openActivityLog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listProvider = context.watch<InventoryListProvider>();
    final service = context.read<InventoryService>();

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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _refreshInventories,
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  displacement: 60,
                  child: SafeArea(
                    child: listProvider.inventories.isEmpty
                        ? EmptyStateWidget(onCreateInventory: _showCreateDialog)
                        : InventoryListWidget(
                            inventories: listProvider.inventories,
                            listProvider: listProvider,
                            service: service,
                            onOpenInventory: _openInventory,
                          ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _refreshInventories,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}