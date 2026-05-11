// File: lib/features/inventory_management/services/demo_data_service.dart

import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/constants/app_constants.dart';

class DemoDataService {
  /// Loads sample demo data into the app.
  /// Only runs when [AppConstants.autoLoadDemoData] is true.
  static Future<void> loadDemoData() async {
    if (!AppConstants.autoLoadDemoData) return;

    final inventoriesBox = Hive.box(AppConstants.inventoriesListBox);
    if (inventoriesBox.isNotEmpty) return;

    // FIX (bug): millisecondsSinceEpoch + 1 can collide on fast hardware.
    // Use a large fixed offset that guarantees two distinct values regardless
    // of execution speed. A UUID library would be even safer if already a
    // dependency, but this is sufficient without adding a new package.
    final now = DateTime.now().millisecondsSinceEpoch;
    final warehouseId = '${now}_warehouse';
    final storeId = '${now}_store';

    await inventoriesBox.put(warehouseId, {
      'name': 'Main Warehouse',
      'created': DateTime.now().toIso8601String(),
    });

    await inventoriesBox.put(storeId, {
      'name': 'Retail Store',
      'created': DateTime.now().toIso8601String(),
    });

    await _initInventoryBoxes(warehouseId);
    await _initInventoryBoxes(storeId);

    await _addWarehouseItems(warehouseId);
    await _addStoreItems(storeId);

    await _addDemoSettings(warehouseId);
    await _addDemoSettings(storeId);
  }

  static Future<void> _initInventoryBoxes(String inventoryId) async {
    final labelsBox = await Hive.openBox('labels_$inventoryId');
    if (!labelsBox.containsKey('labels')) {
      await labelsBox.put('labels', <String>[]);
    }

    await Hive.openBox<InventoryItem>('items_$inventoryId');

    final settingsBox =
        await Hive.openBox<InventorySettings>('inventory_settings_$inventoryId');
    if (!settingsBox.containsKey('main')) {
      await settingsBox.put('main', InventorySettings());
    }
  }

  static Future<void> _addWarehouseItems(String inventoryId) async {
    final itemsBox = Hive.box<InventoryItem>('items_$inventoryId');
    final labelsBox = Hive.box('labels_$inventoryId');

    final labels = ['Electronics', 'Furniture', 'Packaging', 'Raw Materials'];
    await labelsBox.put('labels', labels);

    final warehouseItems = [
      InventoryItem(
        name: 'Wireless Keyboard',
        code: 'WKB-001',
        barcode: '8901234567890',
        quantity: 150,
        label: 'Electronics',
        color: 'Black',
        material: 'Plastic',
        size: 'Standard',
        note: 'Ergonomic design with wrist rest',
        expireDate: DateTime.now().add(const Duration(days: 365)),
        customFields: {
          'Supplier': 'TechGear Inc.',
          'Location': 'Aisle 3, Shelf B',
          'Min Stock': '50',
        },
      ),
      InventoryItem(
        name: 'Office Chair',
        code: 'FRN-002',
        barcode: '8901234567891',
        quantity: 25,
        label: 'Furniture',
        color: 'Gray',
        material: 'Mesh',
        size: 'Large',
        note: 'Adjustable height with lumbar support',
        expireDate: DateTime.now().add(const Duration(days: 730)),
        customFields: {
          'Supplier': 'OfficeMax Co.',
          'Location': 'Section D',
          'Min Stock': '10',
        },
      ),
      InventoryItem(
        name: 'Cardboard Box (Medium)',
        code: 'PKG-003',
        barcode: '8901234567892',
        quantity: 500,
        label: 'Packaging',
        color: 'Brown',
        material: 'Corrugated Cardboard',
        size: 'Medium',
        note: 'Double wall for extra strength',
        customFields: {
          'Supplier': 'PackRight Ltd.',
          'Location': 'Storage Room 1',
          'Min Stock': '200',
        },
      ),
      InventoryItem(
        name: 'Steel Rods',
        code: 'RAW-004',
        barcode: '8901234567893',
        quantity: 1000,
        label: 'Raw Materials',
        color: 'Silver',
        material: 'Stainless Steel',
        size: '2m Length',
        note: 'Grade 304 stainless steel',
        customFields: {
          'Supplier': 'MetalWorks Inc.',
          'Location': 'Yard A',
          'Min Stock': '500',
        },
      ),
      InventoryItem(
        name: 'USB-C Cable',
        code: 'ELC-005',
        barcode: '8901234567894',
        quantity: 75,
        label: 'Electronics',
        color: 'White',
        material: 'PVC',
        size: '1m',
        note: 'Fast charging compatible',
        expireDate: DateTime.now().add(const Duration(days: 15)),
        customFields: {
          'Supplier': 'TechGear Inc.',
          'Location': 'Aisle 1, Shelf A',
          'Min Stock': '100',
        },
      ),
      InventoryItem(
        name: 'Printer Paper',
        code: 'OFF-006',
        barcode: '8901234567895',
        quantity: 0,
        label: 'Packaging',
        color: 'White',
        material: 'A4 Paper',
        size: 'A4',
        note: 'Out of stock - Reorder urgently',
        expireDate: DateTime.now().subtract(const Duration(days: 30)),
        customFields: {
          'Supplier': 'OfficeMax Co.',
          'Location': 'Storage Room 2',
          'Min Stock': '50',
        },
      ),
    ];

    for (final item in warehouseItems) {
      await itemsBox.add(item);
    }
  }

