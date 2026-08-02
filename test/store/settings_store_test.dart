import 'package:flextapdf/store/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 非同期の _loadSettings が state に反映されるまで待つ。
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('SettingsStore', () {
    test('設定が無ければ System テーマ・横スクロール', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();

      container.read(settingsStoreProvider);
      await _settle();

      final state = container.read(settingsStoreProvider);
      expect(state.themeMode, ThemeMode.system);
      expect(state.scrollDirection, Axis.horizontal);
    });

    test('テーマを保存して読み直せる', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      container.read(settingsStoreProvider);
      await _settle();

      await container.read(settingsStoreProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      expect(container.read(settingsStoreProvider).themeMode, ThemeMode.dark);

      // 別インスタンスで読み直しても維持される
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      reopened.read(settingsStoreProvider);
      await _settle();
      expect(reopened.read(settingsStoreProvider).themeMode, ThemeMode.dark);
    });

    test('System を選び直せる', () async {
      SharedPreferences.setMockInitialValues({'flutter.themeMode': 'dark'});
      final container = makeContainer();
      container.read(settingsStoreProvider);
      await _settle();
      expect(container.read(settingsStoreProvider).themeMode, ThemeMode.dark);

      await container.read(settingsStoreProvider.notifier)
          .setThemeMode(ThemeMode.system);

      expect(container.read(settingsStoreProvider).themeMode, ThemeMode.system);
    });

    test('旧 isDarkTheme キーから移行できる', () async {
      SharedPreferences.setMockInitialValues({'flutter.isDarkTheme': true});
      final container = makeContainer();

      container.read(settingsStoreProvider);
      await _settle();

      expect(container.read(settingsStoreProvider).themeMode, ThemeMode.dark);
    });

    test('旧 isScrollVertical キーは true が横スクロールを意味する', () async {
      SharedPreferences.setMockInitialValues({'flutter.isScrollVertical': true});
      final container = makeContainer();

      container.read(settingsStoreProvider);
      await _settle();

      expect(container.read(settingsStoreProvider).scrollDirection,
          Axis.horizontal);
    });

    test('スクロール方向をトグルできる', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      container.read(settingsStoreProvider);
      await _settle();

      final notifier = container.read(settingsStoreProvider.notifier);
      await notifier.toggleScrollDirection();
      expect(container.read(settingsStoreProvider).scrollDirection,
          Axis.vertical);

      await notifier.toggleScrollDirection();
      expect(container.read(settingsStoreProvider).scrollDirection,
          Axis.horizontal);
    });
  });
}
