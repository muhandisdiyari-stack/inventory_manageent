import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';

part 'theme_event.dart';
part 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final Box _appSettings;

  ThemeBloc()
      : _appSettings = Hive.box(AppConstants.appSettingsBox),
        super(ThemeState(
          mode: (Hive.box(AppConstants.appSettingsBox)
                    .get(AppConstants.darkModeKey, defaultValue: false) as bool)
                ? ThemeMode.dark
                : ThemeMode.light,
        )) {
    on<ToggleTheme>(_onToggleTheme);
    on<SetThemeMode>(_onSetThemeMode);
  }

  void _onToggleTheme(ToggleTheme event, Emitter<ThemeState> emit) {
    final newMode = state.isDark ? ThemeMode.light : ThemeMode.dark;
    _appSettings.put(AppConstants.darkModeKey, newMode == ThemeMode.dark);
    emit(state.copyWith(mode: newMode));
  }

  void _onSetThemeMode(SetThemeMode event, Emitter<ThemeState> emit) {
    if (state.mode != event.mode) {
      _appSettings.put(AppConstants.darkModeKey, event.mode == ThemeMode.dark);
      emit(state.copyWith(mode: event.mode));
    }
  }
}