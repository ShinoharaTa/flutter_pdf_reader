import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final ThemeMode themeMode;
  final Axis scrollDirection;

  SettingsState({required this.themeMode, required this.scrollDirection});

  SettingsState copyWith({ThemeMode? themeMode, Axis? scrollDirection}) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      scrollDirection: scrollDirection ?? this.scrollDirection,
    );
  }
}

class SettingsStore extends StateNotifier<SettingsState> {
  SettingsStore()
      : super(SettingsState(
            themeMode: ThemeMode.system, scrollDirection: Axis.horizontal)) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkTheme = prefs.getBool('isDarkTheme') ?? false;
    final scrollDirection = prefs.getBool('isScrollVertical') ?? false;
    state = state.copyWith(
      themeMode: isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      scrollDirection: scrollDirection ? Axis.horizontal : Axis.vertical,
    );
  }

  Future<void> toggleThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkTheme = state.themeMode == ThemeMode.dark;
    final newThemeMode = isDarkTheme ? ThemeMode.light : ThemeMode.dark;
    await prefs.setBool('isDarkTheme', newThemeMode == ThemeMode.dark);
    state = state.copyWith(themeMode: newThemeMode);
  }

  Future<void> toggleScrollDirection() async {
    final prefs = await SharedPreferences.getInstance();
    final isScrollHorizontal = state.scrollDirection == Axis.horizontal;
    final newScrollDirection =
        isScrollHorizontal ? Axis.vertical : Axis.horizontal;
    await prefs.setBool(
        'isScrollVertical', newScrollDirection == Axis.horizontal);
    state = state.copyWith(scrollDirection: newScrollDirection);
  }
}

final settingsStoreProvider =
    StateNotifierProvider<SettingsStore, SettingsState>((ref) {
  return SettingsStore();
});
