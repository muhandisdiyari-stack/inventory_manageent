import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../inventory_management/providers/inventory_provider.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';
import '../../inventory_management/screens/inventory_home_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  Timer? _debounce;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _performSearch(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _hasSearched = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      try {
        final provider = context.read<InventoryProvider>();
        final results = provider.searchAllInventories(query.trim());

        if (mounted) {
          setState(() {
            _results = results;
            _isSearching = false;
            _hasSearched = true;
            _error = results.isEmpty ? 'No results found' : null;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearching = false;
            _hasSearched = true;
            _error = 'Search error: ${e.toString()}';
          });
        }
      }
    });
  }

  void _editItem(InventoryItem item) async {
    if (!mounted) return;

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

  void _adjustQuantity(InventoryItem item, int delta) async {
    try {
      final newQuantity = (item.quantity + delta).clamp(0, InventoryItem.maxQuantity);
      if (newQuantity == item.quantity) return;

      item.quantity = newQuantity;
      item.modified = DateTime.now();
      await item.save();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quantity: ${item.quantity}'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            margin: const EdgeInsets.all(20),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating quantity: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _navigateToInventory(String inventoryId) {
    if (!mounted) return;
    
    final listProvider = context.read<InventoryListProvider>();
    listProvider.selectInventory(inventoryId);
    
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
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _performSearch('');
                    },
                  )
                : const Icon(Icons.search, size: 20),
          ),
          onChanged: _performSearch,
          onSubmitted: _performSearch,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...'),
          ],
        ),
      );
    }

    if (!_hasSearched && _searchController.text.isEmpty) {
      return _buildInitialState();
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            if (_searchController.text.isNotEmpty)
              Text(
                '"${_searchController.text}"',
                style: TextStyle(color: Colors.grey[500]),
              ),
          ],
        ),
      );
    }

    return _buildResults();
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Search Across All Inventories',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search by name, code, barcode, or size',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['name', 'code', 'barcode', 'size', 'color', 'material']
                .map((f) => Chip(
                      label: Text(f, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    // Group results by inventory
    final groupedResults = <String, List<Map<String, dynamic>>>{};
    for (var result in _results) {
      final inventoryName = (result['inventoryName'] as String?) ?? 'Unknown';
      groupedResults.putIfAbsent(inventoryName, () => []).add(result);
    }

    return Column(
      children: [
        // Results summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Found ${_results.length} ${_results.length == 1 ? 'item' : 'items'} '
                'in ${groupedResults.length} ${groupedResults.length == 1 ? 'inventory' : 'inventories'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        
        // Results list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groupedResults.length,
            itemBuilder: (context, index) {
              final inventoryName = groupedResults.keys.elementAt(index);
              final items = groupedResults[inventoryName]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Inventory header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                inventoryName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            final inventoryId = items.first['inventoryId'] as String?;
                            if (inventoryId != null) {
                              _navigateToInventory(inventoryId);
                            }
                          },
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  // Items
                  ...items.map((result) {
                    final item = result['item'] as InventoryItem;
                    return _buildItemCard(item, inventoryName);
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(InventoryItem item, String inventoryName) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: item.isExpired
              ? Colors.red.shade100
              : item.isExpiringSoon
                  ? Colors.orange.shade100
                  : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.inventory_2,
            size: 20,
            color: item.isExpired
                ? Colors.red
                : item.isExpiringSoon
                    ? Colors.orange
                    : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Status badges
            if (item.isExpired)
              _buildStatusBadge('EXPIRED', Colors.red)
            else if (item.isExpiringSoon)
              _buildStatusBadge('EXPIRING', Colors.orange),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.code.isNotEmpty) 
              Text('Code: ${item.code}', style: const TextStyle(fontSize: 12)),
            if (item.barcode.isNotEmpty) 
              Text('Barcode: ${item.barcode}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildInfoChip(Icons.label, item.label, Theme.of(context).colorScheme.secondaryContainer),
                const SizedBox(width: 8),
                _buildInfoChip(Icons.inventory_2, inventoryName, Theme.of(context).colorScheme.tertiaryContainer),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${item.quantity}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text('Qty', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item details
                if (item.barcode.isNotEmpty) _infoRow('Barcode', item.barcode),
                if (item.color.isNotEmpty) _infoRow('Color', item.color),
                if (item.material.isNotEmpty) _infoRow('Material', item.material),
                if (item.size.isNotEmpty) _infoRow('Size', item.size),
                if (item.productionDate != null)
                  _infoRow('Production', item.productionDate.toString().split(' ')[0]),
                if (item.expireDate != null)
                  _infoRow('Expires', item.expireDate.toString().split(' ')[0]),
                if (item.note.isNotEmpty) _infoRow('Note', item.note),
                ...item.customFields.entries
                    .where((e) => e.key != '_supabase_id')
                    .map((e) => _infoRow(e.key, e.value)),
                const Divider(height: 16),
                _infoRow('Inventory', inventoryName),
                _infoRow('Label', item.label),
                const SizedBox(height: 8),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      onPressed: item.quantity > 0 ? () => _adjustQuantity(item, -1) : null,
                      icon: const Icon(Icons.remove, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.errorContainer,
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    Text(
                      '${item.quantity}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton.filled(
                      onPressed: item.quantity < InventoryItem.maxQuantity
                          ? () => _adjustQuantity(item, 1)
                          : null,
                      icon: const Icon(Icons.add, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _editItem(item),
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: 'Edit item',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
            child: Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Simple Edit Sheet ────────────────────────────────────────────

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
    _quantityController = TextEditingController(text: widget.item.quantity.toString());
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
      widget.item.quantity = int.tryParse(_quantityController.text) ?? widget.item.quantity;
      widget.item.note = _noteController.text.trim();
      widget.item.modified = DateTime.now();
      await widget.item.save();

      if (!mounted) return;
      Navigator.pop(context, widget.item);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Error saving: ${e.toString()}';
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
        top: 20,
      ),
      child: Form(
        key: _formKey,
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
              'Quick Edit',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Quantity is required';
                final parsed = int.tryParse(value.trim());
                if (parsed == null) return 'Must be a valid number';
                if (parsed < 0 || parsed > InventoryItem.maxQuantity) {
                  return 'Must be 0-${InventoryItem.maxQuantity}';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
              ),
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
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}