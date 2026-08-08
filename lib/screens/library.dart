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
                        storageKey: const PageStorageKey('library-recent'),
                        documents: library.recent,
                        emptyMessage: '右下のボタンから PDF を追加してください',
                      ),
                      _DocumentList(
                        storageKey: const PageStorageKey('library-favorite'),
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

/// 幅に応じた列数。Material 3 のブレークポイントに沿う。
int _columnsFor(double width) {
  if (width >= 1240) return 4;
  if (width >= 840) return 3;
  if (width >= 600) return 2;
  return 1;
}

/// Recent / Favorite で共通のドキュメント一覧。
///
/// 狭い画面では 1 カラムのリスト、広い画面ではサムネイル付きの
/// グリッドになる。折りたたみ端末を開いたときに横幅を捨てないため。
class _DocumentList extends ConsumerWidget {
  final List<LibraryDocument> documents;
  final String emptyMessage;

  /// 折りたたみ・展開でウィジェットが作り直されてもスクロール位置を保つ。
  final PageStorageKey<String> storageKey;

  const _DocumentList({
    required this.storageKey,
    required this.documents,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (documents.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        if (columns == 1) {
          return ListView.builder(
            key: storageKey,
            itemCount: documents.length,
            itemBuilder: (context, index) => _DocumentTile(
              doc: documents[index],
              subtitle: _subtitleOf(documents[index]),
            ),
          );
        }
        return GridView.builder(
          key: storageKey,
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.62,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: documents.length,
          itemBuilder: (context, index) => _DocumentCard(
            doc: documents[index],
            subtitle: _subtitleOf(documents[index]),
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

/// 読書進捗の割合。未読・総ページ不明なら null。
double? _progressOf(LibraryDocument doc) {
  if (doc.totalPages <= 0) return null;
  return (doc.lastPage / doc.totalPages).clamp(0.0, 1.0);
}

Future<void> _confirmRemove(
  BuildContext context,
  WidgetRef ref,
  LibraryDocument doc,
) async {
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
}

void _openViewer(BuildContext context, LibraryDocument doc) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PDFViewerPage(documentId: doc.id)),
  );
}

/// 1 カラム表示の行。
class _DocumentTile extends ConsumerWidget {
  final LibraryDocument doc;
  final String subtitle;

  const _DocumentTile({required this.doc, required this.subtitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(doc.fileName),
      subtitle: Text(subtitle),
      leading: SizedBox(
        width: 40,
        height: 56,
        child: _Thumbnail(doc: doc),
      ),
      onTap: () => _openViewer(context, doc),
      trailing: IconButton(
        icon: const Icon(Icons.delete),
        tooltip: 'ライブラリから削除',
        onPressed: () => _confirmRemove(context, ref, doc),
      ),
    );
  }
}

/// グリッド表示のカード。
class _DocumentCard extends ConsumerWidget {
  final LibraryDocument doc;
  final String subtitle;

  const _DocumentCard({required this.doc, required this.subtitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = _progressOf(doc);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openViewer(context, doc),
        onLongPress: () => _confirmRemove(context, ref, doc),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Thumbnail(doc: doc),
                  if (doc.isFavorite)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(Icons.star_rounded, color: Colors.amber),
                    ),
                ],
              ),
            ),
            if (progress != null)
              LinearProgressIndicator(value: progress, minHeight: 3),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1 ページ目のサムネイル。無ければアイコンにフォールバックする。
class _Thumbnail extends ConsumerWidget {
  final LibraryDocument doc;

  const _Thumbnail({required this.doc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.read(libraryStoreProvider.notifier).thumbnailPathOf(doc);
    final file = File(path);
    if (!file.existsSync()) {
      return const ColoredBox(
        color: Color(0x11000000),
        child: Center(child: Icon(Icons.picture_as_pdf_outlined)),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: Color(0x11000000),
        child: Center(child: Icon(Icons.picture_as_pdf_outlined)),
      ),
    );
  }
}

class _DirectoryTab extends ConsumerWidget {
  final List<String> directories;
  const _DirectoryTab({required this.directories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      key: const PageStorageKey('library-directory'),
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
