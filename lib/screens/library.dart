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

  /// PDF を選んでライブラリへ取り込む。
  ///
  /// 複数選択に対応している。フォルダ単位で読み込みたい場合は、選択画面で
  /// まとめて選ぶ。フォルダのパスを保存する方式は、SAF の許可が
  /// dart:io の権限にならないため機能しなかった。
  Future<void> _pickAndImport(BuildContext context, WidgetRef ref) async {
    const fileTypeGroup = XTypeGroup(label: 'PDF files', extensions: ['pdf']);
    final files = await openFiles(acceptedTypeGroups: [fileTypeGroup]);
    if (files.isEmpty) return;

    final store = ref.read(libraryStoreProvider.notifier);
    final imported = await store.importFiles(files.map((f) => f.path).toList());
    if (!context.mounted) return;

    if (imported.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ファイルを取り込めませんでした')),
      );
      return;
    }

    final failed = files.length - imported.length;
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failed 件は取り込めませんでした')),
      );
    }

    // 1 件だけ選んだときはそのまま開く。まとめて取り込んだときは一覧に留まる。
    if (imported.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PDFViewerPage(documentId: imported.first.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryStoreProvider);

    return DefaultTabController(
      length: 2,
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
                        emptyMessage: '右下のボタンから PDF を追加してください\n複数まとめて選べます',
                      ),
                      _DocumentList(
                        storageKey: const PageStorageKey('library-favorite'),
                        documents: library.favorites,
                        emptyMessage: 'ビューアの星ボタンでお気に入りに追加できます',
                      ),
                    ],
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _pickAndImport(context, ref),
          tooltip: "PDF を追加（複数選択できます）",
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

