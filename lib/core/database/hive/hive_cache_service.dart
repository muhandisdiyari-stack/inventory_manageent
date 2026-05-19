import 'package:hive_flutter/hive_flutter.dart';
import '../../models/base_entity.dart';

class HiveCacheService {
  Future<void> cacheEntity<T extends BaseEntity>(
    String boxName,
    String key,
    T entity,
  ) async {
    final box = await Hive.openBox(boxName);
    entity.isSynced = false;
    await box.put(key, entity.toLocalJson());
  }

  Future<T?> getCachedEntity<T extends BaseEntity>(
    String boxName,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final box = await Hive.openBox(boxName);
    final data = box.get(key);
    if (data is Map) {
      return fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  Future<List<T>> getCachedEntitiesByCompany<T extends BaseEntity>(
    String boxName,
    String companyId,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final box = await Hive.openBox(boxName);
    final entities = <T>[];
    for (var key in box.keys) {
      final data = box.get(key);
      if (data is Map) {
        final entity = fromJson(Map<String, dynamic>.from(data));
        if (entity.companyId == companyId && !entity.isDeleted) {
          entities.add(entity);
        }
      }
    }
    return entities;
  }

  Future<void> markSynced(String boxName, String key) async {
    final box = await Hive.openBox(boxName);
    final data = box.get(key);
    if (data is Map) {
      final updatedData = Map<String, dynamic>.from(data);
      updatedData['isSynced'] = true;
      await box.put(key, updatedData);
    }
  }

  Future<void> softDelete(String boxName, String key) async {
    final box = await Hive.openBox(boxName);
    final data = box.get(key);
    if (data is Map) {
      final updatedData = Map<String, dynamic>.from(data);
      updatedData['isDeleted'] = true;
      updatedData['modifiedAt'] = DateTime.now().toIso8601String();
      await box.put(key, updatedData);
    }
  }
}