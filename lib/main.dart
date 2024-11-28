import 'package:flutter/material.dart';
import 'screens/library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Riverpodをインポート
import 'store/settings_store.dart';

void main() {
  runApp(ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsStoreProvider).themeMode;
    return MaterialApp(
      title: 'PDF Viewer with Library',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        buttonTheme: ButtonThemeData(buttonColor: Colors.blue),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        buttonTheme: ButtonThemeData(buttonColor: Colors.grey[800]),
      ),
      themeMode: themeMode, // 現在のテーマモード
      home: LibraryScreen(),
    );
  }
}
