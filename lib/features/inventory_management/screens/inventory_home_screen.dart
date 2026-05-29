import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/inventory_item.dart';
import '../bloc/inventory_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../inventory_selection/bloc/inventory_list_bloc.dart';
import '../widgets/add_item_sheet.dart';
import '../widgets/label_list_widget.dart';
import '../widgets/items_list_widget.dart';
import '../../search/screens/search_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../activity_log/screens/activity_log_screen.dart';
import '../../import/screens/bulk_import_screen.dart';
import '../../company/screens/company_settings_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/models/user.dart';

class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key});

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  final _labelSearchController = TextEditingController();
  final _itemSearchController = TextEditingController();
  bool _showItemsView = false;
  InventoryPermissions? _permissions;

  @override
  void initState() {
    super.initState();
    _labelSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _itemSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPermissions();
    });
  }

  @override
  void dispose() {
    _labelSearchController.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    try {
      final authState = context.read<AuthBloc>().state;
      final user = authState.user;

      if (user?.inventoryPermissions != null) {
        setState(() => _permissions = user!.inventoryPermissions);
      } else {
        final role = user?.role ?? UserRole.viewer;
        setState(() => _permissions = InventoryPermissions(
              canCreate: role == UserRole.owner ||
                  role == UserRole.admin ||
                  role == UserRole.dataOperator,
              canUpdate: role == UserRole.owner ||
                  role == UserRole.admin ||
                  role == UserRole.dataOperator,
              canDelete: role == UserRole.owner || role == UserRole.admin,
              canExport: true,
              canViewActivity: true,
              canManageSettings: role == UserRole.owner || role == UserRole.admin,
              role: role.name,
            ));
      }
    } catch (_) {
      setState(() => _permissions = const InventoryPermissions(
            canCreate: true,
            canUpdate: true,
            canDelete: false,
            canExport: true,
            canViewActivity: true,
            canManageSettings: false,
            role: 'data_operator',
          ));
    }
  }

  bool get _canCreate => _permissions?.canCreate ?? true;
  bool get _canUpdate => _permissions?.canUpdate ?? true;
  bool get _canDelete => _permissions?.canDelete ?? false;
  bool get _canExport => _permissions?.canExport ?? true;
  bool get _canManageSettings => _permissions?.canManageSettings ?? false;

  void _selectLabel(String label) {
    context.read<InventoryBloc>().add(SelectLabel(label));
    setState(() {
      _showItemsView = true;
      _itemSearchController.clear();
    });
  }

  void _bulkImport() {
    final state = context.read<InventoryBloc>().state;
    final inventoryId = state.inventoryId;
    if (inventoryId == null) {
      _showSnackBar('No inventory selected');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => BulkImportScreen(
                inventoryId: inventoryId,
                inventoryName: state.inventoryName ?? 'Inventory',
              )),
    ).then((_) {
      if (mounted) {
        final currentId = context.read<InventoryBloc>().state.inventoryId;
        if (currentId != null) {
          context.read<InventoryBloc>().add(InitializeInventory(currentId));
        }
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
          final state = context.read<InventoryBloc>().state;
          if (state.labels.contains(name)) {
            _showSnackBar('"$name" already exists', isError: true);
            return false;
          }
          try {
            context.read<InventoryBloc>().add(CreateLabel(name));
            _labelSearchController.clear();
            _showSnackBar('✅ "$name" created');
            return true;
          } catch (e) {
            _showSnackBar('Error creating label: $e', isError: true);
            return false;
          }
        },
      ),
    );
  }

  void _showAddItemDialog({InventoryItem? existingItem}) {
    final state = context.read<InventoryBloc>().state;
    if (state.selectedLabel == null) {
      _showSnackBar('Select a label first');
      return;
    }

    AddItemSheet.show(
      context,
      label: state.selectedLabel!,
      settings: state.settings,
      existingItem: existingItem,
      inventoryName: state.inventoryName,
      inventoryId: state.inventoryId,
      onSave: (item) async {
        context.read<InventoryBloc>().add(SaveItem(item));
      },
    );
  }

  void _adjustQuantity(InventoryItem item, int delta) {
    final newQuantity = (item.quantity + delta).clamp(0, InventoryItem.maxQuantity);
    if (newQuantity == item.quantity) return;
    context.read<InventoryBloc>().add(AdjustQuantity(item, delta));
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "${item.displayName}" from ${item.label}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      context.read<InventoryBloc>().add(DeleteItem(item));
      _showSnackBar('Removed "${item.displayName}"');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: AppConstants.snackbarDuration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
        margin: const EdgeInsets.all(20),
      ));
  }

  /// ✅ NEW: Refresh items for the currently selected label
  Future<void> _refreshItems() async {
    final state = context.read<InventoryBloc>().state;
    if (state.selectedLabel != null) {
      context.read<InventoryBloc>().add(LoadItems(state.selectedLabel!));
    }
  }

  /// ✅ NEW: Refresh labels list
  Future<void> _refreshLabels() async {
    context.read<InventoryBloc>().add(const LoadLabels());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < AppConstants.mobileBreakpoint;

    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        if (_showItemsView && state.selectedLabel == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _showItemsView = false);
          });
        }

        if (state.isLoading && !state.isInitialized) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (state.error != null && !state.isInitialized) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(state.error!, textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red[700])),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        final currentId = state.inventoryId;
                        if (currentId != null) {
                          context.read<InventoryBloc>().add(InitializeInventory(currentId));
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

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
                    _showItemsView && state.selectedLabel != null
                        ? state.selectedLabel!
                        : state.inventoryName ?? 'Inventory',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  if (_showItemsView && state.selectedLabel != null)
                    Text(state.inventoryName ?? '',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary)),
                ],
              ),
              actions: [
                _buildConnectivityIndicator(context),
                if (!isMobile || !_showItemsView) ...[
                  IconButton(
                    tooltip: 'Members & Permissions',
                    icon: const Icon(Icons.people),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompanySettingsScreen(
                            inventoryId: state.inventoryId ?? 'default',
                            inventoryName: state.inventoryName ?? 'Inventory',
                          ),
                        )),
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
                        MaterialPageRoute(
                            builder: (_) => const ActivityLogScreen())),
                  ),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SearchScreen())),
                  ),
                  IconButton(
                    tooltip: 'Reports',
                    icon: const Icon(Icons.assessment),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReportsScreen())),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen())),
                  ),
                ],
              ],
            ),
            body: SafeArea(
              child: isMobile
                  ? _buildMobileLayout(state)
                  : _buildDesktopLayout(state, width),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectivityIndicator(BuildContext context) {
    final listState = context.watch<InventoryListBloc>().state;

    if (listState.isOffline) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text('Offline',
                  style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    if (listState.isCacheOnly) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text('Cached',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDesktopLayout(InventoryState state, double width) {
    final sidebarWidth = (width * AppConstants.sidebarWidthRatio).clamp(250.0, 400.0);

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
                                onPressed: () => _labelSearchController.clear())
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(40)),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshLabels,
                      child: LabelListWidget(
                        labels: state.labels,
                        currentLabel: state.selectedLabel,
                        searchController: _labelSearchController,
                        onSelectLabel: _selectLabel,
                        onRenameLabel: (oldName) => _showRenameDialog(oldName),
                        onDeleteLabel: (label) => _deleteLabel(label),
                        sortType: state.sortType,
                        onSortChanged: (sortType) {
                          context.read<InventoryBloc>().add(SetLabelSortType(sortType));
                        },
                        inventoryService: InjectionContainer.inventoryService,
                      ),
                    ),
                  ),
                ],
              ),
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
        const VerticalDivider(width: 1),
        Expanded(
          child: Stack(
            children: [
              state.selectedLabel == null
                  ? _buildEmptyState()
                  : ItemsListWidget(
                      items: state.currentItems,
                      label: state.selectedLabel!,
                      searchController: _itemSearchController,
                      canCreate: _canCreate,
                      canUpdate: _canUpdate,
                      canDelete: _canDelete,
                      onAdjustQuantity: _adjustQuantity,
                      onDeleteItem: _deleteItem,
                      onAddItem: () => _showAddItemDialog(),
                      onEditItem: (item) => _showAddItemDialog(existingItem: item),
                      onRefresh: _refreshItems,
                    ),
              if (state.selectedLabel != null)
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
      ],
    );
  }

  Widget _buildMobileLayout(InventoryState state) {
    if (_showItemsView && state.selectedLabel != null) {
      return Stack(
        children: [
          ItemsListWidget(
            items: state.currentItems,
            label: state.selectedLabel!,
            searchController: _itemSearchController,
            canCreate: _canCreate,
            canUpdate: _canUpdate,
            canDelete: _canDelete,
            onAdjustQuantity: _adjustQuantity,
            onDeleteItem: _deleteItem,
            onAddItem: () => _showAddItemDialog(),
            onEditItem: (item) => _showAddItemDialog(existingItem: item),
            onRefresh: _refreshItems,
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
                          onPressed: () => _labelSearchController.clear())
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(40)),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshLabels,
                child: LabelListWidget(
                  labels: state.labels,
                  currentLabel: state.selectedLabel,
                  searchController: _labelSearchController,
                  onSelectLabel: _selectLabel,
                  onRenameLabel: (oldName) => _showRenameDialog(oldName),
                  onDeleteLabel: (label) => _deleteLabel(label),
                  sortType: state.sortType,
                  onSortChanged: (sortType) {
                    context.read<InventoryBloc>().add(SetLabelSortType(sortType));
                  },
                  inventoryService: InjectionContainer.inventoryService,
                ),
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
          final state = context.read<InventoryBloc>().state;
          if (state.labels.contains(newName)) {
            _showSnackBar('"$newName" already exists', isError: true);
            return false;
          }
          try {
            context.read<InventoryBloc>().add(RenameLabel(oldLabel, newName));
            _labelSearchController.clear();
            _showSnackBar('Renamed to "$newName"');
            return true;
          } catch (e) {
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final bloc = context.read<InventoryBloc>();
              Navigator.pop(ctx);
              bloc.add(DeleteLabel(label));
              _labelSearchController.clear();
              setState(() => _showItemsView = false);
              _showSnackBar('🗑️ "$label" deleted');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: RefreshIndicator(
        onRefresh: _refreshItems,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.folder_open, size: 28, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Text('No label selected',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Choose a label or create one',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    const SizedBox(height: 16),
                    Text('Pull down to refresh',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
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
          _error = 'Error: $e';
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
          top: 20),
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
                      borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          Text(widget.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
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
                errorText: _error),
            onSubmitted: (_) => _saving ? null : _submit(),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40))),
                    child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40))),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(widget.submitLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700)))),
          ]),
        ],
      ),
    );
  }
}