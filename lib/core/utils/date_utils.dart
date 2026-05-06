/// Date and file-name utility functions used across the app.
library date_utils;

/// Sanitizes a string so it can be used as a safe file name across
/// Windows, macOS, Linux, Android and iOS.
///
/// Replaces unsafe characters with underscores and collapses
/// consecutive underscores / whitespace.
String sanitizeFileName(String input) {
  // Characters that are unsafe in file names on one or more platforms
  const unsafe = r'[\\/:*?"<>|]';
  var sanitized = input.replaceAll(RegExp(unsafe), '_');

  // Replace any whitespace run with a single underscore
  sanitized = sanitized.replaceAll(RegExp(r'\s+'), '_');

  // Collapse multiple underscores into one
  sanitized = sanitized.replaceAll(RegExp(r'_{2,}'), '_');

  // Trim leading / trailing dots and whitespace (Windows restriction)
  sanitized = sanitized.replaceAll(RegExp(r'^[\.\s]+|[\.\s]+$'), '');

  // If everything was stripped, return a safe fallback
  if (sanitized.isEmpty) sanitized = 'file';

  return sanitized;
}

/// Formats a [DateTime] into a compact, sortable string suitable for
/// use in file names (e.g. `20250502_143022`).
String formatTimestamp(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$y$m$d$h$min$s';
}

/// Formats a [DateTime] into a date-only string that spreadsheet
/// applications recognise as a date (e.g. `2025-05-02`).
String formatDateOnly(DateTime? dt) {
  if (dt == null) return '';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}