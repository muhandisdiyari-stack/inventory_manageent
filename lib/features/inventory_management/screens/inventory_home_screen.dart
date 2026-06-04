import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/inventory_item.dart';
import '../bloc/inventory_bloc.dart';
import '../../company/bloc/company_bloc.dart';
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
import '../../../core/services/auth_service.dart';
import '../../../core/database/supabase/supabase_client.dart';

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
  String? _lastInventoryId;
  bool _permissionsLoading = false;

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
    if (_permissionsLoading) return;
    _permissionsLoading = true;
    try {
      final inventoryBloc = context.read<InventoryBloc>();
      final inventoryState = inventoryBloc.state;
      final inventoryId = inventoryState.inventoryId;

      if (inventoryId == null) {
        if (mounted) {
          setState(() => _permissions = InventoryPermissions.fromRole('viewer'));
        }
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
        final companyRole =
            companyState.selectedCompany?['role']?.toString() ?? 'viewer';
        setState(
            () => _permissions = InventoryPermissions.fromRole(companyRole));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _permissions = InventoryPermissions.fromRole('viewer'));
      }
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
  bool get _canChat => _permissions?.canChat ?? true;
  bool get _isOwnerOrAdmin =>
      _permissions?.role == 'owner' || _permissions?.role == 'admin';

  void _selectLabel(String label) {
    context.read<InventoryBloc>().add(SelectLabel(label));
    setState(() {
      _showItemsView = true;
      _itemSearchController.clear();
    });
  }

  void _openChat() {
    final state = context.read<InventoryBloc>().state;
    final companyState = context.read<CompanyBloc>().state;
    final companyId = companyState.selectedCompany?['id']?.toString() ?? '';
    final companyName =
        companyState.selectedCompany?['name']?.toString() ?? '';

    if (state.inventoryId != null && companyId.isNotEmpty && _canChat) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InventoryChatScreen(
            inventoryId: state.inventoryId!,
            inventoryName: state.inventoryName ?? 'Inventory',
            companyId: companyId,
            companyName: companyName,
          ),
        ),
      );
    } else if (!_canChat) {
      SnackBarUtils.show(context,
          message: 'You do not have permission to access chat', isError: true);
    }
  }

  void _openMembers() {
    final state = context.read<InventoryBloc>().state;
    if (state.inventoryId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryMembersScreen(
          inventoryId: state.inventoryId!,
          inventoryName: state.inventoryName ?? 'Inventory',
        ),
      ),
    ).then((_) {
      if (mounted) _loadPermissions();
    });
  }

  void _openBulkImport() {
    final state = context.read<InventoryBloc>().state;
    if (state.inventoryId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BulkImportScreen(
          inventoryId: state.inventoryId!,
          inventoryName: state.inventoryName ?? 'Inventory',
        ),
      ),
    ).then((_) {
      if (mounted) {
        context.read<InventoryBloc>().add(const LoadLabels());
        if (state.selectedLabel != null) {
          context.read<InventoryBloc>().add(LoadItems(state.selectedLabel!));
        }
      }
    });
  }

  void _openActivityLog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportsScreen()),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    ).then((_) {
      if (mounted) _loadPermissions();
    });
  }

  Future<void> _deleteInventory() async {
    final state = context.read<InventoryBloc>().state;
    if (state.inventoryId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Inventory'),
        content: Text(
            'Delete "${state.inventoryName}"?\n\nThis cannot be undone. All items and labels will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final authService =
          AuthService(supabaseClient: SupabaseClientService());
      final result = await authService.deleteInventory(state.inventoryId!);
      if (!mounted) return;
      if (result) {
        SnackBarUtils.success(context, 'Inventory deleted');
        if (mounted) Navigator.pop(context);
      } else {
        SnackBarUtils.error(context, 'Failed to delete inventory');
      }
    } catch (e) {
      if (mounted) SnackBarUtils.error(context, 'Error: $e');
    }
  }

void _addItem() {
    final currentState = context.read<InventoryBloc>().state;
    if (currentState.selectedLabel == null) return;
    AddItemSheet.show(
      context,
      label: currentState.selectedLabel!,
      settings: currentState.settings,
      inventoryName: currentState.inventoryName,
      inventoryId: currentState.inventoryId,
      onSave: (item) async {
        context.read<InventoryBloc>().add(SaveItem(item));
      },
    );
  }

  void _editItem(InventoryItem item) {
    final currentState = context.read<InventoryBloc>().state;
    AddItemSheet.show(
      context,
      label: item.label,
      settings: currentState.settings,
      existingItem: item,
      inventoryName: currentState.inventoryName,
      inventoryId: currentState.inventoryId,
      onSave: (updatedItem) async {
        context.read<InventoryBloc>().add(SaveItem(updatedItem));
      },
    );
  }

  void _deleteItem(InventoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${item.displayName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<InventoryBloc>().add(DeleteItem(item));
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  InventoryState get state => context.read<InventoryBloc>().state;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < AppConstants.mobileBreakpoint;

    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        if (state.inventoryId != null &&
            state.isInitialized &&
            state.inventoryId != _lastInventoryId) {
          _lastInventoryId = state.inventoryId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadPermissions();
          });
        }

        if (state.isLoading && !state.isInitialized) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  if (_showItemsView && state.selectedLabel != null)
                    Text(
                      state.inventoryName ?? '',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                ],
              ),
              actions: [
                if (!isMobile || !_showItemsView) ...[
                  if (_canChat)
                    IconButton(
                      tooltip: 'Chat',
                      icon: const Icon(Icons.chat),
                      onPressed: _openChat,
                    ),
                  IconButton(
                    tooltip: 'Members',
                    icon: const Icon(Icons.people),
                    onPressed: _openMembers,
                  ),
                  if (_canCreate)
                    IconButton(
                      tooltip: 'Bulk Import',
                      icon: const Icon(Icons.cloud_upload),
                      onPressed: _openBulkImport,
                    ),
                  if (_canViewActivity)
                    IconButton(
                      tooltip: 'Activity Log',
                      icon: const Icon(Icons.history),
                      onPressed: _openActivityLog,
                    ),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: _openSearch,
                  ),
                  if (_canExport)
                    IconButton(
                      tooltip: 'Reports',
                      icon: const Icon(Icons.assessment),
                      onPressed: _openReports,
                    ),
                  if (_canManageSettings)
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings),
                      onPressed: _openSettings,
                    ),
                  if (_isOwnerOrAdmin)
                    IconButton(
                      tooltip: 'Delete Inventory',
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      onPressed: _deleteInventory,
                    ),
                ],
              ],
            ),
            body: SafeArea(
              child: isMobile
                  ? _buildMobileLayout(state)
                  : _buildDesktopLayout(state, width),
            ),
            floatingActionButton: _canCreate && state.selectedLabel != null
                ? FloatingActionButton.extended(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Item'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(InventoryState state, double width) {
    final sidebarWidth =
        (width * AppConstants.sidebarWidthRatio).clamp(250.0, 400.0);
    return Row(
      children: [
        SizedBox(
          width: sidebarWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: TextField(
                  controller: _labelSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search labels…',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(40)),
                    filled: true,
                  ),
                ),
              ),
              Expanded(
                child: LabelListWidget(
                  labels: state.labels,
                  currentLabel: state.selectedLabel,
                  searchController: _labelSearchController,
                  onSelectLabel: _selectLabel,
                  onRenameLabel: (oldName) {
                    _showRenameDialog(oldName);
                  },
                  onDeleteLabel: (name) {
                    _showDeleteLabelDialog(name);
                  },
                  sortType: state.sortType,
                  onSortChanged: (sortType) {
                    context
                        .read<InventoryBloc>()
                        .add(SetLabelSortType(sortType));
                  },
                  inventoryService: InjectionContainer.inventoryService,
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: state.selectedLabel == null
              ? _buildEmptyState()
              : ItemsListWidget(
                  items: state.currentItems,
                  label: state.selectedLabel!,
                  searchController: _itemSearchController,
                  canCreate: _canCreate,
                  canUpdate: _canUpdate,
                  canDelete: _canDelete,
                  onAdjustQuantity: (item, delta) {
                    context
                        .read<InventoryBloc>()
                        .add(AdjustQuantity(item, delta));
                  },
                  onDeleteItem: _deleteItem,
                  onAddItem: _addItem,
                  onEditItem: _editItem,
                  onRefresh: () async {
                    if (state.selectedLabel != null) {
                      context
                          .read<InventoryBloc>()
                          .add(LoadItems(state.selectedLabel!));
                    }
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(InventoryState state) {
    if (_showItemsView && state.selectedLabel != null) {
      return ItemsListWidget(
        items: state.currentItems,
        label: state.selectedLabel!,
        searchController: _itemSearchController,
        canCreate: _canCreate,
        canUpdate: _canUpdate,
        canDelete: _canDelete,
        onAdjustQuantity: (item, delta) {
          context.read<InventoryBloc>().add(AdjustQuantity(item, delta));
        },
        onDeleteItem: _deleteItem,
        onAddItem: _addItem,
        onEditItem: _editItem,
        onRefresh: () async {
          if (state.selectedLabel != null) {
            context.read<InventoryBloc>().add(LoadItems(state.selectedLabel!));
          }
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: TextField(
            controller: _labelSearchController,
            decoration: InputDecoration(
              hintText: 'Search labels…',
              prefixIcon: const Icon(Icons.search, size: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(40)),
              filled: true,
            ),
          ),
        ),
        Expanded(
          child: LabelListWidget(
            labels: state.labels,
            currentLabel: state.selectedLabel,
            searchController: _labelSearchController,
            onSelectLabel: _selectLabel,
            onRenameLabel: (oldName) {
              _showRenameDialog(oldName);
            },
            onDeleteLabel: (name) {
              _showDeleteLabelDialog(name);
            },
            sortType: state.sortType,
            onSortChanged: (sortType) {
              context.read<InventoryBloc>().add(SetLabelSortType(sortType));
            },
            inventoryService: InjectionContainer.inventoryService,
          ),
        ),
      ],
    );
  }

  void _showRenameDialog(String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'New name',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                Navigator.pop(ctx);
                context
                    .read<InventoryBloc>()
                    .add(RenameLabel(oldName, newName));
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteLabelDialog(String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Label'),
        content: Text(
            'Delete "$name" and all its items?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<InventoryBloc>().add(DeleteLabel(name));
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
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
          Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No label selected',
              style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}