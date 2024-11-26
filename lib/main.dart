import 'package:flutter/material.dart';
import 'screens/library.dart';

void main() {
  runApp(MyApp());
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
