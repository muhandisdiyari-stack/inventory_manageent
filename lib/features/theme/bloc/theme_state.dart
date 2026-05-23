part of 'theme_bloc.dart';

class ThemeState {
  final ThemeMode mode;

  const ThemeState({required this.mode});

  bool get isDark => mode == ThemeMode.dark;

  ThemeState copyWith({ThemeMode? mode}) {
    return ThemeState(mode: mode ?? this.mode);
  }
}