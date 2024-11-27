import 'package:flutter/material.dart';
import 'screens/library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Riverpodをインポート

void main() {
  runApp(ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Viewer with Library',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LibraryScreen(),
    );
  }
}
