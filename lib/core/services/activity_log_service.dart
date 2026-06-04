import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/activity_log_entry.dart';
import '../config/app_config.dart';
import '../utils/file_export.dart';

class ActivityLogService {
  static const String _logBoxName = 'activity_logs';
  static const String _logKey = 'all_logs';
  static const int _maxLogEntries = 2000;

  static final ActivityLogService _instance = ActivityLogService._internal();
  factory ActivityLogService() => _instance;
  ActivityLogService._internal();

  Box? _logBox;
  List<ActivityLogEntry>? _cache;
  bool _initialized = false;

  // ─── Initialization ─────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized && _logBox != null && _logBox!.isOpen) return;

    try {
      _logBox = Hive.isBoxOpen(_logBoxName)
          ? Hive.box(_logBoxName)
          : await Hive.openBox(_logBoxName);

      if (!_logBox!.containsKey(_logKey)) {
        await _logBox!.put(_logKey, <String>[]);
      }

      _initialized = true;
      _cache = null; // Force reload on next read
    } catch (e) {
      debugPrint('ActivityLogService initialization error: $e');
      // Try to recover corrupted box
      try {
        await Hive.deleteBoxFromDisk(_logBoxName);
        _logBox = await Hive.openBox(_logBoxName);
        await _logBox!.put(_logKey, <String>[]);
        _initialized = true;
      } catch (e2) {
        debugPrint('ActivityLogService recovery failed: $e2');
        _initialized = false;
      }
    }
  }

  static Future<ActivityLogService> getInstance() async {
    await _instance.initialize();
    return _instance;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized || _logBox == null || !_logBox!.isOpen) {
      await initialize();
    }
  }

  // ─── Read ──────────────────────────────────────────────────────

  List<ActivityLogEntry> getLogs({String? inventoryId, String? entityType}) {
    if (!_initialized || _logBox == null) return [];

    // Populate cache if empty
    _cache ??= _loadAllLogs();

    var result = _cache!;

    if (inventoryId != null) {
      result =
          result.where((l) => l.inventoryId == inventoryId).toList();
    }
    if (entityType != null) {
      result =
          result.where((l) => l.entityType == entityType).toList();
    }

    return result;
  }

  List<ActivityLogEntry> _loadAllLogs() {
    if (_logBox == null) return [];

    try {
      final raw = _logBox!.get(_logKey, defaultValue: <String>[]) as List;
      final parsed = <ActivityLogEntry>[];

      for (final json in raw) {
        try {
          if (json is String && json.isNotEmpty) {
            parsed.add(ActivityLogEntry.fromJson(jsonDecode(json)));
          }
        } catch (e) {
          // Skip malformed entries
        }
      }

      parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return parsed;
    } catch (e) {
      debugPrint('Error loading logs: $e');
      return [];
    }
  }

  // ─── Write ─────────────────────────────────────────────────────

  Future<void> addLog(ActivityLogEntry entry) async {
    await _ensureInitialized();
    if (_logBox == null) return;

    // Ensure entry has a valid UUID for database sync
    final logEntry = entry.id.isEmpty || !_isValidUUID(entry.id)
        ? ActivityLogEntry(
            id: const Uuid().v4(),
            timestamp: entry.timestamp,
            action: entry.action,
            entityType: entry.entityType,
            entityName: entry.entityName,
            inventoryId: entry.inventoryId,
            inventoryName: entry.inventoryName,
            labelName: entry.labelName,
            details: entry.details,
            changes: entry.changes,
          )
        : entry;

    try {
      final rawLogs = List<String>.from(
        _logBox!.get(_logKey, defaultValue: <String>[]) as List,
      );

      rawLogs.add(jsonEncode(logEntry.toJson()));

      // Prune oldest entries if we exceed the cap
      while (rawLogs.length > _maxLogEntries) {
        rawLogs.removeAt(0);
      }

      await _logBox!.put(_logKey, rawLogs);

      // Update cache incrementally
      _cache?.insert(0, logEntry);
      if (_cache != null && _cache!.length > _maxLogEntries) {
        _cache = _cache!.sublist(0, _maxLogEntries);
      }

      // Sync to Supabase if enabled
      await _syncLogToSupabase(logEntry);
    } catch (e) {
      debugPrint('Error adding log: $e');
    }
  }

  /// Check if a string is a valid UUID format
  bool _isValidUUID(String value) {
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(value);
  }

  /// Sync a single log entry to Supabase for cross-device visibility.
  /// Sync a single log entry to Supabase for cross-device visibility.
  Future<void> _syncLogToSupabase(ActivityLogEntry entry) async {
    if (!AppConfig.useSupabase) return;

    try {
      // Get the actual company_id from the inventory
      String? companyId;
      if (entry.inventoryId != null) {
        try {
          final data = await Supabase.instance.client
              .from('inventories')
              .select('company_id')
              .eq('id', entry.inventoryId!)
              .maybeSingle();
          companyId = data?['company_id']?.toString();
        } catch (_) {
          debugPrint('⚠️ Could not fetch company_id for inventory ${entry.inventoryId}');
        }
      }

      // Don't send the id field - let Supabase generate the UUID
      await Supabase.instance.client.from('activity_log').insert({
        'company_id': companyId,
        'inventory_id': entry.inventoryId,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'user_name': Supabase.instance.client.auth.currentUser?.userMetadata?['display_name'],
        'action': entry.action,
        'entity_type': entry.entityType,
        'entity_name': entry.entityName,
        'label_name': entry.labelName,
        'details': entry.details,
        'changes': entry.changes?.map(
            (key, value) => MapEntry(key, value.toJson())),
        'created_at': entry.timestamp.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Activity log sync to Supabase failed: $e');
    }
  }

  /// Fetch activity logs from Supabase and merge with local.
  Future<void> syncLogsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;

    try {
      final data = await Supabase.instance.client
          .from('activity_log')
          .select()
          .eq('inventory_id', inventoryId)
          .order('created_at', ascending: false)
          .limit(_maxLogEntries);

      await _ensureInitialized();
      if (_logBox == null) return;

      final rawLogs = List<String>.from(
        _logBox!.get(_logKey, defaultValue: <String>[]) as List,
      );

      // Track existing IDs to avoid duplicates
      final existingIds = <String>{};
      for (final raw in rawLogs) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          existingIds.add(decoded['id'] as String);
        } catch (_) {}
      }

      // Add new entries from Supabase
      for (final row in data) {
        final id = row['id']?.toString() ?? '';
        if (existingIds.contains(id)) continue;

        final entry = ActivityLogEntry(
          id: id,
          timestamp: row['created_at'] != null
              ? DateTime.parse(row['created_at'] as String)
              : DateTime.now(),
          action: row['action'] as String? ?? 'modified',
          entityType: row['entity_type'] as String? ?? 'unknown',
          entityName: row['entity_name'] as String? ?? 'Unknown',
          inventoryId: row['inventory_id'] as String?,
          labelName: row['label_name'] as String?,
          details: row['details'] as String?,
        );

        rawLogs.add(jsonEncode(entry.toJson()));
      }

      // Prune if over limit
      while (rawLogs.length > _maxLogEntries) {
        rawLogs.removeAt(0);
      }

      await _logBox!.put(_logKey, rawLogs);
      _cache = null; // Force cache refresh
    } catch (e) {
      debugPrint('Activity log sync from Supabase failed: $e');
    }
  }

  Future<void> clearLogs({String? inventoryId}) async {
    await _ensureInitialized();
    if (_logBox == null) return;

    try {
      if (inventoryId != null) {
        final rawLogs = List<String>.from(
          _logBox!.get(_logKey, defaultValue: <String>[]) as List,
        );

        final kept = rawLogs.where((json) {
          try {
            final decoded = jsonDecode(json) as Map<String, dynamic>;
            return decoded['inventoryId'] != inventoryId;
          } catch (_) {
            return true; // Keep unparseable entries
          }
        }).toList();

        await _logBox!.put(_logKey, kept);
      } else {
        await _logBox!.put(_logKey, <String>[]);
      }

      _cache = null; // Full cache invalidation needed
    } catch (e) {
      debugPrint('Error clearing logs: $e');
    }
  }

  // ─── Convenience Methods ────────────────────────────────────────

  /// Quick log for item creation
  Future<void> logItemCreated({
    required String itemName,
    required String inventoryId,
    required String inventoryName,
    required String labelName,
    required String createdBy,
  }) async {
    await addLog(ActivityLogEntry(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      action: 'created',
      entityType: 'item',
      entityName: itemName,
      inventoryId: inventoryId,
      inventoryName: inventoryName,
      labelName: labelName,
      details: 'Item created by $createdBy: "$itemName"',
    ));
  }

  /// Quick log for item modification
  Future<void> logItemModified({
    required String itemName,
    required String inventoryId,
    required String inventoryName,
    required String labelName,
    required String modifiedBy,
    Map<String, FieldChange>? changes,
  }) async {
    await addLog(ActivityLogEntry(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      action: 'modified',
      entityType: 'item',
      entityName: itemName,
      inventoryId: inventoryId,
      inventoryName: inventoryName,
      labelName: labelName,
      details: 'Item modified by $modifiedBy: "$itemName"',
      changes: changes,
    ));
  }

  // ─── Export (unchanged) ────────────────────────────────────────

  String exportLogsAsText({String? inventoryId}) {
    final logs = getLogs(inventoryId: inventoryId);
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════════════════');
    buffer.writeln('  INVENTORY PRO - ACTIVITY LOG');
    buffer.writeln('  Generated: ${DateTime.now().toIso8601String()}');
    if (inventoryId != null) {
      buffer.writeln('  Filtered by Inventory ID: $inventoryId');
    }
    buffer.writeln('  Total Entries: ${logs.length}');
    buffer.writeln('═══════════════════════════════════════════════════');
    buffer.writeln();

    if (logs.isEmpty) {
      buffer.writeln('No activity recorded yet.');
    } else {
      for (final log in logs) {
        buffer.write(log.toFormattedString());
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  Future<String?> saveLogsToFile({String? inventoryId}) async {
    try {
      final content = exportLogsAsText(inventoryId: inventoryId);
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.T]'), '-')
          .substring(0, 19);
      final fileName = 'activity_log_$timestamp.txt';
      final bytes = utf8.encode(content);

      if (kIsWeb) {
        downloadFileWeb(bytes, fileName, 'text/plain');
        return 'web_download';
      }

      String? savedPath;

      if (Platform.isAndroid) {
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          savedPath = '${dir.path}/$fileName';
          await File(savedPath).writeAsBytes(bytes);
        }
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        savedPath = '${dir.path}/$fileName';
        await File(savedPath).writeAsBytes(bytes);
      } else if (Platform.isWindows) {
        final downloadsDir = Directory(
          '${Platform.environment['USERPROFILE']}\\Downloads',
        );
        if (await downloadsDir.exists()) {
          savedPath = '${downloadsDir.path}\\$fileName';
        } else {
          savedPath = '${Directory.systemTemp.path}\\$fileName';
        }
        await File(savedPath).writeAsBytes(bytes);
      } else {
        // macOS / Linux
        final homeDir = Platform.environment['HOME'] ?? '/tmp';
        final downloadsDir = Directory('$homeDir/Downloads');
        if (await downloadsDir.exists()) {
          savedPath = '${downloadsDir.path}/$fileName';
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          savedPath = '${appDir.path}/$fileName';
        }
        await File(savedPath).writeAsBytes(bytes);
      }

      return savedPath;
    } catch (e) {
      debugPrint('ActivityLogService.saveLogsToFile error: $e');
      return null;
    }
  }

  // ─── Statistics ────────────────────────────────────────────────

  Map<String, dynamic> getStatistics({String? inventoryId}) {
    final logs = getLogs(inventoryId: inventoryId);

    final byAction = <String, int>{};
    final byType = <String, int>{};

    for (final log in logs) {
      byAction[log.action] = (byAction[log.action] ?? 0) + 1;
      byType[log.entityType] = (byType[log.entityType] ?? 0) + 1;
    }

    return {
      'totalLogs': logs.length,
      'created': byAction['created'] ?? 0,
      'modified': byAction['modified'] ?? 0,
      'deleted': byAction['deleted'] ?? 0,
      'byAction': byAction,
      'byType': byType,
    };
  }
}