import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../inventory_management/bloc/inventory_bloc.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_selection/bloc/inventory_list_bloc.dart';
import '../../inventory_management/screens/inventory_home_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/models/user.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _isServerSearch = true; // Prefer server search over local
  InventoryPermissions? _permissions;

  // Server search results (RLS-enforced)
  List<Map<String, dynamic>> _serverResults = [];

  // Local search results (fallback)
  List<Map<String, dynamic>> get _localResults {
    final state = context.read<InventoryBloc>().state;
    return state.searchResults;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _loadPermissions();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _loadPermissions() {
    try {
      final user = context.read<AuthBloc>().state.user;
      _permissions = user?.inventoryPermissions ??
          InventoryPermissions.fromRole(user?.role.name ?? 'viewer');
    } catch (_) {
      _permissions = const InventoryPermissions();
    }
    setState(() {});
  }

  bool get _canUpdate => _permissions?.canUpdate ?? false;

  void _performSearch(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _serverResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      if (_isServerSearch) {
        _performServerSearch(query.trim());
      } else {
        _performLocalSearch(query.trim());
      }
    });
  }

  /// Performs a server-side search using Supabase RLS.
  /// The RLS policies ensure users only see items from inventories they are members of.
  Future<void> _performServerSearch(String query) async {
    try {
      final client = Supabase.instance.client;

      // Search across all items the user has access to (RLS-enforced)
      // Uses ilike for case-insensitive matching across multiple fields
      final data = await client
          .from('inventory_items')
          .select('*, inventories(name)')
          .or(
            'name.ilike.%$query%,'
            'code.ilike.%$query%,'
            'barcode.ilike.%$query%,'
            'size.ilike.%$query%,'
            'color.ilike.%$query%,'
            'material.ilike.%$query%',
          )
          .eq('is_deleted', false)
          .order('updated_at', ascending: false)
          .limit(50);

      if (!mounted) return;

      final results = <Map<String, dynamic>>[];

      for (final row in data) {
        final itemData = Map<String, dynamic>.from(row);
        final inventoryName =
            itemData['inventories']?['name']?.toString() ?? 'Unknown';

        // Build InventoryItem from server data
        final item = _buildItemFromServerData(itemData);

        results.add({
          'item': item,
          'inventoryId': itemData['inventory_id']?.toString() ?? '',
          'inventoryName': inventoryName,
        });
      }

      setState(() {
        _serverResults = results;
        _isSearching = false;
        _hasSearched = true;
      });
    } catch (e) {
      debugPrint('⚠️ Server search failed, falling back to local: $e');

      // Fall back to local search
      if (mounted) {
        _performLocalSearch(query);
      }
    }
  }

  /// Builds an InventoryItem from Supabase server data.
  InventoryItem _buildItemFromServerData(Map<String, dynamic> data) {
    final customFields = <String, String>{};
    final rawCustom = data['custom_fields'];
    if (rawCustom is Map) {
      for (final entry in rawCustom.entries) {
        customFields[entry.key.toString()] = entry.value.toString();
      }
    }

    final item = InventoryItem(
      id: data['id']?.toString(),
      name: data['name']?.toString() ?? '',
      code: data['code']?.toString() ?? '',
      barcode: data['barcode']?.toString() ?? '',
      color: data['color']?.toString() ?? '',
      material: data['material']?.toString() ?? '',
      size: data['size']?.toString() ?? '',
      quantity: data['quantity'] as int? ?? 0,
      label: data['label']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
      customFields: customFields,
      productionDate: data['production_date'] != null
          ? DateTime.tryParse(data['production_date'] as String)
          : null,
      expireDate: data['expire_date'] != null
          ? DateTime.tryParse(data['expire_date'] as String)
          : null,
      createdAt: data['created_at'] != null
          ? DateTime.parse(data['created_at'] as String)
          : DateTime.now(),
      modified: data['updated_at'] != null
          ? DateTime.parse(data['updated_at'] as String)
          : DateTime.now(),
    );

    item.supabaseId = data['id']?.toString();
    item.createdBy = data['created_by']?.toString();
    item.createdByName = data['created_by_name']?.toString();
    item.updatedBy = data['updated_by']?.toString();
    item.updatedByName = data['updated_by_name']?.toString();
    item.rowVersion = data['row_version'] as int? ?? 1;
    item.companyId = data['company_id']?.toString();
    item.inventoryId = data['inventory_id']?.toString();

    return item;
  }

  /// Fallback local search using Hive cache.
  void _performLocalSearch(String query) {
    if (!mounted) return;
    context.read<InventoryBloc>().add(SearchItems(query.trim()));
    setState(() {
      _isSearching = false;
      _hasSearched = true;
    });
  }

  void _editItem(InventoryItem item) async {
    if (!_canUpdate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to edit items'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _SimpleEditSheet(item: item),
    );

    if (result != null && mounted) {
      _performSearch(_searchController.text);
    }
  }

  void _adjustQuantity(InventoryItem item, int delta) {
    if (!_canUpdate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to update quantities'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Perform optimistic update
    final newQuantity =
        (item.quantity + delta).clamp(0, InventoryItem.maxQuantity);
    if (newQuantity == item.quantity) return;

    item.quantity = newQuantity;
    item.modified = DateTime.now();
    context.read<InventoryBloc>().add(AdjustQuantity(item, delta));
  }

  void _navigateToInventory(String inventoryId) {
    context.read<InventoryListBloc>().add(SelectInventory(inventoryId));
    context.read<InventoryBloc>().add(InitializeInventory(inventoryId));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InventoryHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search across all inventories...',
            border: InputBorder.none,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Toggle search mode (server vs local)
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _isServerSearch
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      size: 18,
                      color: _isServerSearch
                          ? Theme.of(context).colorScheme.primary
                          : Colors.orange,
                    ),
                    tooltip: _isServerSearch
                        ? 'Searching server (tap for local)'
                        : 'Searching local cache (tap for server)',
                    onPressed: () {
                      setState(() => _isServerSearch = !_isServerSearch);
                      if (_searchController.text.isNotEmpty) {
                        _performSearch(_searchController.text);
                      }
                    },
                  ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _performSearch('');
                    },
                  ),
                const Icon(Icons.search, size: 20),
              ],
            ),
          ),
          onChanged: _performSearch,
          onSubmitted: _performSearch,
        ),
      ),
      body: BlocBuilder<InventoryBloc, InventoryState>(
        builder: (context, state) {
          if (_isSearching) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Searching...'),
                  SizedBox(height: 8),
                  Text(
                    'Checking across all your inventories',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          if (!_hasSearched && _searchController.text.isEmpty) {
            return _buildInitialState();
          }

          // Prefer server results if available
          final displayResults =
              _serverResults.isNotEmpty ? _serverResults : _localResults;

          if (displayResults.isEmpty && _hasSearched) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No results found',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'Try a different search term or check spelling',
                    style: TextStyle(
                        color: Colors.grey[400], fontSize: 13),
                  ),
                  if (!_isServerSearch) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _isServerSearch = true);
                        _performSearch(_searchController.text);
                      },
                      icon: const Icon(Icons.cloud, size: 16),
                      label: const Text('Try searching online'),
                    ),
                  ],
                ],
              ),
            );
          }

          return _buildResults(displayResults);
        },
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Search Across All Inventories',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Search by name, code, barcode, size, color, or material',
                style: TextStyle(color: Colors.grey[500]),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'name',
                'code',
                'barcode',
                'size',
                'color',
                'material',
                'note'
              ]
                  .map((f) => Chip(
                      label: Text(f,
                          style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact))
                  .toList(),
            ),
            const SizedBox(height: 32),
            // Server/local indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isServerSearch
                    ? Colors.blue.withValues(alpha: 0.05)
                    : Colors.orange.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isServerSearch
                      ? Colors.blue.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isServerSearch ? Icons.cloud : Icons.cloud_off,
                    size: 16,
                    color: _isServerSearch ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isServerSearch
                        ? 'Searching across all your inventories (online)'
                        : 'Searching local cache only',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isServerSearch ? Colors.blue : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<Map<String, dynamic>> results) {
    // Group results by inventory
    final groupedResults = <String, List<Map<String, dynamic>>>{};
    for (var result in results) {
      final inventoryName =
          (result['inventoryName'] as String?) ?? 'Unknown';
      groupedResults.putIfAbsent(inventoryName, () => []).add(result);
    }

    return Column(
      children: [
        // Results header
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          child: Row(children: [
            Icon(Icons.search,
                size: 16,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Found ${results.length} ${results.length == 1 ? 'item' : 'items'} in ${groupedResults.length} ${groupedResults.length == 1 ? 'inventory' : 'inventories'}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary)),
            ),
            if (!_isServerSearch)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Local',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groupedResults.length,
            itemBuilder: (context, index) {
              final inventoryName =
                  groupedResults.keys.elementAt(index);
              final items = groupedResults[inventoryName]!;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius:
                                  BorderRadius.circular(20)),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                                const SizedBox(width: 8),
                                Text(inventoryName,
                                    style: TextStyle(
                                        fontWeight:
                                            FontWeight.w700,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize: 15)),
                              ]),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            final inventoryId = items
                                .first['inventoryId'] as String?;
                            if (inventoryId != null) {
                              _navigateToInventory(
                                  inventoryId);
                            }
                          },
                          icon: const Icon(Icons.open_in_new,
                              size: 16),
                          label: const Text('Open',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ),
                    ...items.map((result) => _buildItemCard(
                        result['item'] as InventoryItem,
                        inventoryName)),
                    const SizedBox(height: 8),
                  ]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(InventoryItem item, String inventoryName) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: item.isExpired
              ? Colors.red.shade100
              : item.isExpiringSoon
                  ? Colors.orange.shade100
                  : colorScheme.primaryContainer,
          child: Icon(Icons.inventory_2,
              size: 20,
              color: item.isExpired
                  ? Colors.red
                  : item.isExpiringSoon
                      ? Colors.orange
                      : colorScheme.primary),
        ),
        title: Row(children: [
          Expanded(
              child: Text(item.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          if (item.isExpired)
            _buildBadge('EXPIRED', Colors.red)
          else if (item.isExpiringSoon)
            _buildBadge('EXPIRING', Colors.orange),
        ]),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.code.isNotEmpty)
                Text('Code: ${item.code}',
                    style: const TextStyle(fontSize: 12)),
              if (item.barcode.isNotEmpty)
                Text('Barcode: ${item.barcode}',
                    style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: [
                _buildInfoChip(
                    Icons.label,
                    item.label,
                    colorScheme.secondaryContainer),
                const SizedBox(width: 8),
                _buildInfoChip(
                    Icons.inventory_2,
                    inventoryName,
                    colorScheme.tertiaryContainer),
              ]),
              const SizedBox(height: 2),
              Text('👤 ${item.creatorDisplayName}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500])),
              if (item.updatedByName != null &&
                  item.updatedByName != item.createdByName)
                Text('✏️ ${item.updaterDisplayName}',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400])),
            ]),
        trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${item.quantity}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('Qty',
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 11)),
            ]),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.barcode.isNotEmpty)
                    _infoRow('Barcode', item.barcode),
                  if (item.color.isNotEmpty)
                    _infoRow('Color', item.color),
                  if (item.material.isNotEmpty)
                    _infoRow('Material', item.material),
                  if (item.size.isNotEmpty)
                    _infoRow('Size', item.size),
                  if (item.productionDate != null)
                    _infoRow('Production',
                        item.productionDate
                            .toString()
                            .split(' ')[0]),
                  if (item.expireDate != null)
                    _infoRow('Expires',
                        item.expireDate
                            .toString()
                            .split(' ')[0]),
                  if (item.note.isNotEmpty)
                    _infoRow('Note', item.note),
                  ...item.userCustomFields.entries
                      .map((e) => _infoRow(e.key, e.value)),
                  const Divider(height: 16),
                  _infoRow('Inventory', inventoryName),
                  _infoRow('Label', item.label),
                  _infoRow(
                      'Created by', item.creatorDisplayName),
                  if (item.updatedByName != null &&
                      item.updatedByName !=
                          item.createdByName)
                    _infoRow('Updated by',
                        item.updaterDisplayName),
                  const SizedBox(height: 8),
                  if (_canUpdate)
                    Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filled(
                            onPressed: item.quantity > 0
                                ? () =>
                                    _adjustQuantity(item, -1)
                                : null,
                            icon: const Icon(Icons.remove,
                                size: 20),
                            style: IconButton.styleFrom(
                                backgroundColor:
                                    colorScheme.errorContainer,
                                foregroundColor:
                                    colorScheme.error),
                          ),
                          Text('${item.quantity}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.w700)),
                          IconButton.filled(
                            onPressed: item.quantity <
                                    InventoryItem
                                        .maxQuantity
                                ? () =>
                                    _adjustQuantity(item, 1)
                                : null,
                            icon: const Icon(Icons.add,
                                size: 20),
                            style: IconButton.styleFrom(
                                backgroundColor:
                                    colorScheme.primaryContainer,
                                foregroundColor:
                                    colorScheme.primary),
                          ),
                          IconButton(
                              onPressed: () =>
                                  _editItem(item),
                              icon: const Icon(Icons.edit,
                                  size: 20),
                              tooltip: 'Edit item'),
                        ])
                  else
                    Center(
                        child: Text('View only',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500]))),
                ]),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildInfoChip(
      IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12),
            const SizedBox(width: 4),
            Flexible(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis)),
          ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text('$label: ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontSize: 13))),
          ]),
    );
  }
}

