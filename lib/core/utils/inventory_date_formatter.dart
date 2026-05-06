class InventoryDateFormatter {
  /// Formats a DateTime to a human-readable relative string
  /// Example outputs:
  /// - "Today"
  /// - "Yesterday"
  /// - "3 days ago"
  /// - "2 weeks ago"
  /// - "5 months ago"
  /// - "15/6/2024" (for dates older than 1 year)
  static String format(DateTime date) {
    final now = DateTime.now();

    // Handle future dates
    if (date.isAfter(now)) {
      return '${date.day}/${date.month}/${date.year}';
    }

    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = _calculateMonthsDifference(now, date);
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Calculates the exact month difference between two dates
  static int _calculateMonthsDifference(DateTime now, DateTime date) {
    int months = (now.year - date.year) * 12 + now.month - date.month;

    // Adjust for day difference
    if (now.day < date.day) {
      months--;
    }

    return months;
  }
}