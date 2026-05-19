import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../services/inventory_service.dart';
import '../widgets/add_item_sheet.dart';
import '../widgets/label_list_widget.dart';
import '../widgets/items_list_widget.dart';
import '../../search/screens/search_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../activity_log/screens/activity_log_screen.dart';
import '../../import/screens/bulk_import_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../company/screens/company_settings_screen.dart';


class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key});

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  String? _currentLabel;
  final _labelSearchController = TextEditingController();
  final _itemSearchController = TextEditingController();
  bool _showItemsView = false;
  LabelSortType _labelSortType = LabelSortType.nameAsc;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeInventory();
    });
    
    _labelSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _itemSearchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _labelSearchController.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeInventory() async {
    if (!mounted) return;
    
    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<InventoryProvider>();
      await provider.initializeCurrentInventory();

      if (!mounted) return;

      setState(() {
        if (provider.hasLabels && _currentLabel == null) {
          _currentLabel = provider.labels.first;
        }
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        _errorMessage = 'Failed to load inventory: ${e.toString()}';
      });
    }
  }

  Future<void> _refreshInventory() async {
    if (!mounted) return;
    
    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<InventoryProvider>();
      await provider.initializeCurrentInventory();

      if (!mounted) return;

      setState(() {
        if (_currentLabel != null && !provider.hasLabel(_currentLabel!)) {
          _currentLabel = provider.hasLabels ? provider.labels.first : null;
        }
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        _errorMessage = 'Failed to refresh: ${e.toString()}';
      });
    }
  }

  void _selectLabel(String label) {
    setState(() {
      _currentLabel = label;
      _showItemsView = true;
      _itemSearchController.clear();
      _errorMessage = null;
    });
  }

  void _onSortChanged(LabelSortType sortType) {
    setState(() => _labelSortType = sortType);
  }

  void _bulkImport() {
    final provider = context.read<InventoryProvider>();
    final inventoryId = provider.currentInventoryId;
    
    if (inventoryId == null) {
      _showSnackBar('No inventory selected');
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BulkImportScreen(
          inventoryId: inventoryId,
          inventoryName: provider.currentInventoryName ?? 'Inventory',
        ),
      ),
    ).then((_) {
      if (mounted) {
        context.read<InventoryProvider>().initializeCurrentInventory();
        setState(() {});
      }
    });
  }

  void _showCreateLabelDialog() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _LabelNameSheet(
        title: 'New Label',
        hint: 'Label name',
        submitLabel: 'Save',
        controller: controller,
        onSubmit: (name) async {
          final provider = context.read<InventoryProvider>();
          if (provider.hasLabel(name)) {
            _showSnackBar('"$name" already exists', isError: true);
            return false;
          }
          
          try {
            await provider.createLabel(name);
            if (!mounted) return false;
            
            setState(() => _currentLabel = name);
            _labelSearchController.clear();
            _showSnackBar('✅ "$name" created');
            return true;
          } catch (e) {
            if (!mounted) return false;
            _showSnackBar('Error creating label: $e', isError: true);
            return false;
          }
        },
      ),
    );
  }

  void _showRenameDialog(String oldLabel) {
    final controller = TextEditingController(text: oldLabel);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _LabelNameSheet(
        title: 'Rename Label',
        hint: 'New label name',
        submitLabel: 'Update',
        controller: controller,
        onSubmit: (newName) async {
          if (newName == oldLabel) return true;
          
          final provider = context.read<InventoryProvider>();
          if (provider.hasLabel(newName)) {
            _showSnackBar('"$newName" already exists', isError: true);
            return false;
          }
          
          try {
            await provider.renameLabel(oldLabel, newName);
            if (!mounted) return false;
            
            setState(() {
              if (_currentLabel == oldLabel) _currentLabel = newName;
            });
            _labelSearchController.clear();
            _showSnackBar('Renamed to "$newName"');
            return true;
          } catch (e) {
            if (!mounted) return false;
            _showSnackBar('Error renaming label: $e', isError: true);
            return false;
          }
        },
      ),
    );
  }

  void _deleteLabel(String label) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Label'),
        content: Text('Delete "$label" and all its items?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              try {
                final provider = context.read<InventoryProvider>();
                await provider.deleteLabel(label);

                if (!mounted) return;

                setState(() {
                  if (_currentLabel == label) {
                    _currentLabel = provider.hasLabels ? provider.labels.first : null;
                  }
                });
                _labelSearchController.clear();
                _showSnackBar('🗑️ "$label" deleted');
              } catch (e) {
                if (!mounted) return;
                _showSnackBar('Error deleting label: $e', isError: true);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog({InventoryItem? existingItem}) {
    if (_currentLabel == null) {
      _showSnackBar('Select a label first');
      return;
    }

    final provider = context.read<InventoryProvider>();

    AddItemSheet.show(
      context,
      label: _currentLabel!,
      settings: provider.currentSettings,
      existingItem: existingItem,
      inventoryName: provider.currentInventoryName,
      inventoryId: provider.currentInventoryId,
      onSave: (item) async {
        try {
          if (provider.currentInventoryId == null) {
            _showSnackBar('No inventory selected — please select one first', isError: true);
            return;
          }
          await provider.saveItem(item);
          if (!mounted) return;
          setState(() {});
        } catch (e) {
          if (!mounted) return;
          _showSnackBar('Error saving item: $e', isError: true);
        }
      },
    );
  }

  void _editItem(InventoryItem item) {
    _showAddItemDialog(existingItem: item);
  }

  Future<void> _adjustQuantity(InventoryItem item, int delta) async {
    try {
      final oldQuantity = item.quantity;
      final newQuantity = (item.quantity + delta).clamp(0, InventoryItem.maxQuantity);
      
      if (oldQuantity == newQuantity) return;
      
      item.quantity = newQuantity;
      item.modified = DateTime.now();
      await item.save();

      if (!mounted) return;

      final provider = context.read<InventoryProvider>();
      final logEntry = ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'modified',
        entityType: 'item',
        entityName: item.displayName,
        inventoryId: provider.currentInventoryId,
        inventoryName: provider.currentInventoryName,
        labelName: item.label,
        details: 'Quantity adjusted',
        changes: {
          'quantity': FieldChange(
            oldValue: oldQuantity.toString(),
            newValue: item.quantity.toString(),
          ),
        },
      );
      await ActivityLogService().addLog(logEntry);

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error updating quantity: $e', isError: true);
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final itemName = item.displayName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "$itemName" from ${_currentLabel ?? "label"}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final provider = context.read<InventoryProvider>();

      await item.delete();

      final logEntry = ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'deleted',
        entityType: 'item',
        entityName: itemName,
        inventoryId: provider.currentInventoryId,
        inventoryName: provider.currentInventoryName,
        labelName: item.label,
        details: 'Item deleted: "$itemName"',
      );
      await ActivityLogService().addLog(logEntry);

      if (!mounted) return;
      setState(() {});
      _showSnackBar('Removed "$itemName"');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error removing item: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
          duration: AppConstants.snackbarDuration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          margin: const EdgeInsets.all(20),
        ),
      );
  }

  // ─── Build Method ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final service = context.read<InventoryService>();
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < AppConstants.mobileBreakpoint;

    final sortedLabels = service.getSortedLabels(sortType: _labelSortType);

    return PopScope(
      canPop: !_showItemsView || !isMobile,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showItemsView && isMobile) {
          setState(() => _showItemsView = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(
              (_showItemsView && isMobile) ? Icons.arrow_back : Icons.arrow_back,
            ),
            onPressed: () {
              if (_showItemsView && isMobile) {
                setState(() => _showItemsView = false);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _showItemsView && _currentLabel != null
                    ? _currentLabel!
                    : provider.currentInventoryName ?? 'Inventory',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              if (_showItemsView && _currentLabel != null)
                Text(
                  provider.currentInventoryName ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          actions: [
            // Only show actions when not in mobile items view
            if (!isMobile || !_showItemsView) ...[
              IconButton(
                tooltip: 'Members & Permissions',
                icon: const Icon(Icons.people),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompanySettingsScreen(
                      inventoryId: provider.currentInventoryId ?? 'default',
                      inventoryName: provider.currentInventoryName ?? 'Inventory',
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Bulk Import',
                icon: const Icon(Icons.cloud_upload),
                onPressed: _bulkImport,
              ),
              IconButton(
                tooltip: 'Activity Log',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Reports',
                icon: const Icon(Icons.assessment),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ],
        ),
        body: _isRefreshing
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refreshInventory,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).colorScheme.surface,
                displacement: 60,
                child: SafeArea(
                  child: _errorMessage != null
                      ? _buildErrorState()
                      : isMobile
                          ? _buildMobileLayout(provider, sortedLabels, service)
                          : _buildDesktopLayout(provider, width, sortedLabels, service),
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
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _refreshInventory,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    InventoryProvider provider,
    double width,
    List<String> sortedLabels,
    InventoryService service,
  ) {
    final sidebarWidth = (width * AppConstants.sidebarWidthRatio).clamp(250.0, 400.0);

    return Row(
      children: [
        SizedBox(
          width: sidebarWidth,
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: TextField(
                        controller: _labelSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search labels…',
                          prefixIcon: const Icon(Icons.search, size: 16),
                          suffixIcon: _labelSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () => _labelSearchController.clear(),
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(40)),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    // Labels list
                    Expanded(
                      child: LabelListWidget(
                        labels: sortedLabels,
                        currentLabel: _currentLabel,
                        searchController: _labelSearchController,
                        onSelectLabel: _selectLabel,
                        onRenameLabel: _showRenameDialog,
                        onDeleteLabel: _deleteLabel,
                        sortType: _labelSortType,
                        onSortChanged: _onSortChanged,
                        inventoryService: service,
                      ),
                    ),
                  ],
                ),
                // Add label FAB
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    heroTag: 'add_label_desktop',
                    tooltip: 'New label',
                    onPressed: _showCreateLabelDialog,
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Items panel
        Expanded(
          child: SafeArea(
            child: Stack(
              children: [
                _currentLabel == null
                    ? _buildEmptyState()
                    : ItemsListWidget(
                        items: provider.getItems(_currentLabel!),
                        label: _currentLabel!,
                        searchController: _itemSearchController,
                        onAdjustQuantity: _adjustQuantity,
                        onDeleteItem: _deleteItem,
                        onAddItem: () => _showAddItemDialog(),
                        onEditItem: _editItem,
                      ),
                if (_currentLabel != null)
                  Positioned(
                    bottom: 24,
                    right: 24,
                    child: FloatingActionButton(
                      heroTag: 'add_item_desktop',
                      tooltip: 'Add item',
                      onPressed: () => _showAddItemDialog(),
                      child: const Icon(Icons.add_box),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    InventoryProvider provider,
    List<String> sortedLabels,
    InventoryService service,
  ) {
    if (_showItemsView && _currentLabel != null) {
      return SafeArea(
        child: Stack(
          children: [
            ItemsListWidget(
              items: provider.getItems(_currentLabel!),
              label: _currentLabel!,
              searchController: _itemSearchController,
              onAdjustQuantity: _adjustQuantity,
              onDeleteItem: _deleteItem,
              onAddItem: () => _showAddItemDialog(),
              onEditItem: _editItem,
            ),
            Positioned(
              bottom: AppConstants.fabBottomMargin,
              right: AppConstants.fabRightMargin,
              child: FloatingActionButton(
                heroTag: 'add_item_mobile',
                tooltip: 'Add item',
                onPressed: () => _showAddItemDialog(),
                child: const Icon(Icons.add_box),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: TextField(
                  controller: _labelSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search labels…',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: _labelSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _labelSearchController.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(40)),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              Expanded(
                child: LabelListWidget(
                  labels: sortedLabels,
                  currentLabel: _currentLabel,
                  searchController: _labelSearchController,
                  onSelectLabel: _selectLabel,
                  onRenameLabel: _showRenameDialog,
                  onDeleteLabel: _deleteLabel,
                  sortType: _labelSortType,
                  onSortChanged: _onSortChanged,
                  inventoryService: service,
                ),
              ),
            ],
          ),
          Positioned(
            bottom: AppConstants.fabBottomMargin,
            right: AppConstants.fabRightMargin,
            child: FloatingActionButton(
              heroTag: 'add_label_mobile',
              tooltip: 'New label',
              onPressed: _showCreateLabelDialog,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.folder_open, size: 28, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Text(
            'No label selected',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a label or create one',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            'Pull down to refresh',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Label Name Bottom Sheet ─────────────────────────────────────

class _LabelNameSheet extends StatefulWidget {
  final String title;
  final String hint;
  final String submitLabel;
  final TextEditingController controller;
  final Future<bool> Function(String name) onSubmit;

  const _LabelNameSheet({
    required this.title,
    required this.hint,
    required this.submitLabel,
    required this.controller,
    required this.onSubmit,
  });

  @override
  State<_LabelNameSheet> createState() => _LabelNameSheetState();
}

class _LabelNameSheetState extends State<_LabelNameSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final name = widget.controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty');
      return;
    }
    if (name.length < 2) {
      setState(() => _error = 'Name must be at least 2 characters');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final ok = await widget.onSubmit(name);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
      } else {
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Error: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: widget.hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              errorText: _error,
            ),
            onSubmitted: (_) => _saving ? null : _submit(),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.submitLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}