// ─── Simple Edit Sheet ─────────────────────────────────────────────

class _SimpleEditSheet extends StatefulWidget {
  final InventoryItem item;
  const _SimpleEditSheet({required this.item});

  @override
  State<_SimpleEditSheet> createState() => _SimpleEditSheetState();
}

class _SimpleEditSheetState extends State<_SimpleEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _noteController;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _quantityController = TextEditingController(
        text: widget.item.quantity.toString());
    _noteController = TextEditingController(text: widget.item.note);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      widget.item.name = _nameController.text.trim();
      widget.item.quantity =
          int.tryParse(_quantityController.text) ??
              widget.item.quantity;
      widget.item.note = _noteController.text.trim();
      widget.item.modified = DateTime.now();
      await widget.item.save();
      if (!mounted) return;
      Navigator.pop(context, widget.item);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Error saving: $e';
      });
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
      child: Form(
        key: _formKey,
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
                          borderRadius:
                              BorderRadius.circular(4)))),
              const SizedBox(height: 18),
              Text('Quick Edit',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                      filled: true),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                      filled: true),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Quantity is required';
                    }
                    final parsed =
                        int.tryParse(value.trim());
                    if (parsed == null) {
                      return 'Must be a valid number';
                    }
                    if (parsed < 0 ||
                        parsed >
                            InventoryItem.maxQuantity) {
                      return 'Must be 0-${InventoryItem.maxQuantity}';
                    }
                    return null;
                  }),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: 'Note',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                      filled: true)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        40))),
                        child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        40))),
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                            : const Text('Save',
                                style: TextStyle(
                                    fontWeight:
                                        FontWeight.w700)))),
              ]),
            ]),
      ),
    );
  }
}