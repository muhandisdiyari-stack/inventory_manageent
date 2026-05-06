// lib/auto_version.dart
class AppVersion {
  static const String version = '1.0.0';
  static const String buildNumber = '1';
  static const String buildDate = '2026-05-06';
  
  static String get fullVersion => '$version+$buildNumber';
  
  static void printVersion() {
    print('App Version: $fullVersion');
    print('Build Date: $buildDate');
  }
}