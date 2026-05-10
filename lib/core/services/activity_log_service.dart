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
  static final ActivityLogService _instance = ActivityLogService._internal();
  
  factory ActivityLogService() => _instance;
  ActivityLogService._internal();

  Box? _logBox;

  Future<void> initialize() async {
    if (Hive.isBoxOpen(_logBoxName)) {
      _logBox = Hive.box(_logBoxName);
    } else {
      _logBox = await Hive.openBox(_logBoxName);
    }
    if (!_logBox!.containsKey(_logKey)) {
      await _logBox!.put(_logKey, <String>[]);
    }
  }

  List<ActivityLogEntry> getLogs({String? inventoryId, String? entityType}) {
    if (_logBox == null) return [];
    
    final rawLogs = _logBox!.get(_logKey, defaultValue: <String>[]) as List;
    final logs = <ActivityLogEntry>[];
    for (final json in rawLogs) {
      try {
        logs.add(ActivityLogEntry.fromJson(jsonDecode(json)));
      } catch (e) {
        debugPrint('Error parsing log entry: $e');
      }
    }
    
    var filtered = logs;
    if (inventoryId != null) {
      filtered = filtered.where((log) => log.inventoryId == inventoryId).toList();
    }
    if (entityType != null) {
      filtered = filtered.where((log) => log.entityType == entityType).toList();
    }
    
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  Future<void> addLog(ActivityLogEntry entry) async {
    if (_logBox == null) await initialize();
    
    final rawLogs = (_logBox!.get(_logKey, defaultValue: <String>[]) as List).cast<String>();
    rawLogs.add(jsonEncode(entry.toJson()));
    await _logBox!.put(_logKey, rawLogs);
  }

  Future<void> clearLogs({String? inventoryId}) async {
    if (_logBox == null) return;
    
    if (inventoryId != null) {
      final logs = getLogs();
      final filteredLogs = logs
          .where((log) => log.inventoryId != inventoryId)
          .map((log) => jsonEncode(log.toJson()))
          .toList();
      await _logBox!.put(_logKey, filteredLogs);
    } else {
      await _logBox!.put(_logKey, <String>[]);
    }
  }

  Future<String> exportLogsAsText({String? inventoryId}) async {
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
      final content = await exportLogsAsText(inventoryId: inventoryId);
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'activity_log_$timestamp.txt';
      final bytes = utf8.encode(content);

      if (kIsWeb) {
        downloadFileWeb(bytes, fileName, 'text/plain');
        return 'web_download';
      }

      try {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsString(content);
        return filePath;
      } catch (e) {
        final tempDir = Directory.systemTemp;
        final tempPath = '${tempDir.path}/$fileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsString(content);
        return tempPath;
      }
    } catch (e) {
      debugPrint('Error saving activity log: $e');
      return null;
    }
  }

  Map<String, dynamic> getStatistics({String? inventoryId}) {
    final logs = getLogs(inventoryId: inventoryId);
    
    final stats = <String, dynamic>{
      'totalLogs': logs.length,
      'created': 0,
      'modified': 0,
      'deleted': 0,
      'byType': <String, int>{},
    };

    for (final log in logs) {
      if (log.action == 'created') {
        stats['created'] = (stats['created'] as int) + 1;
      } else if (log.action == 'modified') {
        stats['modified'] = (stats['modified'] as int) + 1;
      } else if (log.action == 'deleted') {
        stats['deleted'] = (stats['deleted'] as int) + 1;
      }

      final byType = stats['byType'] as Map<String, int>;
      byType[log.entityType] = (byType[log.entityType] ?? 0) + 1;
    }

    return stats;
  }
}