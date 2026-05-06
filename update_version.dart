// update_version.dart
import 'dart:io';

void main() {
  final version = DateTime.now().millisecondsSinceEpoch.toString().substring(5, 12);
  final buildDate = DateTime.now().toIso8601String().split('T')[0];
  
  final versionFile = File('lib/auto_version.dart');
  versionFile.writeAsStringSync('''
class AppVersion {
  static const String version = '1.0.$version';
  static const String buildNumber = '$version';
  static const String buildDate = '$buildDate';
  
  static String get fullVersion => '\$version+\$buildNumber';
  
  static void printVersion() {
    print('App Version: \$fullVersion');
    print('Build Date: \$buildDate');
  }
}
''');
  
  print('Version updated to: 1.0.$version');
}