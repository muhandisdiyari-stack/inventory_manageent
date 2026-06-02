import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Centralized snackbar utility to prevent double snackbars and ensure consistency
class SnackBarUtils {
  /// Show a snackbar message
  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
    bool isSuccess = false,
    Duration? duration,
    IconData? icon,
  }) {
    if (!context.mounted) return;

    // Always clear existing snackbars first to prevent stacking
    ScaffoldMessenger.of(context).clearSnackBars();

    final Color? backgroundColor = isError
        ? Colors.red.shade700
        : isSuccess
            ? Colors.green.shade600
            : null;

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
        ],
        if (isError)
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
        if (isError) const SizedBox(width: 8),
        if (isSuccess)
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
        if (isSuccess) const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? AppConstants.snackbarDuration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(40),
        ),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }

  /// Show a success message
  static void success(BuildContext context, String message) {
    show(context, message: message, isSuccess: true);
  }

  /// Show an error message
  static void error(BuildContext context, String message) {
    show(context, message: message, isError: true);
  }

  /// Show an info message
  static void info(BuildContext context, String message, {IconData? icon}) {
    show(context, message: message, icon: icon);
  }
}