import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../inventory_management/providers/inventory_provider.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../../../core/constants/app_constants.dart';

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
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    final provider = context.read<InventoryProvider>();
    final settings = provider.currentSettings;
    if (settings != null) {
      // Use deepCopy for safe editing
      final copy = settings.deepCopy();
      _fieldConfigs = copy.fieldConfigs;
      _customFields = copy.customFieldNames;
    } else {
      final defaultSettings = InventorySettings();
      _fieldConfigs = defaultSettings.fieldConfigs.map((f) => FieldConfig(
        fieldName: f.fieldName,
        isEnabled: f.isEnabled,
        isRequired: f.isRequired,
      )).toList();
      _customFields = [];
    }
    
    // Load dark mode setting
    final appSettings = Hive.box('app_settings');
    _isDarkMode = appSettings.get(AppConstants.darkModeKey, defaultValue: false) as bool;
  }

  @override
  void dispose() {
    _customFieldController.dispose();
    super.dispose();
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _updateField(int index, FieldConfig newConfig) {
    setState(() {
      _fieldConfigs[index] = newConfig;
      _markChanged();
    });
  }

  void _toggleDarkMode(bool value) {
    setState(() => _isDarkMode = value);
    final appSettings = Hive.box('app_settings');
    appSettings.put(AppConstants.darkModeKey, value);
    // This won't take effect until app restarts without a theme provider
    // For immediate effect, you'd need a ThemeProvider
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Dark mode preference saved. Restart app to apply.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          margin: const EdgeInsets.all(20),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final inventoryName = provider.currentInventoryName ?? 'Inventory';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inventory Settings', style: TextStyle(fontSize: 16)),
            Text(
              inventoryName,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
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
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
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
          _buildAppearanceCard(),
          const SizedBox(height: 16),
          _buildFieldConfigCard(),
          const SizedBox(height: 16),
          _buildCustomFieldsCard(),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String inventoryName) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Settings for: $inventoryName',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Toggle dark theme (requires restart)'),
              value: _isDarkMode,
              onChanged: _toggleDarkMode,
              secondary: Icon(
                _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Field Configuration',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Enable/disable fields and set them as required.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            ..._fieldConfigs.asMap().entries.map((entry) => _buildFieldTile(entry.value, entry.key)),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldTile(FieldConfig config, int index) {
    final isNameField = config.fieldName == 'Name';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ExpansionTile(
        key: ValueKey('${config.fieldName}_$index'),
        title: Text(config.fieldName, style: const TextStyle(fontWeight: FontWeight.w600)),
        leading: Switch(
          value: config.isEnabled,
          onChanged: isNameField
              ? null
              : (enabled) {
                  final updated = FieldConfig(
                    fieldName: config.fieldName,
                    isEnabled: enabled,
                    isRequired: enabled ? config.isRequired : false,
                  );
                  _updateField(index, updated);
                },
        ),
        subtitle: config.isEnabled
            ? Text(
                config.isRequired ? 'Required' : 'Optional',
                style: TextStyle(
                  color: config.isRequired
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              )
            : const Text('Disabled', style: TextStyle(fontSize: 12)),
        children: [
          if (!isNameField && config.isEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('Mark as required:'),
                  const SizedBox(width: 8),
                  Switch(
                    value: config.isRequired,
                    onChanged: (required) {
                      final updated = FieldConfig(
                        fieldName: config.fieldName,
                        isEnabled: config.isEnabled,
                        isRequired: required,
                      );
                      _updateField(index, updated);
                    },
                  ),
                ],
              ),
            ),
          if (isNameField)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Name field is always required and enabled',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Custom Fields',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Add custom fields specific to this inventory',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customFieldController,
                    decoration: InputDecoration(
                      hintText: 'e.g., Supplier, Location',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    onSubmitted: (_) => _addCustomField(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _addCustomField, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 12),
            if (_customFields.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text('No custom fields added yet', style: TextStyle(color: Colors.grey[500])),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.label_outline),
        title: Text(field),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () {
            setState(() {
              _customFields.remove(field);
              _markChanged();
            });
          },
        ),
      ),
    );
  }

  void _addCustomField() {
    final field = _customFieldController.text.trim();
    if (field.isEmpty) return;
    final exists = _customFields.any((f) => f.toLowerCase() == field.toLowerCase());
    if (!exists) {
      setState(() {
        _customFields.add(field);
        _customFieldController.clear();
        _markChanged();
      });
    }
  }

  void _saveSettings(InventoryProvider provider) {
    final settings = InventorySettings(
      fieldConfigs: _fieldConfigs.map((f) => FieldConfig(
        fieldName: f.fieldName,
        isEnabled: f.isEnabled,
        isRequired: f.isRequired,
      )).toList(),
      customFieldNames: List<String>.from(_customFields),
    );
    provider.updateSettings(settings);
    setState(() => _hasChanges = false);
    if (mounted) {
      final name = provider.currentInventoryName ?? 'inventory';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Settings saved for $name'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          margin: const EdgeInsets.all(20),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}