import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import 'unified_barcode_scanner.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../bloc/inventory_bloc.dart';

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
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _materialCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _quantityCtrl;
  DateTime? _productionDate;
  DateTime? _expireDate;
  final Map<String, TextEditingController> _customCtrls = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _codeCtrl = TextEditingController(text: item?.code ?? '');
    _barcodeCtrl = TextEditingController(text: item?.barcode ?? '');
    _colorCtrl = TextEditingController(text: item?.color ?? '');
    _materialCtrl = TextEditingController(text: item?.material ?? '');
    _sizeCtrl = TextEditingController(text: item?.size ?? '');
    _noteCtrl = TextEditingController(text: item?.note ?? '');
    _quantityCtrl = TextEditingController(text: (item?.quantity ?? 0).toString());
    _productionDate = item?.productionDate;
    _expireDate = item?.expireDate;
    for (final f in widget.settings?.customFieldNames ?? const []) {
      _customCtrls[f] = TextEditingController(text: item?.customFields[f] ?? '');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _barcodeCtrl.dispose();
    _colorCtrl.dispose();
    _materialCtrl.dispose();
    _sizeCtrl.dispose();
    _noteCtrl.dispose();
    _quantityCtrl.dispose();
    for (final c in _customCtrls.values) { c.dispose(); }
    super.dispose();
  }

  bool _enabled(String f) => widget.settings?.isFieldEnabled(f) ?? ['Name', 'Code', 'Barcode', 'Size', 'Quantity', 'Note'].contains(f);
  bool _required(String f) => widget.settings?.isFieldRequired(f) ?? (f == 'Name' || f == 'Quantity');

  void _scan() {
    UnifiedBarcodeScanner.showScanner(
      context,
      onBarcodeScanned: (b) {
        if (mounted) {
          setState(() { _barcodeCtrl.text = b; _error = null; });
          SnackBarUtils.success(context, 'Barcode scanned: $b');
        }
      },
    );
  }

  void _clearBarcode() {
    setState(() { _barcodeCtrl.clear(); _error = null; });
  }

  String _uid() {
    try { return context.read<AuthBloc>().state.user?.id ?? 'unknown'; } catch (_) { return 'unknown'; }
  }

  String _uname() {
    try { return context.read<AuthBloc>().state.user?.displayNameOrEmail ?? 'Unknown'; } catch (_) { return 'Unknown'; }
  }

  @override
  Widget build(BuildContext c) {
    final editing = widget.existingItem != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(c).viewInsets.bottom + 28,
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
                  decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                editing ? 'Edit Item' : 'Add New Item to ${widget.label}',
                style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ],
              const SizedBox(height: 16),

              // --- Fields (identical to previous, removed for brevity but keep all) ---
              if (_enabled('Name'))
                _tf(ctrl: _nameCtrl, label: 'Name', hint: 'Enter item name', icon: Icons.label, required: _required('Name'), cap: TextCapitalization.words, autofocus: true, maxLen: 200),
              if (_enabled('Code'))
                _tf(ctrl: _codeCtrl, label: 'Code', hint: 'Enter item code', icon: Icons.code, required: _required('Code'), maxLen: 100),
              if (_enabled('Barcode'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _barcodeCtrl,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: _required('Barcode') ? 'Barcode *' : 'Barcode',
                      hintText: 'Enter barcode manually or scan',
                      prefixIcon: const Icon(Icons.qr_code, size: 20),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_barcodeCtrl.text.isNotEmpty)
                          IconButton(icon: const Icon(Icons.clear, size: 20), tooltip: 'Clear', onPressed: _clearBarcode),
                        IconButton(icon: Icon(Icons.qr_code_scanner, size: 20, color: Theme.of(c).colorScheme.primary), tooltip: 'Scan', onPressed: _scan),
                      ]),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                      counterText: '',
                    ),
                    validator: _required('Barcode') ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
                  ),
                ),
              if (_enabled('Color'))
                _tf(ctrl: _colorCtrl, label: 'Color', hint: 'Enter color', icon: Icons.color_lens, required: _required('Color'), cap: TextCapitalization.words),
              if (_enabled('Material'))
                _tf(ctrl: _materialCtrl, label: 'Material', hint: 'Enter material', icon: Icons.texture, required: _required('Material'), cap: TextCapitalization.words),
              if (_enabled('Size'))
                _tf(ctrl: _sizeCtrl, label: 'Size', hint: 'Enter size (e.g., S, M, L)', icon: Icons.straighten, required: _required('Size')),
              if (_enabled('Quantity'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _quantityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _required('Quantity') ? 'Quantity *' : 'Quantity',
                      hintText: '0-${InventoryItem.maxQuantity}',
                      prefixIcon: const Icon(Icons.numbers, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                    ),
                    validator: (v) {
                      if (_required('Quantity') && (v == null || v.trim().isEmpty)) return 'Required';
                      if (v == null || v.trim().isEmpty) return null;
                      final p = int.tryParse(v.trim());
                      if (p == null) return 'Invalid number';
                      if (p < 0 || p > InventoryItem.maxQuantity) return '0-${InventoryItem.maxQuantity}';
                      return null;
                    },
                  ),
                ),
              if (_enabled('Production Date'))
                _df(label: 'Production Date', required: _required('Production Date'), value: _productionDate, onPick: (d) => setState(() => _productionDate = d), onClear: () => setState(() => _productionDate = null)),
              if (_enabled('Expire Date'))
                _df(label: 'Expire Date', required: _required('Expire Date'), value: _expireDate, onPick: (d) => setState(() => _expireDate = d), onClear: () => setState(() => _expireDate = null)),
              if (_enabled('Note'))
                _tf(ctrl: _noteCtrl, label: 'Note', hint: 'Enter notes', icon: Icons.note, maxLines: 3, required: _required('Note'), cap: TextCapitalization.sentences),
              ..._customCtrls.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: e.value,
                      decoration: InputDecoration(
                        labelText: e.key, hintText: 'Enter ${e.key}',
                        prefixIcon: const Icon(Icons.edit_note, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  )),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(c),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40))),
                    child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing ? 'Update' : 'Save', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── FIXED _submit with mounted checks before using context ───
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() { _saving = true; _error = null; });

    try {
      final cf = <String, String>{};
      for (final e in _customCtrls.entries) {
        final v = e.value.text.trim();
        if (v.isNotEmpty) cf[e.key] = v;
      }

      final editing = widget.existingItem != null;
      final uid = _uid();
      final uname = _uname();
      final now = DateTime.now();

      if (editing) {
        final old = widget.existingItem!;
        final ov = _captureOld(old);
        old.name = _nameCtrl.text.trim();
        old.code = _enabled('Code') ? _codeCtrl.text.trim() : '';
        old.barcode = _enabled('Barcode') ? _barcodeCtrl.text.trim() : '';
        old.color = _enabled('Color') ? _colorCtrl.text.trim() : '';
        old.material = _enabled('Material') ? _materialCtrl.text.trim() : '';
        old.size = _enabled('Size') ? _sizeCtrl.text.trim() : '';
        old.productionDate = _enabled('Production Date') ? _productionDate : null;
        old.expireDate = _enabled('Expire Date') ? _expireDate : null;
        old.note = _enabled('Note') ? _noteCtrl.text.trim() : '';
        old.quantity = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
        old.label = widget.label;
        old.customFields = cf;
        old.modified = now;
        old.updatedBy = uid;
        old.updatedByName = uname;
        await old.save();

        // Sync edit to Supabase – guard context use
        if (!mounted) return;
        final inventoryService = context.read<InventoryBloc>().inventoryService;
        await inventoryService.saveItem(old);

        final ch = _detectChanges(ov, old, cf);
        if (ch.isNotEmpty) {
          await ActivityLogService().addLog(ActivityLogEntry(
            id: const Uuid().v4(), timestamp: now, action: 'modified',
            entityType: 'item', entityName: old.displayName,
            inventoryId: widget.inventoryId, inventoryName: widget.inventoryName,
            labelName: widget.label, details: 'Modified by $uname', changes: ch,
          ));
        }
      } else {
        final item = InventoryItem(
          name: _nameCtrl.text.trim(),
          code: _enabled('Code') ? _codeCtrl.text.trim() : '',
          barcode: _enabled('Barcode') ? _barcodeCtrl.text.trim() : '',
          color: _enabled('Color') ? _colorCtrl.text.trim() : '',
          material: _enabled('Material') ? _materialCtrl.text.trim() : '',
          size: _enabled('Size') ? _sizeCtrl.text.trim() : '',
          productionDate: _enabled('Production Date') ? _productionDate : null,
          expireDate: _enabled('Expire Date') ? _expireDate : null,
          note: _enabled('Note') ? _noteCtrl.text.trim() : '',
          quantity: int.tryParse(_quantityCtrl.text.trim()) ?? 0,
          label: widget.label,
          customFields: cf,
          modified: now,
          createdAt: now,
          createdBy: uid,
          createdByName: uname,
        );
        await widget.onSave(item);
        await ActivityLogService().addLog(ActivityLogEntry(
          id: const Uuid().v4(), timestamp: item.createdAt, action: 'created',
          entityType: 'item', entityName: item.displayName,
          inventoryId: widget.inventoryId, inventoryName: widget.inventoryName,
          labelName: widget.label, details: 'Created by $uname with qty ${item.quantity}',
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; _error = 'Error: $e'; });
        SnackBarUtils.error(context, 'Error saving item: $e');
      }
    }
  }

  Map<String, String> _captureOld(InventoryItem i) => {
    'name': i.name, 'code': i.code, 'barcode': i.barcode,
    'color': i.color, 'material': i.material, 'size': i.size,
    'productionDate': i.productionDate?.toIso8601String() ?? '',
    'expireDate': i.expireDate?.toIso8601String() ?? '',
    'note': i.note, 'quantity': i.quantity.toString(), 'label': i.label,
    ...i.customFields,
  };

  Map<String, FieldChange> _detectChanges(Map<String, String> ov, InventoryItem ni, Map<String, String> ncf) {
    final ch = <String, FieldChange>{};
    void cmp(String k, String nv) { if (ov[k] != nv) ch[k] = FieldChange(oldValue: ov[k] ?? '', newValue: nv); }
    cmp('name', ni.name); cmp('code', ni.code); cmp('barcode', ni.barcode);
    cmp('color', ni.color); cmp('material', ni.material); cmp('size', ni.size);
    cmp('productionDate', ni.productionDate?.toIso8601String() ?? '');
    cmp('expireDate', ni.expireDate?.toIso8601String() ?? '');
    cmp('note', ni.note); cmp('quantity', ni.quantity.toString()); cmp('label', ni.label);
    for (final e in ncf.entries) { cmp(e.key, e.value); }
    return ch;
  }

  Widget _tf({required TextEditingController ctrl, required String label, required String hint, required IconData icon, bool required = false, int maxLines = 1, int? maxLen, TextInputType? kb, TextCapitalization cap = TextCapitalization.none, bool autofocus = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl, maxLines: maxLines, maxLength: maxLen, keyboardType: kb, textCapitalization: cap, autofocus: autofocus, enabled: enabled,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label, hintText: hint, prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, counterText: '',
        ),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
      ),
    );
  }

  Widget _df({required String label, required bool required, required DateTime? value, required Function(DateTime) onPick, required VoidCallback onClear}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FormField<DateTime?>(
        initialValue: value,
        validator: required ? (v) => v == null ? '$label is required' : null : null,
        builder: (s) => InkWell(
          onTap: () async {
            try {
              final p = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (p != null && mounted) { onPick(p); s.didChange(p); }
            } catch (_) {}
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              suffixIcon: value != null ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { onClear(); s.didChange(null); }) : null,
              errorText: s.errorText,
            ),
            child: Text(value != null ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}' : 'Select date', style: TextStyle(color: value != null ? null : Colors.grey, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}