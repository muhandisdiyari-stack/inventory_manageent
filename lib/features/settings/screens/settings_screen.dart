import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inventory_management/core/config/app_config.dart';
import 'package:inventory_management/core/models/user.dart';
import 'package:inventory_management/core/services/permission_service.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../inventory_management/bloc/inventory_bloc.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../../company/bloc/company_bloc.dart';
import '../../theme/bloc/theme_bloc.dart';

const Set<String> _permanentFields = {'Name', 'Quantity'};

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
  bool _isSaving = false;
  String? _errorMessage;
  String? _lastInventoryId;
  bool _canManageSettings = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentId = context.read<InventoryBloc>().state.inventoryId;
    if (currentId != _lastInventoryId) {
      _lastInventoryId = currentId;
      _loadCurrentSettings();
      _checkPermissions();
    }
  }

  @override
  void dispose() {
    _customFieldController.dispose();
    super.dispose();
  }

  void _checkPermissions() async {
    try {
      final inventoryId =
          context.read<InventoryBloc>().state.inventoryId;

      if (inventoryId != null && AppConfig.useSupabase) {
        final permService = PermissionService();
        final perms =
            await permService.getInventoryPermissions(inventoryId);
        if (mounted) {
          setState(
              () => _canManageSettings = perms.canManageSettings);
        }
      } else {
        final companyState = context.read<CompanyBloc>().state;
        final companyRole = companyState.selectedCompany?['role']
                ?.toString() ??
            'viewer';
        final permissions =
            InventoryPermissions.fromRole(companyRole);
        if (mounted) {
          setState(() =>
              _canManageSettings = permissions.canManageSettings);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _canManageSettings = false);
    }
  }

  void _loadCurrentSettings() {
    final state = context.read<InventoryBloc>().state;
    try {
      final settings = state.settings;
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
                isRequired: f.isRequired))
            .toList();
        _customFields = [];
      }
      _ensureQuantityField();
      _customFieldController.clear();
      _hasChanges = false;
      _errorMessage = null;
    } catch (e) {
      setState(
          () => _errorMessage = 'Failed to load settings: $e');
    }
  }

  void _ensureQuantityField() {
    if (!_fieldConfigs.any((f) => f.fieldName == 'Quantity')) {
      _fieldConfigs.add(FieldConfig(
          fieldName: 'Quantity',
          isEnabled: true,
          isRequired: true));
    }
  }

  Future<void> _saveSettings() async {
    if (!_canManageSettings) {
      SnackBarUtils.error(context,
          'You do not have permission to change settings');
      return;
    }

    _ensureQuantityField();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final settings = InventorySettings(
        fieldConfigs: _fieldConfigs
            .map((f) => FieldConfig(
                fieldName: f.fieldName,
                isEnabled: f.isEnabled,
                isRequired: f.isRequired))
            .toList(),
        customFieldNames: List<String>.from(_customFields),
      );
      context.read<InventoryBloc>().add(UpdateSettings(settings));
      if (!mounted) return;
      setState(() {
        _hasChanges = false;
        _isSaving = false;
      });
      final name = context.read<InventoryBloc>().state.inventoryName ??
          'inventory';
      SnackBarUtils.success(context, 'Settings saved for $name');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to save: $e';
      });
    }
  }

  bool _isPermanent(String fieldName) =>
      _permanentFields.contains(fieldName);

  void _updateField(int index, FieldConfig newConfig) {
    if (!_canManageSettings) return;
    setState(() {
      _fieldConfigs[index] = newConfig;
      _hasChanges = true;
    });
  }

  static const _standardFields = {
    'Name',
    'Code',
    'Barcode',
    'Color',
    'Material',
    'Size',
    'Quantity',
    'Production Date',
    'Expire Date',
    'Note',
    'Label',
    'Inventory',
  };

  void _addCustomField() {
    if (!_canManageSettings) return;
    final field = _customFieldController.text.trim();
    if (field.isEmpty) return;
    final lower = field.toLowerCase();
    if (_standardFields.any((f) => f.toLowerCase() == lower)) {
      SnackBarUtils.show(context,
          message: '"$field" is a standard field',
          icon: Icons.warning_amber);
      return;
    }
    if (_customFields.any((f) => f.toLowerCase() == lower)) {
      SnackBarUtils.show(context,
          message: '"$field" already exists',
          icon: Icons.warning_amber);
      return;
    }
    setState(() {
      _customFields.add(field);
      _customFieldController.clear();
      _hasChanges = true;
    });
  }

  void _removeCustomField(String field) {
    if (!_canManageSettings) return;
    setState(() {
      _customFields.remove(field);
      _hasChanges = true;
    });
  }

  void _toggleDarkMode(bool value) {
    context.read<ThemeBloc>().add(
        SetThemeMode(value ? ThemeMode.dark : ThemeMode.light));
    SnackBarUtils.success(context,
        'Switched to ${value ? 'dark' : 'light'} theme');
  }

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
              child: const Text('Keep editing')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              child: const Text('Discard')),
        ],
      ),
    );
    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final inventoryName = state.inventoryName ?? 'Inventory';
        final isDarkMode = context.watch<ThemeBloc>().state.isDark;

        return PopScope(
          canPop: !_hasChanges,
          onPopInvokedWithResult: (didPop, result) async {
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
                  Text(inventoryName,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .primary)),
                ],
              ),
              actions: [
                if (_hasChanges && _canManageSettings)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Icon(Icons.save, size: 18),
                      label: Text(
                          _isSaving ? 'Saving...' : 'Save'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(40)),
                      ),
                    ),
                  ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_canManageSettings)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can view settings but do not have permission to modify them. Only owners and admins can change settings.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.orange),
                        ),
                      ),
                    ]),
                  ),
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13)),
                      ),
                    ]),
                  ),
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
      },
    );
  }

  Widget _buildInfoCard(String inventoryName) {
    return Card(
      color: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Settings for: $inventoryName',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer)),
          ),
        ]),
      ),
    );
  }

  Widget _buildAppearanceCard(bool isDarkMode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.palette,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appearance',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Global app setting — applies everywhere',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Toggle dark theme'),
              value: isDarkMode,
              onChanged: _toggleDarkMode,
              secondary: Icon(
                  isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: Theme.of(context).colorScheme.primary),
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
            Row(children: [
              Icon(Icons.tune,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Field Configuration',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Enable or disable fields and mark them as required.',
                style:
                    TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            ..._fieldConfigs
                .asMap()
                .entries
                .map((entry) => _buildFieldTile(entry.value, entry.key)),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldTile(FieldConfig config, int index) {
    final permanent = _isPermanent(config.fieldName);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(children: [
          Row(children: [
            Switch(
              value: config.isEnabled,
              onChanged: permanent || !_canManageSettings
                  ? null
                  : (enabled) => _updateField(
                      index,
                      FieldConfig(
                          fieldName: config.fieldName,
                          isEnabled: enabled,
                          isRequired:
                              enabled ? config.isRequired : false)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(config.fieldName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            _buildStatusBadge(config, permanent),
          ]),
          if (!permanent && config.isEnabled)
            Padding(
              padding:
                  const EdgeInsets.only(left: 56, top: 4, bottom: 4),
              child: Row(children: [
                Text('Required',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[700])),
                const SizedBox(width: 8),
                Switch(
                  value: config.isRequired,
                  onChanged: !_canManageSettings
                      ? null
                      : (required) => _updateField(
                          index,
                          FieldConfig(
                              fieldName: config.fieldName,
                              isEnabled: config.isEnabled,
                              isRequired: required)),
                ),
              ]),
            ),
          if (permanent)
            Padding(
              padding:
                  const EdgeInsets.only(left: 56, top: 2, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Always enabled and required',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[500])),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildStatusBadge(FieldConfig config, bool permanent) {
    String label;
    Color color;

    if (!config.isEnabled) {
      label = 'Disabled';
      color = Colors.grey;
    } else if (permanent) {
      label = 'Always required';
      color = Theme.of(context).colorScheme.primary;
    } else if (config.isRequired) {
      label = 'Required';
      color = Theme.of(context).colorScheme.error;
    } else {
      label = 'Optional';
      color = Theme.of(context).colorScheme.primary;
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCustomFieldsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.add_circle_outline,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Custom Fields',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Add custom fields specific to this inventory.',
                style:
                    TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            if (_canManageSettings)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _customFieldController,
                builder: (_, value, __) {
                  return Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _customFieldController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Supplier, Location',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                          filled: true,
                        ),
                        onSubmitted: (_) => _addCustomField(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          value.text.trim().isNotEmpty
                              ? _addCustomField
                              : null,
                      child: const Text('Add'),
                    ),
                  ]);
                },
              ),
            const SizedBox(height: 12),
            if (_customFields.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text('No custom fields added yet',
                      style: TextStyle(color: Colors.grey[500])),
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
        trailing: _canManageSettings
            ? IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red),
                tooltip: 'Remove field',
                onPressed: () => _removeCustomField(field),
              )
            : null,
      ),
    );
  }
}