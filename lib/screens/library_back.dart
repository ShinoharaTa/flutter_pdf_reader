import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import './viewer.dart';
import 'package:permission_handler/permission_handler.dart';

class LibraryScreen extends StatefulWidget {
  @override
  _LibraryScreenState createState() => _LibraryScreenState();
}

Future<bool> _requestStoragePermission() async {
  final status = await Permission.manageExternalStorage.request();
  return status.isGranted;
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<String> recentFiles = [];
  List<String> favoriteFiles = [];
  List<String> directories = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      recentFiles = prefs.getStringList('recentFiles') ?? [];
      favoriteFiles = prefs.getStringList('favoriteFiles') ?? [];
      directories = prefs.getStringList('directories') ?? [];
    });
  }

  Future<void> _addRecentFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      recentFiles.remove(filePath);
      recentFiles.insert(0, filePath);
      if (recentFiles.length > 20) {
        recentFiles = recentFiles.sublist(0, 20);
      }
      prefs.setStringList('recentFiles', recentFiles);
    });
  }

  Future<void> _addFavoriteFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (!favoriteFiles.contains(filePath)) {
        favoriteFiles.add(filePath);
        prefs.setStringList('favoriteFiles', favoriteFiles);
      }
    });
  }

  Future<void> _addDirectory() async {
    final isGranted = await _requestStoragePermission();
    if (!isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Storage permission is required to access folders.")),
      );
      return;
    }

    final directory = await getDirectoryPath();
    if (directory != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (!directories.contains(directory)) {
          directories.add(directory);
          prefs.setStringList('directories', directories);
        }
      });
    }
  }

  Future<void> _openFilePicker() async {
    const fileTypeGroup = XTypeGroup(
      label: 'PDF files', // ダイアログに表示されるフィルタ名
      extensions: ['pdf'], // 拡張子フィルタ
    );
    final file = await openFile(acceptedTypeGroups: [fileTypeGroup]);

    if (file != null) {
      await _addRecentFile(file.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PDFViewerPage(filePath: file.path),
        ),
      );
    } else {
      print('No file selected.');
    }
  }

  Widget _buildRecentTab() {
    return ListView.builder(
      itemCount: recentFiles.length,
      itemBuilder: (context, index) {
        final filePath = recentFiles[index];
        return ListTile(
          title: Text(filePath.split('/').last),
          subtitle: Text(filePath),
          onTap: () async {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PDFViewerPage(filePath: filePath),
              ),
            );
            await _addRecentFile(filePath);
          },
        );
      },
    );
  }

  Widget _buildFavoriteTab() {
    return ListView.builder(
      itemCount: favoriteFiles.length,
      itemBuilder: (context, index) {
        final filePath = favoriteFiles[index];
        return ListTile(
          title: Text(filePath.split('/').last),
          subtitle: Text(filePath),
          trailing: IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              setState(() {
                favoriteFiles.remove(filePath);
                prefs.setStringList('favoriteFiles', favoriteFiles);
              });
            },
          ),
          onTap: () {
            // ファイルを開く処理
          },
        );
      },
    );
  }

  Widget _buildDirectoryTab() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: _addDirectory,
            icon: Icon(Icons.add),
            label: Text("Add Directory"),
          ),
        ),
        ...directories.map((directory) {
          return ExpansionTile(
            title: Text(directory.split('/').last),
            children: _buildDirectoryContent(directory),
          );
        }).toList(),
      ],
    );
  }

  List<Widget> _buildDirectoryContent(String directory) {
    final dir = Directory(directory);
    final files = dir.listSync();
    return files.map((file) {
      if (file is Directory) {
        return ExpansionTile(
          title: Text(file.path.split('/').last),
          children: _buildDirectoryContent(file.path),
        );
      } else {
        return ListTile(
          title: Text(file.path.split('/').last),
          onTap: () {
            // ファイルを開く処理
          },
        );
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Library"),
          bottom: TabBar(
            tabs: [
              Tab(text: "Recent"),
              Tab(text: "Favorite"),
              Tab(text: "Directory"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRecentTab(),
            _buildFavoriteTab(),
            _buildDirectoryTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openFilePicker,
          child: Icon(Icons.folder_open),
          tooltip: "Open PDF",
        ),
      ),
    );
  }
}
