import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/confirm_dialog.dart';
import '../models/library_document.dart';
import '../store/library_store.dart';
import './settings.dart';
import './viewer.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  /// ファイルを選び、アプリ内ライブラリへ取り込んでからビューアを開く。
  Future<void> _pickAndOpen(BuildContext context, WidgetRef ref) async {
    const fileTypeGroup = XTypeGroup(label: 'PDF files', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [fileTypeGroup]);
    if (file == null) return;

    final doc = await ref.read(libraryStoreProvider.notifier).importFile(file.path);
    if (!context.mounted) return;

    if (doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ファイルを取り込めませんでした')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PDFViewerPage(documentId: doc.id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryStoreProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Library"),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Recent"),
              Tab(text: "Favorite"),
              Tab(text: "Directory"),
            ],
          ),
        ),
        body: library.errorMessage != null
            ? _ErrorView(message: library.errorMessage!)
            : library.isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _DocumentList(
                        documents: library.recent,
                        emptyMessage: '右下のボタンから PDF を追加してください',
                      ),
                      _DocumentList(
                        documents: library.favorites,
                        emptyMessage: 'ビューアの星ボタンでお気に入りに追加できます',
                      ),
                      _DirectoryTab(directories: library.directories),
                    ],
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _pickAndOpen(context, ref),
          tooltip: "Open PDF",
          child: const Icon(Icons.folder_open),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Recent / Favorite で共通のドキュメント一覧。
class _DocumentList extends ConsumerWidget {
  final List<LibraryDocument> documents;
  final String emptyMessage;

  const _DocumentList({required this.documents, required this.emptyMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (documents.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView.builder(
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        return ListTile(
          title: Text(doc.fileName),
          subtitle: Text(_subtitleOf(doc)),
          leading: doc.isFavorite
              ? const Icon(Icons.star_rounded, color: Colors.amber)
              : const Icon(Icons.picture_as_pdf_outlined),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PDFViewerPage(documentId: doc.id),
              ),
            );
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'ライブラリから削除',
            onPressed: () async {
              final result = await ConfirmationDialog.show(
                context: context,
                title: 'ライブラリから削除',
                content: '${doc.fileName} を削除しますか？\n読書位置とファイルの実体も削除されます。',
                confirmText: "削除",
                cancelText: "キャンセル",
              );
              if (result == true) {
                await ref.read(libraryStoreProvider.notifier).remove(doc.id);
              }
            },
          ),
        );
      },
    );
  }

  String _subtitleOf(LibraryDocument doc) {
    if (doc.totalPages <= 0) return '未読';
    if (doc.isRead) return '読了 · ${doc.totalPages}ページ';
    return '${doc.lastPage} / ${doc.totalPages} ページ';
  }
}

class _DirectoryTab extends ConsumerWidget {
  final List<String> directories;
  const _DirectoryTab({required this.directories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            // フォルダ選択は SAF 経由なので、ストレージ権限を要求しない。
            // MANAGE_EXTERNAL_STORAGE は Play の審査対象で PDF リーダーは
            // 通らない可能性が高く、READ/WRITE_EXTERNAL_STORAGE も
            // Android 13 以降は事実上機能しない。
            onPressed: () async {
              final directory = await getDirectoryPath();
              if (directory == null) return;
              await ref
                  .read(libraryStoreProvider.notifier)
                  .addDirectory(directory);
            },
            icon: const Icon(Icons.add),
            label: const Text("Add Directory"),
          ),
        ),
        ...directories.map((directory) {
          return ExpansionTile(
            title: Text(directory.split(Platform.pathSeparator).last),
            subtitle: Text(directory),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: '登録を解除',
              onPressed: () => ref
                  .read(libraryStoreProvider.notifier)
                  .removeDirectory(directory),
            ),
            // 展開されるまで中身を読まない（閉じたままのフォルダを走査しない）。
            children: [_DirectoryContents(directoryPath: directory)],
          );
        }),
      ],
    );
  }
}

/// フォルダ配下の PDF を非同期に読み出して並べる。
class _DirectoryContents extends ConsumerWidget {
  final String directoryPath;
  const _DirectoryContents({required this.directoryPath});

  Future<List<File>> _listPdfs() async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const [];

    final entries = await dir.list().toList();
    final pdfs = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return pdfs;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<File>>(
      future: _listPdfs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text('読み込めませんでした: ${snapshot.error}'),
          );
        }

        final files = snapshot.data ?? const <File>[];
        if (files.isEmpty) {
          return const ListTile(title: Text('PDF がありません'));
        }

        return Column(
          children: files.map((file) {
            return ListTile(
              title: Text(file.path.split(Platform.pathSeparator).last),
              leading: const Icon(Icons.picture_as_pdf_outlined),
              onTap: () async {
                final doc = await ref
                    .read(libraryStoreProvider.notifier)
                    .importFile(file.path);
                if (!context.mounted) return;
                if (doc == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ファイルを取り込めませんでした')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PDFViewerPage(documentId: doc.id),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}
