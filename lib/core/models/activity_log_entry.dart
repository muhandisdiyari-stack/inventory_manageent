/// Represents a single activity log entry with detailed change tracking.
class ActivityLogEntry {
  final String id;
  final DateTime timestamp;
  final String action; // 'created', 'modified', 'deleted'
  final String entityType; // 'inventory', 'label', 'item', 'settings'
  final String entityName;
  final String? inventoryId;
  final String? inventoryName;
  final String? labelName;
  final String? details;
  final Map<String, FieldChange>? changes; // old -> new values

  ActivityLogEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.entityType,
    required this.entityName,
    this.inventoryId,
    this.inventoryName,
    this.labelName,
    this.details,
    this.changes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'action': action,
      'entityType': entityType,
      'entityName': entityName,
      'inventoryId': inventoryId,
      'inventoryName': inventoryName,
      'labelName': labelName,
      'details': details,
      'changes': changes?.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ActivityLogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      action: json['action'] as String,
      entityType: json['entityType'] as String,
      entityName: json['entityName'] as String,
      inventoryId: json['inventoryId'] as String?,
      inventoryName: json['inventoryName'] as String?,
      labelName: json['labelName'] as String?,
      details: json['details'] as String?,
      changes: (json['changes'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, FieldChange.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('[$timestamp] $action - $entityType: $entityName');
    if (inventoryName != null) buffer.writeln('  Inventory: $inventoryName');
    if (labelName != null) buffer.writeln('  Label: $labelName');
    if (details != null) buffer.writeln('  Details: $details');
    if (changes != null && changes!.isNotEmpty) {
      buffer.writeln('  Changes:');
      for (final entry in changes!.entries) {
        buffer.writeln('    ${entry.key}: "${entry.value.oldValue}" → "${entry.value.newValue}"');
      }
    }
    buffer.writeln('---');
    return buffer.toString();
  }
}

class FieldChange {
  final String oldValue;
  final String newValue;

  FieldChange({
    required this.oldValue,
    required this.newValue,
  });

  Map<String, dynamic> toJson() {
    return {
      'oldValue': oldValue,
      'newValue': newValue,
    };
  }

  factory FieldChange.fromJson(Map<String, dynamic> json) {
    return FieldChange(
      oldValue: json['oldValue'] as String? ?? '',
      newValue: json['newValue'] as String? ?? '',
    );
  }
}