import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';

class ThemeProvider extends ChangeNotifier {
  final Box _appSettings;
  ThemeMode _themeMode;

  ThemeProvider()
      : _appSettings = Hive.box('app_settings'),
        _themeMode = (Hive.box('app_settings')
                    .get(AppConstants.darkModeKey, defaultValue: false) as bool)
                ? ThemeMode.dark
                : ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    _appSettings.put(AppConstants.darkModeKey, isDarkMode);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _appSettings.put(AppConstants.darkModeKey, mode == ThemeMode.dark);
      notifyListeners();
    }
  }
}