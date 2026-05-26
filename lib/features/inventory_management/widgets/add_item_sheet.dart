import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import 'unified_barcode_scanner.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class AddItemSheet {
  static void show(
    BuildContext context, {
    required String label,
    required InventorySettings? settings,
    required Future<void> Function(InventoryItem) onSave,
    InventoryItem? existingItem,
    String? inventoryName,
    String? inventoryId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _AddItemForm(
        label: label,
        settings: settings,
        onSave: onSave,
        existingItem: existingItem,
        inventoryName: inventoryName,
        inventoryId: inventoryId,
      ),
    );
  }
}

class _AddItemForm extends StatefulWidget {
  final String label;
  final InventorySettings? settings;
  final Future<void> Function(InventoryItem) onSave;
  final InventoryItem? existingItem;
  final String? inventoryName;
  final String? inventoryId;

  const _AddItemForm({
    required this.label,
    required this.settings,
    required this.onSave,
    this.existingItem,
    this.inventoryName,
    this.inventoryId,
  });

  @override
  State<_AddItemForm> createState() => _AddItemFormState();
}

class _AddItemFormState extends State<_AddItemForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _colorController;
  late final TextEditingController _materialController;
  late final TextEditingController _sizeController;
  late final TextEditingController _noteController;
  late final TextEditingController _quantityController;

  DateTime? _productionDate;
  DateTime? _expireDate;
  final Map<String, TextEditingController> _customFieldControllers = {};

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;

    _nameController = TextEditingController(text: item?.name ?? '');
    _codeController = TextEditingController(text: item?.code ?? '');
    _barcodeController = TextEditingController(text: item?.barcode ?? '');
    _colorController = TextEditingController(text: item?.color ?? '');
    _materialController = TextEditingController(text: item?.material ?? '');
    _sizeController = TextEditingController(text: item?.size ?? '');
    _noteController = TextEditingController(text: item?.note ?? '');
    _quantityController = TextEditingController(
      text: (item?.quantity ?? 0).toString(),
    );
    _productionDate = item?.productionDate;
    _expireDate = item?.expireDate;

    _initializeCustomFields(item);
  }

  void _initializeCustomFields(InventoryItem? item) {
    final customFieldNames = widget.settings?.customFieldNames ?? const [];
    for (final fieldName in customFieldNames) {
      _customFieldControllers[fieldName] = TextEditingController(
        text: item?.customFields[fieldName] ?? '',
      );
    }
  }

  @override
  void didUpdateWidget(covariant _AddItemForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newFields = widget.settings?.customFieldNames ?? const [];

    for (final fieldName in newFields) {
      if (!_customFieldControllers.containsKey(fieldName)) {
        _customFieldControllers[fieldName] = TextEditingController(
          text: widget.existingItem?.customFields[fieldName] ?? '',
        );
      }
    }

    final keysToRemove = _customFieldControllers.keys
        .where((key) => !newFields.contains(key))
        .toList();
    for (final key in keysToRemove) {
      _customFieldControllers[key]?.dispose();
      _customFieldControllers.remove(key);
    }

    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _barcodeController.dispose();
    _colorController.dispose();
    _materialController.dispose();
    _sizeController.dispose();
    _noteController.dispose();
    _quantityController.dispose();
    for (final controller in _customFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isFieldEnabled(String fieldName) {
    if (widget.settings == null) {
      const alwaysShown = ['Name', 'Code', 'Barcode', 'Size', 'Quantity', 'Note'];
      return alwaysShown.contains(fieldName);
    }
    return widget.settings!.isFieldEnabled(fieldName);
  }

  bool _isFieldRequired(String fieldName) {
    if (widget.settings == null) {
      return fieldName == 'Name' || fieldName == 'Quantity';
    }
    return widget.settings!.isFieldRequired(fieldName);
  }

  void _openBarcodeScanner() {
    UnifiedBarcodeScanner.showScanner(
      context,
      onBarcodeScanned: (barcode) {
        if (!mounted) return;
        setState(() {
          _barcodeController.text = barcode;
          _errorMessage = null;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Barcode scanned: $barcode', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            margin: const EdgeInsets.all(20),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _clearBarcode() {
    setState(() {
      _barcodeController.clear();
      _errorMessage = null;
    });
  }

  String _getCurrentUserId() {
    try {
      return context.read<AuthBloc>().state.user?.id ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  String _getCurrentUserName() {
    try {
      return context.read<AuthBloc>().state.user?.displayNameOrEmail ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingItem != null;
    final item = widget.existingItem;

    // Show warning if item has reached update limit
    final showUpdateLimitWarning = isEditing && item != null && item.hasReachedUpdateLimit;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                isEditing ? 'Edit Item' : 'Add New Item to ${widget.label}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),

              if (showUpdateLimitWarning) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.purple, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This item has reached the maximum update limit (${item.updateCount}/3). '
                          'Contact an admin to make further changes.',
                          style: const TextStyle(color: Colors.purple, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              if (_isFieldEnabled('Name'))
                _buildTextField(
                  controller: _nameController,
                  label: 'Name',
                  hint: 'Enter item name',
                  icon: Icons.label,
                  required: _isFieldRequired('Name'),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Code'))
                _buildTextField(
                  controller: _codeController,
                  label: 'Code',
                  hint: 'Enter item code',
                  icon: Icons.code,
                  required: _isFieldRequired('Code'),
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Barcode'))
                _buildBarcodeField(enabled: !showUpdateLimitWarning),

              if (_isFieldEnabled('Color'))
                _buildTextField(
                  controller: _colorController,
                  label: 'Color',
                  hint: 'Enter color',
                  icon: Icons.color_lens,
                  required: _isFieldRequired('Color'),
                  textCapitalization: TextCapitalization.words,
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Material'))
                _buildTextField(
                  controller: _materialController,
                  label: 'Material',
                  hint: 'Enter material',
                  icon: Icons.texture,
                  required: _isFieldRequired('Material'),
                  textCapitalization: TextCapitalization.words,
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Size'))
                _buildTextField(
                  controller: _sizeController,
                  label: 'Size',
                  hint: 'Enter size (e.g., S, M, L, XL)',
                  icon: Icons.straighten,
                  required: _isFieldRequired('Size'),
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Quantity'))
                _buildQuantityField(enabled: !showUpdateLimitWarning),

              if (_isFieldEnabled('Production Date'))
                _buildDateField(
                  label: 'Production Date',
                  required: _isFieldRequired('Production Date'),
                  value: _productionDate,
                  onPicked: (d) => setState(() => _productionDate = d),
                  onClear: () => setState(() => _productionDate = null),
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Expire Date'))
                _buildDateField(
                  label: 'Expire Date',
                  required: _isFieldRequired('Expire Date'),
                  value: _expireDate,
                  onPicked: (d) => setState(() => _expireDate = d),
                  onClear: () => setState(() => _expireDate = null),
                  enabled: !showUpdateLimitWarning,
                ),

              if (_isFieldEnabled('Note'))
                _buildTextField(
                  controller: _noteController,
                  label: 'Note',
                  hint: 'Enter notes or description',
                  icon: Icons.note,
                  maxLines: 3,
                  required: _isFieldRequired('Note'),
                  textCapitalization: TextCapitalization.sentences,
                  enabled: !showUpdateLimitWarning,
                ),

              ..._buildCustomFields(enabled: !showUpdateLimitWarning),

              const SizedBox(height: 16),

              if (!showUpdateLimitWarning)
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
                            ? const SizedBox(height: 18, width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(isEditing ? 'Update' : 'Save',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarcodeField({bool enabled = true}) {
    final hasText = _barcodeController.text.isNotEmpty;
    final required = _isFieldRequired('Barcode');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _barcodeController,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: required ? 'Barcode *' : 'Barcode',
          hintText: 'Enter barcode manually or scan',
          prefixIcon: const Icon(Icons.qr_code, size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText && enabled)
                IconButton(icon: const Icon(Icons.clear, size: 20), tooltip: 'Clear barcode', onPressed: _clearBarcode),
              if (enabled)
                IconButton(
                  icon: Icon(Icons.qr_code_scanner, size: 20, color: Theme.of(context).colorScheme.primary),
                  tooltip: 'Scan barcode (Camera, USB Scanner, or Image)',
                  onPressed: _openBarcodeScanner,
                ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: hasText
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1)
              : null,
        ),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Barcode is required' : null : null,
      ),
    );
  }

  Widget _buildQuantityField({bool enabled = true}) {
    final required = _isFieldRequired('Quantity');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _quantityController,
        keyboardType: TextInputType.number,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: required ? 'Quantity *' : 'Quantity',
          hintText: 'Enter quantity (0-${InventoryItem.maxQuantity})',
          prefixIcon: const Icon(Icons.numbers, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          errorStyle: const TextStyle(fontSize: 12),
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Quantity is required';
          if (v == null || v.trim().isEmpty) return null;
          final parsed = int.tryParse(v.trim());
          if (parsed == null) return 'Enter a valid whole number';
          if (parsed < 0) return 'Quantity cannot be negative';
          if (parsed > InventoryItem.maxQuantity) return 'Quantity cannot exceed ${InventoryItem.maxQuantity}';
          return null;
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autofocus = false,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        autofocus: autofocus,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          errorStyle: const TextStyle(fontSize: 12),
        ),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required bool required,
    required DateTime? value,
    required Function(DateTime) onPicked,
    required VoidCallback onClear,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FormField<DateTime?>(
        initialValue: value,
        validator: required ? (v) => v == null ? '$label is required' : null : null,
        builder: (formFieldState) => InkWell(
          onTap: enabled
              ? () async {
                  try {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: value ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      helpText: 'Select $label',
                      cancelText: 'Cancel',
                      confirmText: 'OK',
                    );
                    if (picked != null && mounted) {
                      onPicked(picked);
                      formFieldState.didChange(picked);
                    }
                  } catch (e) {
                    debugPrint('Date picker error: $e');
                  }
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              suffixIcon: value != null && enabled
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: 'Clear date', onPressed: () { onClear(); formFieldState.didChange(null); })
                  : null,
              errorText: formFieldState.errorText,
            ),
            child: Text(
              value != null
                  ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
                  : 'Select date',
              style: TextStyle(color: value != null ? null : Colors.grey, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCustomFields({bool enabled = true}) {
    return _customFieldControllers.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: entry.value,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: entry.key,
            hintText: 'Enter ${entry.key}',
            prefixIcon: const Icon(Icons.edit_note, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
      );
    }).toList();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() { _saving = true; _errorMessage = null; });

    try {
      final customFields = <String, String>{};
      for (final entry in _customFieldControllers.entries) {
        final value = entry.value.text.trim();
        if (value.isNotEmpty) customFields[entry.key] = value;
      }

      final isEditing = widget.existingItem != null;
      final userId = _getCurrentUserId();
      final userName = _getCurrentUserName();
      final now = DateTime.now();

      if (isEditing) {
        final oldItem = widget.existingItem!;
        final oldValues = _captureOldValues(oldItem);

        oldItem.name = _nameController.text.trim();
        oldItem.code = _isFieldEnabled('Code') ? _codeController.text.trim() : '';
        oldItem.barcode = _isFieldEnabled('Barcode') ? _barcodeController.text.trim() : '';
        oldItem.color = _isFieldEnabled('Color') ? _colorController.text.trim() : '';
        oldItem.material = _isFieldEnabled('Material') ? _materialController.text.trim() : '';
        oldItem.size = _isFieldEnabled('Size') ? _sizeController.text.trim() : '';
        oldItem.productionDate = _isFieldEnabled('Production Date') ? _productionDate : null;
        oldItem.expireDate = _isFieldEnabled('Expire Date') ? _expireDate : null;
        oldItem.note = _isFieldEnabled('Note') ? _noteController.text.trim() : '';
        oldItem.quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
        oldItem.label = widget.label;
        oldItem.customFields = customFields;
        oldItem.modified = now;
        oldItem.updatedBy = userId;
        oldItem.updatedByName = userName;
        await oldItem.save();

        final changes = _detectChanges(oldValues, oldItem, customFields);
        if (changes.isNotEmpty) {
          await ActivityLogService().addLog(ActivityLogEntry(
            id: now.microsecondsSinceEpoch.toString(),
            timestamp: now,
            action: 'modified',
            entityType: 'item',
            entityName: oldItem.displayName,
            inventoryId: widget.inventoryId,
            inventoryName: widget.inventoryName,
            labelName: widget.label,
            details: 'Item modified by $userName: "${oldItem.displayName}" (update #${oldItem.updateCount + 1})',
            changes: changes,
          ));
        }
      } else {
        final item = InventoryItem(
          name: _nameController.text.trim(),
          code: _isFieldEnabled('Code') ? _codeController.text.trim() : '',
          barcode: _isFieldEnabled('Barcode') ? _barcodeController.text.trim() : '',
          color: _isFieldEnabled('Color') ? _colorController.text.trim() : '',
          material: _isFieldEnabled('Material') ? _materialController.text.trim() : '',
          size: _isFieldEnabled('Size') ? _sizeController.text.trim() : '',
          productionDate: _isFieldEnabled('Production Date') ? _productionDate : null,
          expireDate: _isFieldEnabled('Expire Date') ? _expireDate : null,
          note: _isFieldEnabled('Note') ? _noteController.text.trim() : '',
          quantity: int.tryParse(_quantityController.text.trim()) ?? 0,
          label: widget.label,
          customFields: customFields,
          modified: now,
          createdAt: now,
          createdBy: userId,
          createdByName: userName,
        );

        await widget.onSave(item);

        await ActivityLogService().addLog(ActivityLogEntry(
          id: item.createdAt.microsecondsSinceEpoch.toString(),
          timestamp: item.createdAt,
          action: 'created',
          entityType: 'item',
          entityName: item.displayName,
          inventoryId: widget.inventoryId,
          inventoryName: widget.inventoryName,
          labelName: widget.label,
          details: 'Item created by $userName: "${item.displayName}" with quantity ${item.quantity}',
        ));
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; _errorMessage = 'Error saving item: ${e.toString()}'; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving item: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    }
  }

  Map<String, String> _captureOldValues(InventoryItem item) {
    return {
      'name': item.name, 'code': item.code, 'barcode': item.barcode,
      'color': item.color, 'material': item.material, 'size': item.size,
      'productionDate': item.productionDate?.toIso8601String() ?? '',
      'expireDate': item.expireDate?.toIso8601String() ?? '',
      'note': item.note, 'quantity': item.quantity.toString(), 'label': item.label,
      ...item.customFields,
    };
  }

  Map<String, FieldChange> _detectChanges(
    Map<String, String> oldValues, InventoryItem newItem, Map<String, String> newCustomFields,
  ) {
    final changes = <String, FieldChange>{};
    void compare(String key, String newValue) {
      if (oldValues[key] != newValue) {
        changes[key] = FieldChange(oldValue: oldValues[key] ?? '', newValue: newValue);
      }
    }
    compare('name', newItem.name);
    compare('code', newItem.code);
    compare('barcode', newItem.barcode);
    compare('color', newItem.color);
    compare('material', newItem.material);
    compare('size', newItem.size);
    compare('productionDate', newItem.productionDate?.toIso8601String() ?? '');
    compare('expireDate', newItem.expireDate?.toIso8601String() ?? '');
    compare('note', newItem.note);
    compare('quantity', newItem.quantity.toString());
    compare('label', newItem.label);
    for (final entry in newCustomFields.entries) {
      compare(entry.key, entry.value);
    }
    return changes;
  }
}