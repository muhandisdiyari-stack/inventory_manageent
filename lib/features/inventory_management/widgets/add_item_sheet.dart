// lib/features/inventory_management/widgets/add_item_sheet.dart
import 'package:flutter/material.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import 'unified_barcode_scanner.dart';

class AddItemSheet {
  static void show(
    BuildContext context, {
    required String label,
    required InventorySettings? settings,
    required Future<void> Function(InventoryItem) onSave,
    InventoryItem? existingItem,
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
      ),
    );
  }
}

class _AddItemForm extends StatefulWidget {
  final String label;
  final InventorySettings? settings;
  final Future<void> Function(InventoryItem) onSave;
  final InventoryItem? existingItem;

  const _AddItemForm({
    required this.label,
    required this.settings,
    required this.onSave,
    this.existingItem,
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
    _quantityController = TextEditingController(text: (item?.quantity ?? 0).toString());
    _productionDate = item?.productionDate;
    _expireDate = item?.expireDate;
    
    // Initialize custom field controllers
    for (var fieldName in widget.settings?.customFieldNames ?? []) {
      _customFieldControllers[fieldName] = TextEditingController(
        text: item?.customFields[fieldName] ?? ''
      );
    }
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
    for (var controller in _customFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isFieldEnabled(String fieldName) {
    if (widget.settings == null) return true;
    final config = widget.settings!.fieldConfigs.firstWhere(
      (f) => f.fieldName == fieldName,
      orElse: () => FieldConfig(fieldName: fieldName, isEnabled: true, isRequired: false),
    );
    return config.isEnabled;
  }

  bool _isFieldRequired(String fieldName) {
    if (widget.settings == null) return fieldName == 'Name';
    return widget.settings!.isFieldRequired(fieldName);
  }

  void _openBarcodeScanner() {
    UnifiedBarcodeScanner.showScanner(
      context,
      onBarcodeScanned: (barcode) {
        setState(() {
          _barcodeController.text = barcode;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Barcode scanned: $barcode',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
              margin: const EdgeInsets.all(20),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  void _clearBarcode() {
    if (_barcodeController.text.isNotEmpty) {
      setState(() {
        _barcodeController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingItem != null;
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        left: 20, right: 20, top: 20,
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
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isEditing ? 'Edit Item' : 'Add New Item to ${widget.label}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              if (_isFieldEnabled('Name'))
                _buildTextField(
                  controller: _nameController,
                  label: 'Name *',
                  hint: 'Enter item name',
                  icon: Icons.label,
                  required: true,
                  textCapitalization: TextCapitalization.words,
                ),
              if (_isFieldEnabled('Code'))
                _buildTextField(
                  controller: _codeController,
                  label: _isFieldRequired('Code') ? 'Code *' : 'Code',
                  hint: 'Enter item code',
                  icon: Icons.code,
                  required: _isFieldRequired('Code'),
                ),
              if (_isFieldEnabled('Barcode'))
                _buildBarcodeField(),
              if (_isFieldEnabled('Color'))
                _buildTextField(
                  controller: _colorController,
                  label: _isFieldRequired('Color') ? 'Color *' : 'Color',
                  hint: 'Enter color',
                  icon: Icons.color_lens,
                  required: _isFieldRequired('Color'),
                  textCapitalization: TextCapitalization.words,
                ),
              if (_isFieldEnabled('Material'))
                _buildTextField(
                  controller: _materialController,
                  label: _isFieldRequired('Material') ? 'Material *' : 'Material',
                  hint: 'Enter material',
                  icon: Icons.texture,
                  required: _isFieldRequired('Material'),
                  textCapitalization: TextCapitalization.words,
                ),
              if (_isFieldEnabled('Size'))
                _buildTextField(
                  controller: _sizeController,
                  label: _isFieldRequired('Size') ? 'Size *' : 'Size',
                  hint: 'Enter size (e.g., S, M, L, XL)',
                  icon: Icons.straighten,
                  required: _isFieldRequired('Size'),
                ),
              if (_isFieldEnabled('Production Date'))
                _buildDateField(
                  label: _isFieldRequired('Production Date') ? 'Production Date *' : 'Production Date',
                  value: _productionDate,
                  onPicked: (d) => setState(() => _productionDate = d),
                  onClear: () => setState(() => _productionDate = null),
                ),
              if (_isFieldEnabled('Expire Date'))
                _buildDateField(
                  label: _isFieldRequired('Expire Date') ? 'Expire Date *' : 'Expire Date',
                  value: _expireDate,
                  onPicked: (d) => setState(() => _expireDate = d),
                  onClear: () => setState(() => _expireDate = null),
                ),
              _buildTextField(
                controller: _quantityController,
                label: 'Quantity',
                hint: 'Enter quantity',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                required: false,
              ),
              if (_isFieldEnabled('Note'))
                _buildTextField(
                  controller: _noteController,
                  label: _isFieldRequired('Note') ? 'Note *' : 'Note',
                  hint: 'Enter notes or description',
                  icon: Icons.note,
                  maxLines: 3,
                  required: _isFieldRequired('Note'),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ..._buildCustomFields(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isEditing ? 'Update' : 'Save',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
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

  Widget _buildBarcodeField() {
    final hasText = _barcodeController.text.isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _barcodeController,
        decoration: InputDecoration(
          labelText: _isFieldRequired('Barcode') ? 'Barcode *' : 'Barcode',
          hintText: 'Enter barcode manually',
          prefixIcon: const Icon(Icons.qr_code, size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: 'Clear barcode',
                  onPressed: _clearBarcode,
                ),
              IconButton(
                icon: Icon(
                  Icons.qr_code_scanner,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
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
        validator: _isFieldRequired('Barcode') 
            ? (v) => (v == null || v.trim().isEmpty) ? 'Barcode is required' : null 
            : null,
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          errorStyle: const TextStyle(fontSize: 12),
        ),
        validator: required 
            ? (v) {
                if (v == null || v.trim().isEmpty) {
                  return '${label.replaceAll(' *', '')} is required';
                }
                return null;
              } 
            : null,
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required Function(DateTime) onPicked,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            helpText: 'Select $label',
            cancelText: 'Cancel',
            confirmText: 'OK',
          );
          if (picked != null) onPicked(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            prefixIcon: const Icon(Icons.calendar_today, size: 18),
            suffixIcon: value != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear date',
                    onPressed: onClear,
                  )
                : null,
          ),
          child: Text(
            value != null 
                ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
                : 'Select date',
            style: TextStyle(
              color: value != null ? null : Colors.grey,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCustomFields() {
    if (widget.settings == null || widget.settings!.customFieldNames.isEmpty) {
      return [];
    }
    
    return widget.settings!.customFieldNames.map((fieldName) {
      if (!_customFieldControllers.containsKey(fieldName)) {
        _customFieldControllers[fieldName] = TextEditingController(
          text: widget.existingItem?.customFields[fieldName] ?? ''
        );
      }
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _customFieldControllers[fieldName],
          decoration: InputDecoration(
            labelText: fieldName,
            hintText: 'Enter $fieldName',
            prefixIcon: const Icon(Icons.edit_note, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
      );
    }).toList();
  }

  /// Submit handler that correctly handles both add and edit modes
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    
    try {
      // Build custom fields map
      final customFields = <String, String>{};
      for (var entry in _customFieldControllers.entries) {
        final value = entry.value.text.trim();
        if (value.isNotEmpty) {
          customFields[entry.key] = value;
        }
      }
      
      final isEditing = widget.existingItem != null;
      
      if (isEditing) {
        // EDITING: Mutate the existing HiveObject directly
        final item = widget.existingItem!;
        item.name = _nameController.text.trim();
        item.code = _isFieldEnabled('Code') ? _codeController.text.trim() : '';
        item.barcode = _isFieldEnabled('Barcode') ? _barcodeController.text.trim() : '';
        item.color = _isFieldEnabled('Color') ? _colorController.text.trim() : '';
        item.material = _isFieldEnabled('Material') ? _materialController.text.trim() : '';
        item.size = _isFieldEnabled('Size') ? _sizeController.text.trim() : '';
        item.productionDate = _isFieldEnabled('Production Date') ? _productionDate : null;
        item.expireDate = _isFieldEnabled('Expire Date') ? _expireDate : null;
        item.note = _isFieldEnabled('Note') ? _noteController.text.trim() : '';
        item.quantity = int.tryParse(_quantityController.text) ?? 0;
        item.label = widget.label;
        item.customFields = customFields;
        item.modified = DateTime.now();
      } else {
        // ADDING: Create a new item
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
          quantity: int.tryParse(_quantityController.text) ?? 0,
          label: widget.label,
          customFields: customFields,
          modified: DateTime.now(),
        );
        
        // Pass to parent for saving
        await widget.onSave(item);
      }
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Error saving item: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}