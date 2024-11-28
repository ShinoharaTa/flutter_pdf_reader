import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final ThemeMode themeMode;

  SettingsState({required this.themeMode});

  SettingsState copyWith({ThemeMode? themeMode}) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsStore extends StateNotifier<SettingsState> {
  SettingsStore() : super(SettingsState(themeMode: ThemeMode.system)) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkTheme = prefs.getBool('isDarkTheme') ?? false;
    state = state.copyWith(
      themeMode: isDarkTheme ? ThemeMode.dark : ThemeMode.light,
    );
  }

  Future<void> toggleThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkTheme = state.themeMode == ThemeMode.dark;
    final newThemeMode = isDarkTheme ? ThemeMode.light : ThemeMode.dark;
    await prefs.setBool('isDarkTheme', newThemeMode == ThemeMode.dark);
    state = state.copyWith(themeMode: newThemeMode);
  }
}

final settingsStoreProvider =
    StateNotifierProvider<SettingsStore, SettingsState>((ref) {
  return SettingsStore();
});