  static Future<void> _addStoreItems(String inventoryId) async {
    final itemsBox = Hive.box<InventoryItem>('items_$inventoryId');
    final labelsBox = Hive.box('labels_$inventoryId');

    final labels = ['Clothing', 'Accessories', 'Shoes'];
    await labelsBox.put('labels', labels);

    final storeItems = [
      InventoryItem(
        name: 'Cotton T-Shirt',
        code: 'CLT-001',
        barcode: '8901234567896',
        quantity: 200,
        label: 'Clothing',
        color: 'White',
        material: '100% Cotton',
        size: 'M',
        note: 'Summer collection 2026',
        customFields: {
          'Brand': 'UrbanWear',
          'Price': '29.99',
          'Section': "Men's Wear",
        },
      ),
      InventoryItem(
        name: 'Leather Wallet',
        code: 'ACC-002',
        barcode: '8901234567897',
        quantity: 50,
        label: 'Accessories',
        color: 'Brown',
        material: 'Genuine Leather',
        size: 'Standard',
        note: 'Bestseller - Reorder soon',
        expireDate: DateTime.now().add(const Duration(days: 20)),
        customFields: {
          'Brand': 'LeatherCraft',
          'Price': '49.99',
          'Section': 'Accessories Wall',
        },
      ),
      InventoryItem(
        name: 'Running Shoes',
        code: 'SHO-003',
        barcode: '8901234567898',
        quantity: 30,
        label: 'Shoes',
        color: 'Black/Red',
        material: 'Mesh/Synthetic',
        size: '42 EU',
        note: 'Lightweight running shoes',
        customFields: {
          'Brand': 'SpeedRunner',
          'Price': '89.99',
          'Section': 'Footwear Aisle',
        },
      ),
    ];

    for (final item in storeItems) {
      await itemsBox.add(item);
    }
  }

  static Future<void> _addDemoSettings(String inventoryId) async {
    final settingsBox =
        Hive.box<InventorySettings>('inventory_settings_$inventoryId');

    final settings = InventorySettings(
      fieldConfigs: [
        FieldConfig(fieldName: 'Name', isEnabled: true, isRequired: true),
        FieldConfig(fieldName: 'Code', isEnabled: true, isRequired: false),
        FieldConfig(fieldName: 'Barcode', isEnabled: true, isRequired: false),
        FieldConfig(fieldName: 'Color', isEnabled: true, isRequired: false),
        FieldConfig(fieldName: 'Material', isEnabled: true, isRequired: false),
        FieldConfig(fieldName: 'Size', isEnabled: true, isRequired: false),
        FieldConfig(fieldName: 'Quantity', isEnabled: true, isRequired: true),
        FieldConfig(fieldName: 'Production Date', isEnabled: false, isRequired: false),
        FieldConfig(fieldName: 'Expire Date', isEnabled: true, isRequired: false),
        FieldConfig(fieldName: 'Note', isEnabled: true, isRequired: false),
      ],
      customFieldNames: ['Supplier', 'Location', 'Min Stock'],
    );

    await settingsBox.put('main', settings);
  }
}