import 'package:flutter/material.dart';
import 'screens/library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'store/settings_store.dart';

void main() {
  runApp(ProviderScope(child: MyApp()));
}

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  useMaterial3: true, // Material 3 を有効化
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF666666), // グレースケールのベースカラー
    brightness: Brightness.light,
  ),
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true, // Material 3 を有効化
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF666666), // グレースケールのベースカラー
    brightness: Brightness.dark,
  ),
);

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsStoreProvider).themeMode;
    return MaterialApp(
      title: 'PDF Viewer with Library',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: LibraryScreen(),
    );
  }
}
