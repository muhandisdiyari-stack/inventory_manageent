import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

/// Application-wide constants.
///
/// Version info is imported from [AppConfig] which is the single source of truth.
class AppConstants {
  // ─── App Info (from central config) ────────────────────────────
  static String get appVersion => AppConfig.appVersion;
  static String get appName => AppConfig.appName;

  // ─── Theme ────────────────────────────────────────────────────
  static const String darkModeKey = 'dark_mode';

  // ─── Onboarding ───────────────────────────────────────────────
  static const String onboardingCompletedKey = 'onboarding_completed';

  // ─── UI Timing ────────────────────────────────────────────────
  static const Duration snackbarDuration = Duration(seconds: 3);
  static const Duration undoDuration = Duration(seconds: 5);
  static const Duration splashDuration = Duration(milliseconds: 2500);

  // ─── Responsive Breakpoints ───────────────────────────────────
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double sidebarWidthRatio = 0.3;

  // ─── Layout Spacing ───────────────────────────────────────────
  static const double fabBottomMargin = 24.0;
  static const double fabRightMargin = 24.0;

  // ─── Hive Box Names ───────────────────────────────────────────
  static const String appSettingsBox = 'app_settings';
  static const String inventoriesListBox = 'inventories_list';
  static const String activityLogsBox = 'activity_logs';

  // ─── CSV Export ───────────────────────────────────────────────
  static const int batchSize = 100;
  static const int previewLimit = 50;

  // ─── Activity Log ─────────────────────────────────────────────
  static const int maxLogEntries = 2000;

  /// Logs app constants at startup for debugging.
  static void logConstants() {
    debugPrint('📋 App Constants initialized');
    debugPrint('   Version: $appVersion');
    debugPrint('   Mobile Breakpoint: $mobileBreakpoint');
    debugPrint('   Preview Limit: $previewLimit');
  }
}