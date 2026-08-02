import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_document.dart';

/// DB スキーマのバージョン。
///
/// v3 までは cache 配下の一時パスを主キーにした `pdf_info` テーブルだった。
/// そのパスは同じファイルを開き直すたびに変わるため一意キーとして機能せず、
/// v4 で内容ハッシュを ID にした `pdf_documents` へ作り直している。
const _dbVersion = 4;

const _dbFileName = 'pdf_info.db';
const _tableName = 'pdf_documents';

/// アプリ内ライブラリの実体を置くディレクトリ名。
const _libraryDirName = 'library';

/// ID を導出するときに読み込む先頭バイト数。
///
/// 全体を読むと大きい PDF で待たされるため、先頭 1MB とファイルサイズの
/// 組み合わせで識別する。個人のライブラリ規模で衝突は現実的に起きない。
const _hashSampleBytes = 1024 * 1024;

class LibraryState {
  final Map<String, LibraryDocument> documents;
  final List<String> directories;

  /// 初期ロードが終わるまで true。
  final bool isLoading;

  /// DB の初期化に失敗したときの表示用メッセージ。
  /// null でなければライブラリは読み取り専用として振る舞う。
  final String? errorMessage;

  const LibraryState({
    this.documents = const {},
    this.directories = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  /// 最終閲覧が新しい順。
  List<LibraryDocument> get recent {
    final list = documents.values.toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return list;
  }

  /// お気に入りのみを最終閲覧が新しい順で。
  List<LibraryDocument> get favorites =>
      recent.where((doc) => doc.isFavorite).toList();

  LibraryState copyWith({
    Map<String, LibraryDocument>? documents,
    List<String>? directories,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      documents: documents ?? this.documents,
      directories: directories ?? this.directories,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class LibraryStore extends Notifier<LibraryState> {
  Database? _database;
  Directory? _libraryDir;

  @override
  LibraryState build() {
    _load();
    return const LibraryState();
  }

  // ---------------------------------------------------------------- 初期化

  Future<void> _load() async {
    try {
      _database = await _openDb();
    } catch (e) {
      // 開けないときは一度だけファイルごと作り直す。
      // ここで UI にダイアログを出すと Navigator 未構築のタイミングで落ちるため、
      // 失敗は state に持たせて画面側に判断させる。
      try {
        await deleteDatabase(await _dbPath());
        _database = await _openDb();
      } catch (e2) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'データベースを開けませんでした: $e2',
        );
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final rows = await _database!.query(_tableName);

    state = LibraryState(
      documents: {
        for (final row in rows)
          row['id'] as String: LibraryDocument.fromMap(row),
      },
      directories: prefs.getStringList('directories') ?? const [],
      isLoading: false,
    );
  }

  Future<String> _dbPath() async => p.join(await getDatabasesPath(), _dbFileName);

  Future<Database> _openDb() async {
    return openDatabase(
      await _dbPath(),
      version: _dbVersion,
      onCreate: (db, version) => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          // v3 以前のレコードは cache 配下の一時パスを指しており、
          // 実体が既に消えている前提。移行せず破棄する。
          await db.execute('DROP TABLE IF EXISTS pdf_info');
          await _createSchema(db);
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName(
        id TEXT PRIMARY KEY,
        fileName TEXT NOT NULL,
        storedPath TEXT NOT NULL,
        isRead INTEGER NOT NULL DEFAULT 0,
        lastPage INTEGER NOT NULL DEFAULT 1,
        totalPages INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        addedAt TEXT NOT NULL,
        lastOpenedAt TEXT NOT NULL
      )
    ''');
  }

  Future<Directory> _ensureLibraryDir() async {
    final cached = _libraryDir;
    if (cached != null) return cached;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _libraryDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _libraryDir = dir;
    return dir;
  }

  // ------------------------------------------------------------ 取り込み

  /// [sourcePath] の PDF をアプリ内ライブラリへ取り込み、永続 ID を持つ
  /// [LibraryDocument] を返す。
  ///
  /// 同じ内容のファイルが既にあれば、コピーせず既存レコードを返す。
  /// 取り込みに失敗した場合は null を返す。
  Future<LibraryDocument?> importFile(String sourcePath) async {
    final db = _database;
    if (db == null) return null;

    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final id = await _computeId(source);
    final existing = state.documents[id];
    final now = DateTime.now();

    if (existing != null && await File(existing.storedPath).exists()) {
      return _upsert(existing.copyWith(lastOpenedAt: now));
    }

    final dir = await _ensureLibraryDir();
    final stored = p.join(dir.path, '$id.pdf');
    await source.copy(stored);

    return _upsert(LibraryDocument(
      id: id,
      fileName: p.basename(sourcePath),
      storedPath: stored,
      addedAt: existing?.addedAt ?? now,
      lastOpenedAt: now,
      // 取り込み直しの場合は読書位置を引き継ぐ。
      isRead: existing?.isRead ?? false,
      lastPage: existing?.lastPage ?? 1,
      totalPages: existing?.totalPages ?? 0,
      isFavorite: existing?.isFavorite ?? false,
    ));
  }

  /// ファイルサイズと先頭 [_hashSampleBytes] バイトから永続 ID を作る。
  Future<String> _computeId(File file) async {
    final length = await file.length();
    final sample = await file
        .openRead(0, length < _hashSampleBytes ? length : _hashSampleBytes)
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));

    return sha1.convert([...sample, ...'$length'.codeUnits]).toString();
  }

  // -------------------------------------------------------------- 更新系

  /// 開いた時刻を記録する。
  Future<void> markOpened(String id) async {
    final doc = state.documents[id];
    if (doc == null) return;
    await _upsert(doc.copyWith(lastOpenedAt: DateTime.now()));
  }

  /// 読書位置を保存する。
  Future<void> updateProgress(
    String id, {
    required int lastPage,
    required int totalPages,
  }) async {
    final doc = state.documents[id];
    if (doc == null) return;
    await _upsert(doc.copyWith(
      lastPage: lastPage,
      totalPages: totalPages,
      isRead: totalPages > 0 && lastPage >= totalPages,
      lastOpenedAt: DateTime.now(),
    ));
  }

  Future<void> toggleFavorite(String id) async {
    final doc = state.documents[id];
    if (doc == null) return;
    await _upsert(doc.copyWith(isFavorite: !doc.isFavorite));
  }

  /// ライブラリから完全に削除する。実体・DB レコードの両方を消す。
  Future<void> remove(String id) async {
    final doc = state.documents[id];
    if (doc == null) return;

    final file = File(doc.storedPath);
    if (await file.exists()) {
      await file.delete();
    }
    await _database?.delete(_tableName, where: 'id = ?', whereArgs: [id]);

    final updated = Map<String, LibraryDocument>.from(state.documents)..remove(id);
    state = state.copyWith(documents: updated);
  }

  Future<LibraryDocument> _upsert(LibraryDocument doc) async {
    await _database?.insert(
      _tableName,
      doc.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final updated = Map<String, LibraryDocument>.from(state.documents);
    updated[doc.id] = doc;
    state = state.copyWith(documents: updated);
    return doc;
  }

  LibraryDocument? getById(String id) => state.documents[id];

  // ------------------------------------------------------- ディレクトリ

  Future<void> addDirectory(String directoryPath) async {
    if (state.directories.contains(directoryPath)) return;
    final updated = [...state.directories, directoryPath];
    state = state.copyWith(directories: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('directories', updated);
  }

  Future<void> removeDirectory(String directoryPath) async {
    final updated =
        state.directories.where((d) => d != directoryPath).toList();
    state = state.copyWith(directories: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('directories', updated);
  }
}

final libraryStoreProvider =
    NotifierProvider<LibraryStore, LibraryState>(LibraryStore.new);
