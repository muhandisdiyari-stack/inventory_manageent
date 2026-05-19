import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/activity_log_entry.dart';
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
    if (_cache == null) {
      _cache = _loadAllLogs();
    }

    var result = _cache!;
    
    if (inventoryId != null) {
      result = result.where((l) => l.inventoryId == inventoryId).toList();
    }
    if (entityType != null) {
      result = result.where((l) => l.entityType == entityType).toList();
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

    try {
      final rawLogs = List<String>.from(
        _logBox!.get(_logKey, defaultValue: <String>[]) as List,
      );
      
      rawLogs.add(jsonEncode(entry.toJson()));

      // Prune oldest entries if we exceed the cap
      while (rawLogs.length > _maxLogEntries) {
        rawLogs.removeAt(0);
      }

      await _logBox!.put(_logKey, rawLogs);
      
      // Update cache incrementally instead of invalidating
      _cache?.insert(0, entry);
      if (_cache != null && _cache!.length > _maxLogEntries) {
        _cache = _cache!.sublist(0, _maxLogEntries);
      }
    } catch (e) {
      debugPrint('Error adding log: $e');
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

  // ─── Export ────────────────────────────────────────────────────

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