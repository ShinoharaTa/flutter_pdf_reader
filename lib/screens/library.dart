import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf_reader/components/confirm_dialog.dart';
import '../store/file_store.dart';
import './viewer.dart';
import './settings.dart';
import 'package:permission_handler/permission_handler.dart';

class LibraryScreen extends ConsumerWidget {
  Future<bool> _requestStoragePermission() async {
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  List<Widget> _getDirectoryContent(
      String directoryPath, WidgetRef ref, BuildContext context) {
    final dir = Directory(directoryPath);
    final files = dir.listSync();

    return files.map((file) {
      if (file is Directory) {
        return ExpansionTile(
            title: Text(file.path.split('/').last),
            children: _getDirectoryContent(file.path, ref, context));
      } else {
        return ListTile(
          title: Text(file.path.split('/').last),
          onTap: () async {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PDFViewerPage(filePath: file.path),
              ),
            );
            final notifier = ref.read(fileStoreProvider.notifier);
            await notifier.addRecentFile(file.path);
          },
        );
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileStore = ref.watch(fileStoreProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Library"),
          actions: [
            IconButton(
              icon: Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(), // 設定画面に遷移
                  ),
                );
              },
            ),
          ],
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
            _buildRecentTab(fileStore, ref),
            _buildFavoriteTab(fileStore, ref),
            _buildDirectoryTab(fileStore, ref),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            const fileTypeGroup = XTypeGroup(
              label: 'PDF files', // ダイアログに表示されるフィルタ名
              extensions: ['pdf'], // 拡張子フィルタ
            );
            final file = await openFile(acceptedTypeGroups: [fileTypeGroup]);

            if (file != null) {
              final notifier = ref.read(fileStoreProvider.notifier);
              await notifier.addRecentFile(file.path);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewerPage(filePath: file.path),
                ),
              );
            } else {
              print('No file selected.');
            }
          },
          child: Icon(Icons.folder_open),
          tooltip: "Open PDF",
        ),
      ),
    );
  }

  Widget _buildRecentTab(FileStoreState state, WidgetRef ref) {
    return ListView.builder(
      itemCount: state.recentFiles.length,
      itemBuilder: (context, index) {
        final filePath = state.recentFiles[index];
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
            final notifier = ref.read(fileStoreProvider.notifier);
            await notifier.addRecentFile(filePath);
          },
          trailing: IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              final result = await ConfirmationDialog.show(
                context: context,
                content: "${filePath.split('/').last}を削除しますか？",
                confirmText: "はい",
                cancelText: "いいえ",
              );
              if (result == true) {
                final notifier = ref.read(fileStoreProvider.notifier);
                notifier.removeRecentFile(filePath);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildFavoriteTab(FileStoreState state, WidgetRef ref) {
    return ListView.builder(
      itemCount: state.favoriteFiles.length,
      itemBuilder: (context, index) {
        final filePath = state.favoriteFiles[index];
        return ListTile(
          title: Text(filePath.split('/').last),
          subtitle: Text(filePath),
          trailing: IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              final notifier = ref.read(fileStoreProvider.notifier);
              notifier.removeFavoriteFile(filePath);
            },
          ),
        );
      },
    );
  }

  Widget _buildDirectoryTab(FileStoreState state, WidgetRef ref) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: () async {
              final isGranted = await _requestStoragePermission();
              if (!isGranted) {
                ScaffoldMessenger.of(ref.context).showSnackBar(
                  SnackBar(
                      content: Text(
                          "Storage permission is required to access folders.")),
                );
                return;
              }
              final directory = await getDirectoryPath();
              if (directory != null) {
                final notifier = ref.read(fileStoreProvider.notifier);
                notifier.addDirectory(directory);
              }
            },
            icon: Icon(Icons.add),
            label: Text("Add Directory"),
          ),
        ),
        ...state.directories.map((directory) {
          return ExpansionTile(
              title: Text(directory.split('/').last),
              children: _getDirectoryContent(directory, ref, ref.context));
        })
      ],
    );
  }
}
