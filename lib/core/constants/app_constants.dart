// File: lib/core/constants/app_constants.dart

class AppConstants {
  // App Info
  static const String appVersion = '2.1.0';
  static const String appName = 'Inventory Pro';

  // Theme
  static const darkModeKey = 'dark_mode';

  // Onboarding
  static const String onboardingCompletedKey = 'onboarding_completed';

  // UI Timing
  static const Duration snackbarDuration = Duration(seconds: 3);
  static const Duration undoDuration = Duration(seconds: 5);
  static const Duration splashDuration = Duration(milliseconds: 2500);

  // Responsive Breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double sidebarWidthRatio = 0.3;

  // Layout Spacing
  static const double fabBottomMargin = 24.0;
  static const double fabRightMargin = 24.0;

  // Hive Box Names
  static const String appSettingsBox = 'app_settings';
  static const String inventoriesListBox = 'inventories_list';
  static const String activityLogsBox = 'activity_logs';

  // CSV Export
  static const int batchSize = 100;
  static const int previewLimit = 50;

  // Demo Mode
  // Set to true to auto-load demo data on first run
  static const bool autoLoadDemoData = true;
}