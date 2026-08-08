import 'dart:io';

import 'package:flextapdf/store/library_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// DB のオープンは実 I/O を伴うため、マイクロタスクを流すだけでは足りない。
Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 25));

/// 中身の違う PDF もどきを作る。ID は「先頭 1MB + サイズ」から作られるので、
/// 実際の PDF である必要はない。
File _makeFile(Directory dir, String name, String content) {
  final file = File(p.join(dir.path, name))..writeAsStringSync(content);
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('flextapdf_test');
    // テストファイルは並列に走るため、DB を他ファイルと共有しないよう分離する。
    await databaseFactory.setDatabasesPath(tempRoot.path);

    // path_provider は実機のチャネルを叩くので、テスト用の一時領域に差し替える。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempRoot.path,
    );

    // 各テストで DB を空にする。
    await deleteDatabase(p.join(tempRoot.path, 'pdf_info.db'));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// 初期ロードが済んだ Store を返す。
  Future<(ProviderContainer, LibraryStore)> boot() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(libraryStoreProvider);
    // DB オープンと最初のクエリを待つ。
    for (var i = 0; i < 40; i++) {
      await _tick();
      if (!container.read(libraryStoreProvider).isLoading) break;
    }
    final state = container.read(libraryStoreProvider);
    expect(state.isLoading, isFalse, reason: 'ライブラリの初期ロードが終わらなかった');
    expect(state.errorMessage, isNull);
    return (container, container.read(libraryStoreProvider.notifier));
  }

  group('LibraryStore.importFile', () {
    test('取り込むとアプリ内ライブラリへコピーされる', () async {
      final (container, store) = await boot();
      final source = _makeFile(tempRoot, 'source.pdf', 'hello');

      final doc = await store.importFile(source.path);

      expect(doc, isNotNull);
      expect(doc!.fileName, 'source.pdf');
      // 選択された元パスではなく、アプリ内の永続パスを指す
      expect(doc.storedPath, isNot(source.path));
      expect(doc.storedPath, endsWith('${doc.id}.pdf'));
      expect(File(doc.storedPath).existsSync(), isTrue);
      expect(container.read(libraryStoreProvider).documents, hasLength(1));
    });

    test('同じ内容を取り込み直しても重複しない', () async {
      final (container, store) = await boot();
      final first = _makeFile(tempRoot, 'a.pdf', 'same content');
      // file_selector は毎回別ディレクトリにコピーを返すため、
      // パスが違っても同じファイルとして扱えなければならない。
      final copyDir = Directory(p.join(tempRoot.path, 'uuid-2'))
        ..createSync();
      final second = _makeFile(copyDir, 'a.pdf', 'same content');

      final doc1 = await store.importFile(first.path);
      final doc2 = await store.importFile(second.path);

      expect(doc1!.id, doc2!.id);
      expect(container.read(libraryStoreProvider).documents, hasLength(1));
    });

    test('取り込み直しても読書位置が引き継がれる', () async {
      final (container, store) = await boot();
      final source = _makeFile(tempRoot, 'b.pdf', 'content b');

      final doc = await store.importFile(source.path);
      await store.updateProgress(doc!.id, lastPage: 7, totalPages: 20);

      final reimported = await store.importFile(source.path);

      expect(reimported!.id, doc.id);
      expect(reimported.lastPage, 7);
      expect(reimported.totalPages, 20);
      expect(container.read(libraryStoreProvider).documents, hasLength(1));
    });

    test('内容が違えば別レコードになる', () async {
      final (container, store) = await boot();

      await store.importFile(_makeFile(tempRoot, 'c.pdf', 'aaa').path);
      await store.importFile(_makeFile(tempRoot, 'd.pdf', 'bbb').path);

      expect(container.read(libraryStoreProvider).documents, hasLength(2));
    });

    test('存在しないパスは null を返す', () async {
      final (_, store) = await boot();

      final doc = await store.importFile(p.join(tempRoot.path, 'missing.pdf'));

      expect(doc, isNull);
    });
  });

  group('LibraryStore の状態更新', () {
    test('最終ページまで読むと既読になる', () async {
      final (container, store) = await boot();
      final doc =
          await store.importFile(_makeFile(tempRoot, 'e.pdf', 'e').path);

      await store.updateProgress(doc!.id, lastPage: 9, totalPages: 10);
      expect(container.read(libraryStoreProvider).documents[doc.id]!.isRead,
          isFalse);

      await store.updateProgress(doc.id, lastPage: 10, totalPages: 10);
      expect(container.read(libraryStoreProvider).documents[doc.id]!.isRead,
          isTrue);
    });

    test('お気に入りを切り替えると favorites に出入りする', () async {
      final (container, store) = await boot();
      final doc =
          await store.importFile(_makeFile(tempRoot, 'f.pdf', 'f').path);

      expect(container.read(libraryStoreProvider).favorites, isEmpty);

      await store.toggleFavorite(doc!.id);
      expect(container.read(libraryStoreProvider).favorites, hasLength(1));

      await store.toggleFavorite(doc.id);
      expect(container.read(libraryStoreProvider).favorites, isEmpty);
    });

    test('削除すると実体もレコードも消える', () async {
      final (container, store) = await boot();
      final doc =
          await store.importFile(_makeFile(tempRoot, 'g.pdf', 'g').path);
      final stored = File(doc!.storedPath);
      expect(stored.existsSync(), isTrue);

      await store.remove(doc.id);

      expect(container.read(libraryStoreProvider).documents, isEmpty);
      // 一覧から消えてもファイルや DB レコードが残り続けないこと
      expect(stored.existsSync(), isFalse);
    });

    test('recent は最終閲覧が新しい順', () async {
      final (container, store) = await boot();
      final older =
          await store.importFile(_makeFile(tempRoot, 'h.pdf', 'h').path);
      final newer =
          await store.importFile(_makeFile(tempRoot, 'i.pdf', 'i').path);

      await store.markOpened(older!.id);

      final recent = container.read(libraryStoreProvider).recent;
      expect(recent.first.id, older.id);
      expect(recent.last.id, newer!.id);
    });
  });

  group('LibraryStore の永続化', () {
    test('再起動しても取り込み済みのファイルが残る', () async {
      final (_, store) = await boot();
      final doc =
          await store.importFile(_makeFile(tempRoot, 'j.pdf', 'j').path);
      await store.updateProgress(doc!.id, lastPage: 3, totalPages: 5);

      // 別コンテナ = アプリ再起動相当
      final (reopened, _) = await boot();

      final restored = reopened.read(libraryStoreProvider).documents[doc.id];
      expect(restored, isNotNull);
      expect(restored!.lastPage, 3);
      expect(restored.totalPages, 5);
      expect(restored.fileName, 'j.pdf');
    });
  });

  group('LibraryStore のディレクトリ登録', () {
    test('追加と解除ができ、重複登録されない', () async {
      final (container, store) = await boot();

      await store.addDirectory('/books');
      await store.addDirectory('/books');
      expect(container.read(libraryStoreProvider).directories, ['/books']);

      await store.removeDirectory('/books');
      expect(container.read(libraryStoreProvider).directories, isEmpty);
    });
  });
}
