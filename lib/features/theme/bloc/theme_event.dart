part of 'theme_bloc.dart';

sealed class ThemeEvent {
  const ThemeEvent();
}

class ToggleTheme extends ThemeEvent {
  const ToggleTheme();
}

class SetThemeMode extends ThemeEvent {
  final ThemeMode mode;
  const SetThemeMode(this.mode);
}