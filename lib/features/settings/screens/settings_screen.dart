import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../inventory_management/providers/inventory_provider.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../../../core/providers/theme_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Fields that are always enabled and required — they cannot be toggled off.
const Set<String> _permanentFields = {'Name', 'Quantity'};

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late List<FieldConfig> _fieldConfigs;
  late List<String> _customFields;
  final _customFieldController = TextEditingController();
  bool _hasChanges = false;

  // Track the last-loaded inventory ID so we can reload when it changes.
  String? _loadedInventoryId;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Safe to call here — context is fully attached.
    // Reload whenever the active inventory changes.
    final provider = context.read<InventoryProvider>();
    final currentId = provider.currentInventoryId;
    if (currentId != _loadedInventoryId) {
      _loadedInventoryId = currentId;
      _loadCurrentSettings(provider);
    }
  }

  @override
  void dispose() {
    _customFieldController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Settings load / save
  // ---------------------------------------------------------------------------

  void _loadCurrentSettings(InventoryProvider provider) {
    final settings = provider.currentSettings;
    if (settings != null) {
      final copy = settings.deepCopy();
      _fieldConfigs = copy.fieldConfigs;
      _customFields = copy.customFieldNames;
    } else {
      final defaultSettings = InventorySettings();
      _fieldConfigs = defaultSettings.fieldConfigs
          .map((f) => FieldConfig(
                fieldName: f.fieldName,
                isEnabled: f.isEnabled,
                isRequired: f.isRequired,
              ))
          .toList();
      _customFields = [];
    }
    _ensureQuantityField();
    _customFieldController.clear();
    _hasChanges = false;
  }

  /// Ensures the Quantity field always exists in the config list.
  void _ensureQuantityField() {
    final hasQuantity =
        _fieldConfigs.any((f) => f.fieldName == 'Quantity');
    if (!hasQuantity) {
      final sizeIndex =
          _fieldConfigs.indexWhere((f) => f.fieldName == 'Size');
      final newField = FieldConfig(
        fieldName: 'Quantity',
        isEnabled: true,
        isRequired: true,
      );
      if (sizeIndex >= 0) {
        _fieldConfigs.insert(sizeIndex + 1, newField);
      } else {
        _fieldConfigs.add(newField);
      }
    }
  }

  void _saveSettings(InventoryProvider provider) {
    // Re-guarantee permanent fields are intact before saving.
    _ensureQuantityField();

    final settings = InventorySettings(
      fieldConfigs: _fieldConfigs
          .map((f) => FieldConfig(
                fieldName: f.fieldName,
                isEnabled: f.isEnabled,
                isRequired: f.isRequired,
              ))
          .toList(),
      customFieldNames: List<String>.from(_customFields),
    );
    provider.updateSettings(settings);
    setState(() => _hasChanges = false);

    if (mounted) {
      final name = provider.currentInventoryName ?? 'inventory';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved for $name'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40)),
          margin: const EdgeInsets.all(20),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Field helpers
  // ---------------------------------------------------------------------------

  bool _isPermanent(String fieldName) =>
      _permanentFields.contains(fieldName);

  void _updateField(int index, FieldConfig newConfig) {
    setState(() {
      _fieldConfigs[index] = newConfig;
      _hasChanges = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Custom field helpers
  // ---------------------------------------------------------------------------

  static const _standardFields = {
    'Name', 'Code', 'Barcode', 'Color', 'Material', 'Size',
    'Quantity', 'Production Date', 'Expire Date', 'Note', 'Label', 'Inventory',
  };

  void _addCustomField() {
    final field = _customFieldController.text.trim();
    if (field.isEmpty) return;

    final lower = field.toLowerCase();

    if (_standardFields.any((f) => f.toLowerCase() == lower)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$field" is a standard field and cannot be added as custom'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isDuplicate =
        _customFields.any((f) => f.toLowerCase() == lower);
    if (isDuplicate) {
      // Give feedback instead of silently ignoring.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$field" already exists'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _customFields.add(field);
      _customFieldController.clear();
      _hasChanges = true;
    });
  }

  void _removeCustomField(String field) {
    setState(() {
      _customFields.remove(field);
      _hasChanges = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Appearance
  // ---------------------------------------------------------------------------

  void _toggleDarkMode(bool value) {
    context.read<ThemeProvider>().setThemeMode(
          value ? ThemeMode.dark : ThemeMode.light,
        );
    // No mounted check needed — this is a synchronous callback from a widget
    // that is guaranteed to be mounted when its onChanged fires.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to ${value ? 'dark' : 'light'} theme'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Back-navigation guard
  // ---------------------------------------------------------------------------

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
            'You have unsaved changes. Discard them and go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return shouldDiscard ?? false;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final inventoryName =
        provider.currentInventoryName ?? 'Inventory';
    final themeProvider = context.watch<ThemeProvider>();
    final isDarkMode = themeProvider.isDarkMode;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Inventory Settings',
                  style: TextStyle(fontSize: 16)),
              Text(
                inventoryName,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          actions: [
            if (_hasChanges)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => _saveSettings(provider),
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor:
                        Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40)),
                  ),
                ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildInfoCard(inventoryName),
            const SizedBox(height: 16),
            _buildAppearanceCard(isDarkMode),
            const SizedBox(height: 16),
            _buildFieldConfigCard(),
            const SizedBox(height: 16),
            _buildCustomFieldsCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Info card
  // ---------------------------------------------------------------------------

  Widget _buildInfoCard(String inventoryName) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: Theme.of(context).colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Settings for: $inventoryName',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Appearance card — global app setting, clearly labeled as such
  // ---------------------------------------------------------------------------

  Widget _buildAppearanceCard(bool isDarkMode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Global app setting — applies everywhere',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Toggle dark theme'),
              value: isDarkMode,
              onChanged: _toggleDarkMode,
              secondary: Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field config card
  // ---------------------------------------------------------------------------

  Widget _buildFieldConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Field Configuration',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Enable or disable fields and mark them as required.',
              style:
                  TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            ..._fieldConfigs.asMap().entries.map(
                  (entry) =>
                      _buildFieldTile(entry.value, entry.key),
                ),
          ],
        ),
      ),
    );
  }

  /// Each field is a flat [ListTile] instead of a nested [ExpansionTile],
  /// avoiding the tap-target conflict between the tile expand action and
  /// the enable/require toggles.
  Widget _buildFieldTile(FieldConfig config, int index) {
    final permanent = _isPermanent(config.fieldName);

    return Container(
      // Use Container + decoration instead of nested Card to avoid
      // double-elevation artifacts.
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                // Enable toggle
                Switch(
                  value: config.isEnabled,
                  onChanged: permanent
                      ? null
                      : (enabled) => _updateField(
                            index,
                            FieldConfig(
                              fieldName: config.fieldName,
                              isEnabled: enabled,
                              // Disabling a field also clears its required flag.
                              isRequired: enabled
                                  ? config.isRequired
                                  : false,
                            ),
                          ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.fieldName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                // Status badge — single source of truth, shown once.
                _StatusBadge(
                  enabled: config.isEnabled,
                  required: config.isRequired || permanent,
                  permanent: permanent,
                ),
              ],
            ),
            // "Mark as required" row — only visible when enabled and not permanent.
            if (!permanent && config.isEnabled)
              Padding(
                padding:
                    const EdgeInsets.only(left: 56, top: 4, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      'Required',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: config.isRequired,
                      onChanged: (required) => _updateField(
                        index,
                        FieldConfig(
                          fieldName: config.fieldName,
                          isEnabled: config.isEnabled,
                          isRequired: required,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (permanent)
              Padding(
                padding:
                    const EdgeInsets.only(left: 56, top: 2, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Always enabled and required',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Custom fields card
  // ---------------------------------------------------------------------------

  Widget _buildCustomFieldsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Custom Fields',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Add custom fields specific to this inventory.',
              style:
                  TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            // Input row — button disabled when the field is empty.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _customFieldController,
              builder: (_, value, __) {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customFieldController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Supplier, Location',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        onSubmitted: (_) => _addCustomField(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: value.text.trim().isNotEmpty
                          ? _addCustomField
                          : null,
                      child: const Text('Add'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (_customFields.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No custom fields added yet',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ..._customFields.map(_buildCustomFieldTile),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomFieldTile(String field) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.label_outline),
        title: Text(field),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Remove field',
          onPressed: () => _removeCustomField(field),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widget – consolidates the status badge logic in one place
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final bool enabled;
  final bool required;
  final bool permanent;

  const _StatusBadge({
    required this.enabled,
    required this.required,
    required this.permanent,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return _badge(context, 'Disabled', Colors.grey);
    }
    if (permanent) {
      return _badge(
          context, 'Always required', Theme.of(context).colorScheme.primary);
    }
    if (required) {
      return _badge(context, 'Required',
          Theme.of(context).colorScheme.error);
    }
    return _badge(context, 'Optional',
        Theme.of(context).colorScheme.primary);
  }

  Widget _badge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}