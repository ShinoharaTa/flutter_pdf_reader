import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'themeMode';
const _scrollDirectionKey = 'scrollDirection';

/// v1 のキー。bool で「ダークかどうか」を持っていた。
const _legacyThemeKey = 'isDarkTheme';

/// v1 のキー。名前は isScrollVertical だが、実際には
/// 「横スクロールかどうか」を保存していた（意味が逆）。
const _legacyScrollKey = 'isScrollVertical';

class SettingsState {
  final ThemeMode themeMode;
  final Axis scrollDirection;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.scrollDirection = Axis.horizontal,
  });

  SettingsState copyWith({ThemeMode? themeMode, Axis? scrollDirection}) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      scrollDirection: scrollDirection ?? this.scrollDirection,
    );
  }
}

class SettingsStore extends StateNotifier<SettingsState> {
  SettingsStore() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // 読み込み中に破棄されていることがある（画面遷移やテストの終了時）。
    if (!mounted) return;

    state = SettingsState(
      themeMode: _readThemeMode(prefs),
      scrollDirection: _readScrollDirection(prefs),
    );
  }

  /// 旧キー（bool）しか無い場合はそこから読む。System は表現できないので
  /// 旧データからの復元では Light / Dark のどちらかになる。
  ThemeMode _readThemeMode(SharedPreferences prefs) {
    final stored = prefs.getString(_themeModeKey);
    if (stored != null) {
      return ThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => ThemeMode.system,
      );
    }
    final legacy = prefs.getBool(_legacyThemeKey);
    if (legacy != null) return legacy ? ThemeMode.dark : ThemeMode.light;
    return ThemeMode.system;
  }

  Axis _readScrollDirection(SharedPreferences prefs) {
    final stored = prefs.getString(_scrollDirectionKey);
    if (stored != null) {
      return stored == Axis.vertical.name ? Axis.vertical : Axis.horizontal;
    }
    final legacy = prefs.getBool(_legacyScrollKey);
    // 旧キーは true が横スクロールを意味していた。
    if (legacy != null) return legacy ? Axis.horizontal : Axis.vertical;
    return Axis.horizontal;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    await prefs.remove(_legacyThemeKey);
  }

  Future<void> setScrollDirection(Axis direction) async {
    state = state.copyWith(scrollDirection: direction);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scrollDirectionKey, direction.name);
    await prefs.remove(_legacyScrollKey);
  }

  Future<void> toggleScrollDirection() {
    return setScrollDirection(
      state.scrollDirection == Axis.horizontal ? Axis.vertical : Axis.horizontal,
    );
  }
}

final settingsStoreProvider =
    StateNotifierProvider<SettingsStore, SettingsState>((ref) {
  return SettingsStore();
});
