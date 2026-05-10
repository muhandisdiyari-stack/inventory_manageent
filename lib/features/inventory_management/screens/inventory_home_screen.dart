import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../widgets/add_item_sheet.dart';
import '../widgets/label_list_widget.dart';
import '../widgets/items_list_widget.dart';
import '../../search/screens/search_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/constants/app_constants.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<InventoryProvider>();
      provider.initializeCurrentInventory();
      if (provider.hasLabels && _currentLabel == null) {
        setState(() {
          _currentLabel = provider.labels.first;
        });
      }
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

  Future<void> _refreshInventory() async {
    final provider = context.read<InventoryProvider>();
    await provider.initializeCurrentInventory();

    if (!mounted) return;

    setState(() {
      if (_currentLabel != null && !provider.hasLabel(_currentLabel!)) {
        _currentLabel =
            provider.hasLabels ? provider.labels.first : null;
      }
    });
  }

  void _selectLabel(String label) {
    setState(() {
      _currentLabel = label;
      _showItemsView = true;
      _itemSearchController.clear();
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
            _showSnack('"$name" already exists');
            return false;
          }
          await provider.createLabel(name);

          if (!mounted) return false;

          setState(() => _currentLabel = name);
          _labelSearchController.clear();
          _showSnack('✅ "$name" created');
          return true;
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
            _showSnack('"$newName" already exists');
            return false;
          }
          await provider.renameLabel(oldLabel, newName);

          if (!mounted) return false;

          setState(() {
            if (_currentLabel == oldLabel) _currentLabel = newName;
          });
          _labelSearchController.clear();
          _showSnack('Renamed to "$newName"');
          return true;
        },
      ),
    );
  }

  void _deleteLabel(String label) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Label'),
        content: Text('Delete "$label" and all its items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final provider = context.read<InventoryProvider>();
              await provider.deleteLabel(label);

              if (!mounted) return;

              setState(() {
                if (_currentLabel == label) {
                  _currentLabel =
                      provider.hasLabels ? provider.labels.first : null;
                }
              });
              _labelSearchController.clear();
              if (ctx.mounted) Navigator.pop(ctx);
              _showSnack('🗑️ "$label" deleted');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Shows the add/edit item dialog.
  ///
  /// For both new items AND edits, validation is now enforced through
  /// AddItemSheet's FormState, which checks all required fields before
  /// allowing save.
  void _showAddItemDialog({InventoryItem? existingItem}) {
    if (_currentLabel == null) {
      _showSnack('Select a label first');
      return;
    }

    final provider = context.read<InventoryProvider>();

    AddItemSheet.show(
      context,
      label: _currentLabel!,
      settings: provider.currentSettings,
      existingItem: existingItem,
      onSave: (item) async {
        if (provider.currentInventoryId == null) {
          _showSnack('No inventory selected — please select one first');
          return;
        }
        await provider.saveItem(item);
        if (!mounted) return;
        setState(() {});
      },
    );

    // For edits, refresh the list after the sheet closes
    if (existingItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _editItem(InventoryItem item) {
    _showAddItemDialog(existingItem: item);
  }

  Future<void> _adjustQuantity(InventoryItem item, int delta) async {
    try {
      item.quantity =
          (item.quantity + delta).clamp(0, InventoryItem.maxQuantity);
      item.modified = DateTime.now();
      await item.save();

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e');
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final itemName = item.displayName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content:
            Text('Remove "$itemName" from ${_currentLabel ?? "label"}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      try {
        await item.delete();

        if (!mounted) return;

        setState(() {});
        _showSnack('Removed "$itemName"');
      } catch (e) {
        if (!mounted) return;
        _showSnack('Error: $e');
      }
    }
  }

  void _showSnack(String message,
      {Duration duration = AppConstants.snackbarDuration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          margin: const EdgeInsets.all(20),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < AppConstants.mobileBreakpoint;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (_showItemsView && _currentLabel != null)
              Text(
                provider.currentInventoryName ?? '',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary),
              ),
          ],
        ),
        actions: [
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
      ),
      body: RefreshIndicator(
        onRefresh: _refreshInventory,
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: Theme.of(context).colorScheme.surface,
        displacement: 60,
        child: isMobile
            ? _buildMobileLayout(provider)
            : _buildDesktopLayout(provider, width),
      ),
    );
  }

  Widget _buildDesktopLayout(InventoryProvider provider, double width) {
    final sidebarWidth = width * 0.30;
    return Row(
      children: [
        SizedBox(
          width: sidebarWidth,
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
                                onPressed: () =>
                                    _labelSearchController.clear(),
                              )
                            : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(40)),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LabelListWidget(
                      labels: provider.labels,
                      currentLabel: _currentLabel,
                      searchController: _labelSearchController,
                      onSelectLabel: _selectLabel,
                      onRenameLabel: _showRenameDialog,
                      onDeleteLabel: _deleteLabel,
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton(
                  heroTag: 'add_label',
                  tooltip: 'New label',
                  onPressed: _showCreateLabelDialog,
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
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
                    heroTag: 'add_item',
                    tooltip: 'Add item',
                    onPressed: () => _showAddItemDialog(),
                    child: const Icon(Icons.add_box),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(InventoryProvider provider) {
    if (_showItemsView && _currentLabel != null) {
      return Stack(
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
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              heroTag: 'add_item_mobile',
              tooltip: 'Add item',
              onPressed: () => _showAddItemDialog(),
              child: const Icon(Icons.add_box),
            ),
          ),
        ],
      );
    }

    return Stack(
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(40)),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                ),
              ),
            ),
            Expanded(
              child: LabelListWidget(
                labels: provider.labels,
                currentLabel: _currentLabel,
                searchController: _labelSearchController,
                onSelectLabel: _selectLabel,
                onRenameLabel: _showRenameDialog,
                onDeleteLabel: _deleteLabel,
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton(
            heroTag: 'add_label_mobile',
            tooltip: 'New label',
            onPressed: _showCreateLabelDialog,
            child: const Icon(Icons.add),
          ),
        ),
      ],
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
            child: const Icon(Icons.folder_open,
                size: 28, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Text(
            'No label selected',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

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

  Future<void> _submit() async {
    final name = widget.controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final ok = await widget.onSubmit(name);
      if (!mounted) return;
      if (ok) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
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
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: widget.hint,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              filled: true,
            ),
            onSubmitted: (_) => _saving ? null : _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                      : Text(widget.submitLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}