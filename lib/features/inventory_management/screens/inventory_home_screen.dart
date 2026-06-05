import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/inventory_item.dart';
import '../bloc/inventory_bloc.dart';
import '../../company/bloc/company_bloc.dart';
import '../../inventory_selection/bloc/inventory_list_bloc.dart';
import '../widgets/add_item_sheet.dart';
import '../widgets/label_list_widget.dart';
import '../widgets/items_list_widget.dart';
import '../../search/screens/search_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../activity_log/screens/activity_log_screen.dart';
import '../../import/screens/bulk_import_screen.dart';
import '../../company/screens/inventory_members_screen.dart';
import '../../chat/screens/inventory_chat_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/models/user.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/permission_service.dart';

class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key});

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  final _itemSearchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  InventoryPermissions? _permissions;
  String? _lastInventoryId;
  bool _permissionsLoading = false;

  @override
  void initState() {
    super.initState();
    _itemSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPermissions();
    });
  }

  @override
  void dispose() {
    _itemSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    if (_permissionsLoading) return;
    _permissionsLoading = true;
    try {
      final inventoryState = context.read<InventoryBloc>().state;
      final inventoryId = inventoryState.inventoryId;
      if (inventoryId == null) {
        if (mounted) setState(() => _permissions = InventoryPermissions.fromRole('viewer'));
        _permissionsLoading = false;
        return;
      }
      if (AppConfig.useSupabase) {
        try {
          final permService = PermissionService();
          final perms = await permService.getInventoryPermissions(inventoryId);
          if (mounted) setState(() => _permissions = perms);
          _permissionsLoading = false;
          return;
        } catch (e) {
          debugPrint('⚠️ Failed to fetch inventory permissions: $e');
        }
      }
      if (mounted) {
        final companyState = context.read<CompanyBloc>().state;
        final companyRole = companyState.selectedCompany?['role']?.toString() ?? 'viewer';
        setState(() => _permissions = InventoryPermissions.fromRole(companyRole));
      }
    } catch (_) {
      if (mounted) setState(() => _permissions = InventoryPermissions.fromRole('viewer'));
    } finally {
      if (mounted) _permissionsLoading = false;
    }
  }

  bool get _canCreate => _permissions?.canCreate ?? false;
  bool get _canUpdate => _permissions?.canUpdate ?? false;
  bool get _canDelete => _permissions?.canDelete ?? false;
  bool get _canExport => _permissions?.canExport ?? true;
  bool get _canManageSettings => _permissions?.canManageSettings ?? false;
  bool get _canViewActivity => _permissions?.canViewActivity ?? true;
  bool get _canManageLabels => _permissions?.canManageLabels ?? false;
  bool get _canChat => _permissions?.canChat ?? true;

  void _selectLabel(String label) {
    context.read<InventoryBloc>().add(SelectLabel(label));
    _itemSearchController.clear();
  }

  void _showCreateLabelDialog() {
    if (!_canManageLabels && !_canCreate) {
      SnackBarUtils.show(context, message: 'You do not have permission to create labels', isError: true);
      return;
    }
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _LabelNameSheet(
        title: 'New Label',
        hint: 'Label name',
        submitLabel: 'Save',
        controller: controller,
        onSubmit: (name) async {
          final state = context.read<InventoryBloc>().state;
          if (state.labels.contains(name)) {
            SnackBarUtils.show(context, message: '"$name" already exists', isError: true);
            return false;
          }
          try {
            context.read<InventoryBloc>().add(CreateLabel(name));
            SnackBarUtils.success(context, '"$name" created');
            return true;
          } catch (e) {
            SnackBarUtils.error(context, 'Error creating label: $e');
            return false;
          }
        },
      ),
    );
  }

  void _showAddItemDialog({InventoryItem? existingItem}) {
    if (existingItem != null && !_canUpdate) {
      SnackBarUtils.show(context, message: 'You do not have permission to update items', isError: true);
      return;
    }
    if (existingItem == null && !_canCreate) {
      SnackBarUtils.show(context, message: 'You do not have permission to create items', isError: true);
      return;
    }
    final state = context.read<InventoryBloc>().state;
    if (state.selectedLabel == null) {
      SnackBarUtils.show(context, message: 'Select a label first');
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
    if (!_canUpdate) {
      SnackBarUtils.show(context, message: 'You do not have permission to update quantities', isError: true);
      return;
    }
    final newQuantity = (item.quantity + delta).clamp(0, InventoryItem.maxQuantity);
    if (newQuantity == item.quantity) return;
    context.read<InventoryBloc>().add(AdjustQuantity(item, delta));
  }

  Future<void> _deleteItem(InventoryItem item) async {
    if (!_canDelete) {
      SnackBarUtils.show(context, message: 'You do not have permission to delete items', isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "${item.displayName}" from ${item.label}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<InventoryBloc>().add(DeleteItem(item));
      SnackBarUtils.show(context, message: 'Removed "${item.displayName}"');
    }
  }

  void _openChat() {
    final state = context.read<InventoryBloc>().state;
    final companyState = context.read<CompanyBloc>().state;
    final companyId = companyState.selectedCompany?['id']?.toString() ?? '';
    final companyName = companyState.selectedCompany?['name']?.toString() ?? '';
    if (state.inventoryId != null && companyId.isNotEmpty && _canChat) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryChatScreen(inventoryId: state.inventoryId!, inventoryName: state.inventoryName ?? 'Inventory', companyId: companyId, companyName: companyName)));
    }
  }

  void _openMembers() {
    final state = context.read<InventoryBloc>().state;
    if (state.inventoryId == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryMembersScreen(inventoryId: state.inventoryId!, inventoryName: state.inventoryName ?? 'Inventory'))).then((_) { if (mounted) _loadPermissions(); });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        if (state.inventoryId != null && state.isInitialized && state.inventoryId != _lastInventoryId) {
          _lastInventoryId = state.inventoryId;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadPermissions(); });
        }
        if (state.isLoading && !state.isInitialized) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state.error != null && !state.isInitialized) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: () { if (state.inventoryId != null) context.read<InventoryBloc>().add(InitializeInventory(state.inventoryId!)); }, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ]),
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(state.inventoryName ?? 'Inventory', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            actions: [
              if (_canChat) IconButton(icon: const Icon(Icons.chat_outlined), tooltip: 'Chat', onPressed: _openChat),
              IconButton(icon: const Icon(Icons.people_outline), tooltip: 'Members', onPressed: _openMembers),
              if (_canViewActivity) IconButton(icon: const Icon(Icons.history), tooltip: 'Activity', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogScreen()))),
              IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
              if (_canExport) IconButton(icon: const Icon(Icons.assessment_outlined), tooltip: 'Reports', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()))),
              if (_canManageSettings) IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            ],
          ),
          drawer: _buildLabelDrawer(state, colorScheme),
          body: Column(
            children: [
              // Current label header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                child: Row(children: [
                  Icon(Icons.label_important, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.selectedLabel ?? 'Select a label',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: state.selectedLabel != null ? colorScheme.onSurface : Colors.grey),
                    ),
                  ),
                  if (state.selectedLabel != null && _canCreate)
                    FilledButton.icon(
                      onPressed: () => _showAddItemDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Item'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                ]),
              ),

              // Search bar
              if (state.selectedLabel != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: TextField(
                    controller: _itemSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search items in ${state.selectedLabel}...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _itemSearchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _itemSearchController.clear()) : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),

              // Items list or empty state
              Expanded(
                child: state.selectedLabel == null
                    ? _buildNoLabelSelected(colorScheme)
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
                        onRefresh: () async { if (state.selectedLabel != null) context.read<InventoryBloc>().add(LoadItems(state.selectedLabel!)); },
                      ),
              ),
            ],
          ),
          floatingActionButton: state.selectedLabel == null
              ? FloatingActionButton.extended(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.label),
                  label: const Text('Select Label'),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }

  Widget _buildLabelDrawer(InventoryState state, ColorScheme colorScheme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.inventory_2, color: colorScheme.primary, size: 24),
                    const SizedBox(width: 8),
                    Expanded(child: Text(state.inventoryName ?? 'Inventory', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: colorScheme.primary))),
                    if (_canCreate) IconButton(icon: const Icon(Icons.cloud_upload, size: 20), tooltip: 'Bulk Import', onPressed: () { Navigator.pop(context); _bulkImport(); }),
                  ]),
                  const SizedBox(height: 4),
                  Text('${state.labels.length} labels', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),

            // Labels list
            Expanded(
              child: state.labels.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.label_off, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No labels yet', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Create a label to start adding items', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                        const SizedBox(height: 16),
                        if (_canManageLabels || _canCreate)
                          OutlinedButton.icon(onPressed: () { Navigator.pop(context); _showCreateLabelDialog(); }, icon: const Icon(Icons.add, size: 16), label: const Text('Create Label')),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: state.labels.length,
                      itemBuilder: (_, index) {
                        final label = state.labels[index];
                        final isSelected = label == state.selectedLabel;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.2),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected ? colorScheme.primary : Colors.grey[200],
                            child: Icon(Icons.label, size: 16, color: isSelected ? colorScheme.onPrimary : Colors.grey[600]),
                          ),
                          title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () {
                            _selectLabel(label);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),

            // Footer with create button
            if (_canManageLabels || _canCreate)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)))),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () { Navigator.pop(context); _showCreateLabelDialog(); },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Label'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _bulkImport() {
    final state = context.read<InventoryBloc>().state;
    final inventoryId = state.inventoryId;
    if (inventoryId == null) return;
    if (!_canCreate) {
      SnackBarUtils.show(context, message: 'You do not have permission to import items', isError: true);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => BulkImportScreen(inventoryId: inventoryId, inventoryName: state.inventoryName ?? 'Inventory'))).then((_) {
      if (mounted) { final currentId = context.read<InventoryBloc>().state.inventoryId; if (currentId != null) context.read<InventoryBloc>().add(InitializeInventory(currentId)); }
    });
  }

  Widget _buildNoLabelSelected(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(color: colorScheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(30)),
              child: Icon(Icons.label_outline, size: 48, color: colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text('Select a Label', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('Open the drawer to choose a label\nor create a new one', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 14, height: 1.5)),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu),
              label: const Text('Open Labels'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ),
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

  const _LabelNameSheet({required this.title, required this.hint, required this.submitLabel, required this.controller, required this.onSubmit});

  @override
  State<_LabelNameSheet> createState() => _LabelNameSheetState();
}

class _LabelNameSheetState extends State<_LabelNameSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final name = widget.controller.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Name cannot be empty'); return; }
    if (name.length < 2) { setState(() => _error = 'Name must be at least 2 characters'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final ok = await widget.onSubmit(name);
      if (!mounted) return;
      if (ok) { Navigator.pop(context); } else { setState(() => _saving = false); }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 28, left: 20, right: 20, top: 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 18),
        Text(widget.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        TextField(
          controller: widget.controller, autofocus: true, textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: widget.hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, errorText: _error),
          onSubmitted: (_) => _saving ? null : _submit(),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))), child: const Text('Cancel'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: _saving ? null : _submit, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))), child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.submitLabel, style: const TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]),
    );
  }
}