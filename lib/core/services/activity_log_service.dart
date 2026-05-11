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

  /// Maximum number of log entries retained. Oldest entries are pruned first.
  static const int _maxLogEntries = 2000;

  static final ActivityLogService _instance = ActivityLogService._internal();
  factory ActivityLogService() => _instance;
  ActivityLogService._internal();

  Box? _logBox;

  // In-memory cache so getLogs() doesn't re-deserialise on every call.
  List<ActivityLogEntry>? _cache;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Initialises the service. Safe to call multiple times.
  Future<void> initialize() async {
    if (_logBox != null && _logBox!.isOpen) return;
    _logBox = Hive.isBoxOpen(_logBoxName)
        ? Hive.box(_logBoxName)
        : await Hive.openBox(_logBoxName);
    if (!_logBox!.containsKey(_logKey)) {
      await _logBox!.put(_logKey, <String>[]);
    }
    _cache = null; // invalidate cache after open
  }

  /// Returns the singleton after guaranteeing initialisation.
  /// Prefer this over the default constructor in code that runs before
  /// the app-level initialize() call.
  static Future<ActivityLogService> getInstance() async {
    await _instance.initialize();
    return _instance;
  }

  // Ensures the box is open before any operation.
  Future<void> _ensureInitialised() async {
    if (_logBox == null || !_logBox!.isOpen) await initialize();
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns all logs, optionally filtered, sorted newest-first.
  /// Uses an in-memory cache — only deserialises from Hive when the cache
  /// is stale (after a write).
  List<ActivityLogEntry> getLogs({String? inventoryId, String? entityType}) {
    if (_logBox == null) return [];

    // Populate cache if empty.
    if (_cache == null) {
      final raw =
          (_logBox!.get(_logKey, defaultValue: <String>[]) as List);
      final parsed = <ActivityLogEntry>[];
      for (final json in raw) {
        try {
          parsed.add(ActivityLogEntry.fromJson(jsonDecode(json as String)));
        } catch (e) {
          // Skip malformed entries rather than crashing.
          debugPrint('ActivityLogService: skipping malformed entry: $e');
        }
      }
      parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cache = parsed;
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

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  Future<void> addLog(ActivityLogEntry entry) async {
    await _ensureInitialised();

    // Copy — never mutate the list returned by Hive directly.
    final rawLogs = List<String>.from(
      _logBox!.get(_logKey, defaultValue: <String>[]) as List,
    );
    rawLogs.add(jsonEncode(entry.toJson()));

    // Prune oldest entries if we exceed the cap.
    if (rawLogs.length > _maxLogEntries) {
      rawLogs.removeRange(0, rawLogs.length - _maxLogEntries);
    }

    await _logBox!.put(_logKey, rawLogs);
    _cache = null; // invalidate cache
  }

  Future<void> clearLogs({String? inventoryId}) async {
    await _ensureInitialised();

    if (inventoryId != null) {
      // Work directly on the raw strings to avoid a full deserialise/serialise
      // round-trip when we only need to filter by inventoryId.
      final rawLogs = List<String>.from(
        _logBox!.get(_logKey, defaultValue: <String>[]) as List,
      );
      final kept = rawLogs.where((json) {
        try {
          final decoded = jsonDecode(json) as Map<String, dynamic>;
          return decoded['inventoryId'] != inventoryId;
        } catch (_) {
          return true; // keep unparseable entries to avoid data loss
        }
      }).toList();
      await _logBox!.put(_logKey, kept);
    } else {
      await _logBox!.put(_logKey, <String>[]);
    }
    _cache = null;
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Builds a human-readable text representation of the logs.
  /// Not async — no I/O happens here.
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

  /// Saves the log to a user-accessible file and returns the saved path,
  /// or null on failure.
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

      String savedPath;

      if (Platform.isAndroid) {
        // App-scoped external directory: writable on all Android versions
        // without runtime permissions.
        // Visible at: /sdcard/Android/data/<package>/files/
        final dir = await getExternalStorageDirectory();
        if (dir == null) throw Exception('External storage unavailable');
        savedPath = '${dir.path}/$fileName';
      } else if (Platform.isWindows) {
        final downloadsDir = Directory(
            '${Platform.environment['USERPROFILE']}\\Downloads');
        final dir = await downloadsDir.exists()
            ? downloadsDir
            : Directory.systemTemp;
        savedPath = '${dir.path}\\$fileName';
      } else {
        // macOS / Linux / iOS
        final downloadsDir =
            Directory('${Platform.environment['HOME']}/Downloads');
        final dir = Platform.isIOS || !await downloadsDir.exists()
            ? await getApplicationDocumentsDirectory()
            : downloadsDir;
        savedPath = '${dir.path}/$fileName';
      }

      await File(savedPath).writeAsString(content);
      return savedPath;
    } catch (e) {
      debugPrint('ActivityLogService.saveLogsToFile error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  Map<String, dynamic> getStatistics({String? inventoryId}) {
    final logs = getLogs(inventoryId: inventoryId);

    // Use a generic action map so no action type is silently ignored.
    final byAction = <String, int>{};
    final byType = <String, int>{};

    for (final log in logs) {
      byAction[log.action] = (byAction[log.action] ?? 0) + 1;
      byType[log.entityType] = (byType[log.entityType] ?? 0) + 1;
    }

    return {
      'totalLogs': logs.length,
      // Keep named keys for backward compatibility with any existing UI.
      'created': byAction['created'] ?? 0,
      'modified': byAction['modified'] ?? 0,
      'deleted': byAction['deleted'] ?? 0,
      'byAction': byAction,
      'byType': byType,
    };
  }
}