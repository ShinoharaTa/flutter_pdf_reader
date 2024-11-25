import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfx/pdfx.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

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

class LibraryScreen extends StatefulWidget {
  @override
  _LibraryScreenState createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<String> recentFiles = [];

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  Future<void> _loadRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      recentFiles = prefs.getStringList('recentFiles') ?? [];
    });
  }

  Future<void> _addRecentFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      recentFiles.remove(filePath); // 重複を排除
      recentFiles.insert(0, filePath); // 新しいファイルを先頭に追加
      if (recentFiles.length > 10) {
        recentFiles = recentFiles.sublist(0, 10); // 最大10件まで
      }
      prefs.setStringList('recentFiles', recentFiles);
    });
  }

  Future<void> _openFilePicker() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      await _addRecentFile(filePath);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PDFViewerPage(filePath: filePath),
        ),
      );
    }
  }

  Future<void> _openNetworkFile() async {
    final urlController = TextEditingController();

    // ダイアログでURLを入力
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Enter PDF URL"),
        content: TextField(
          controller: urlController,
          decoration: InputDecoration(hintText: "Enter URL here"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(context);
                final tempDir = await getTemporaryDirectory();
                final filePath = '${tempDir.path}/${url.split('/').last}';

                try {
                  await Dio().download(url, filePath);
                  await _addRecentFile(filePath);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PDFViewerPage(filePath: filePath),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to download file")),
                  );
                }
              }
            },
            child: Text("Open"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Library"),
        actions: [
          IconButton(
            icon: Icon(Icons.download),
            onPressed: _openNetworkFile,
          ),
          IconButton(
            icon: Icon(Icons.folder),
            onPressed: _openFilePicker,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: recentFiles.length,
        itemBuilder: (context, index) {
          final filePath = recentFiles[index];
          return ListTile(
            title: Text(filePath.split('/').last),
            subtitle: Text(filePath),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewerPage(filePath: filePath),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PDFViewerPage extends StatelessWidget {
  final String filePath;

  const PDFViewerPage({required this.filePath});

  @override
  Widget build(BuildContext context) {
    final pdfController = PdfController(
      document: PdfDocument.openFile(filePath),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("PDF Viewer"),
      ),
      body: PdfView(
        controller: pdfController,
      ),
    );
  }
}
