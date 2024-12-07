import 'package:flextapdf/components/confirm_dialog.dart';
import 'package:flextapdf/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class PDFFileInfo {
  final String path;
  final bool isRead;
  final int lastPage;
  final int totalPages;
  final DateTime lastOpenedAt;

  PDFFileInfo({
    required this.path,
    this.isRead = false,
    this.lastPage = 0,
    this.totalPages = 0,
    required this.lastOpenedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'isRead': isRead ? 1 : 0,
      'lastPage': lastPage,
      'totalPages': totalPages,
      'lastOpenedAt': lastOpenedAt.toIso8601String(),
    };
  }

  factory PDFFileInfo.fromMap(Map<String, dynamic> map) {
    return PDFFileInfo(
      path: map['path'],
      isRead: map['isRead'] == 1,
      lastPage: map['lastPage'],
      totalPages: map['totalPages'],
      lastOpenedAt: DateTime.parse(map['lastOpenedAt']),
    );
  }
}

class FileStore extends Notifier<FileStoreState> {
  late Database _database;

  @override
  FileStoreState build() {
    _loadData();
    return const FileStoreState();
  }

  Future<void> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'pdf_info.db');
    _database = await openDatabase(
      path,
      version: 3,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE pdf_info(
            path TEXT PRIMARY KEY,
            isRead INTEGER NOT NULL DEFAULT 0,
            lastPage INTEGER NOT NULL DEFAULT 0,
            totalPages INTEGER NOT NULL DEFAULT 0,
            lastOpenedAt TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          // 既存のテーブルにtotalPagesカラムを追加
          await db.execute('''
            ALTER TABLE pdf_info
            ADD COLUMN totalPage INTEGER NOT NULL DEFAULT 0
          ''');
        }
        if (oldVersion < 3) {
          // 既存のテーブルにtotalPageカラムに修正追加
          await db.execute('''
            ALTER TABLE pdf_info
            RENAME COLUMN totalPage TO totalPages
          ''');
        }
      },
    );
  }

  Future<void> _resetDatabase() async {
    try {
      await _database.close();
    } catch (e) {
      print('Database already.');
    }
    try {
      String path = join(await getDatabasesPath(), 'pdf_info.db');
      _database = await openDatabase(
        path,
        version: 3,
        onCreate: (Database db, int version) async {
          // 既存のテーブルを削除
          await db.execute('DROP TABLE IF EXISTS pdf_info');
        },
      );
    } catch (e) {
      print('Database reset failed: $e');
      rethrow;
    }
  }

  // データの永続化をロード
  Future<void> _loadData() async {
    try {
      await _initDatabase();
    } catch (e) {
      print('Database initialization failed: $e');

      final context = navigatorKey.currentContext!;
      final shouldReset = await ConfirmationDialog.show(
        context: context,
        title: 'データベースエラー',
        content: 'データベースの初期化に失敗しました。データをリセットしますか？',
        confirmText: 'リセット',
        cancelText: 'キャンセル',
      );

      if (shouldReset == true) {
        await _resetDatabase();
        await _initDatabase();
      }
    }
    final prefs = await SharedPreferences.getInstance();

    // PDFファイル情報の読み込み
    final List<Map<String, dynamic>> maps = await _database.query('pdf_info');
    final Map<String, PDFFileInfo> fileInfos = {
      for (var map in maps) map['path'] as String: PDFFileInfo.fromMap(map)
    };
    print(fileInfos);

    state = state.copyWith(
      recentFiles: prefs.getStringList('recentFiles') ?? [],
      favoriteFiles: prefs.getStringList('favoriteFiles') ?? [],
      directories: prefs.getStringList('directories') ?? [],
      fileInfos: fileInfos,
    );
  }

  // Recentファイルの追加
  Future<void> addRecentFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedRecentFiles = List<String>.from(state.recentFiles);
    updatedRecentFiles.remove(filePath);
    updatedRecentFiles.insert(0, filePath);
    if (updatedRecentFiles.length > 50) {
      updatedRecentFiles.removeRange(50, updatedRecentFiles.length);
    }
    state = state.copyWith(recentFiles: updatedRecentFiles);
    await prefs.setStringList('recentFiles', updatedRecentFiles);
    await _updateFileInfo(filePath);
  }

  // Favoriteファイルの削除
  Future<void> removeRecentFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedRecentFiles = List<String>.from(state.recentFiles)
      ..remove(filePath);
    state = state.copyWith(recentFiles: updatedRecentFiles);
    await prefs.setStringList('recentFiles', updatedRecentFiles);
  }

  // Favoriteファイルの追加
  Future<void> addFavoriteFile(String filePath) async {
    if (!state.favoriteFiles.contains(filePath)) {
      final prefs = await SharedPreferences.getInstance();
      final updatedFavorites = List<String>.from(state.favoriteFiles)
        ..add(filePath);
      state = state.copyWith(favoriteFiles: updatedFavorites);
      await prefs.setStringList('favoriteFiles', updatedFavorites);
    }
  }

  // Favoriteファイルの削除
  Future<void> removeFavoriteFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedFavorites = List<String>.from(state.favoriteFiles)
      ..remove(filePath);
    state = state.copyWith(favoriteFiles: updatedFavorites);
    await prefs.setStringList('favoriteFiles', updatedFavorites);
  }

  // Directoryの追加
  Future<void> addDirectory(String directoryPath) async {
    if (!state.directories.contains(directoryPath)) {
      final prefs = await SharedPreferences.getInstance();
      final updatedDirectories = List<String>.from(state.directories)
        ..add(directoryPath);
      state = state.copyWith(directories: updatedDirectories);
      await prefs.setStringList('directories', updatedDirectories);
    }
  }

  // PDFファイル情報の更新（新規メソッド）
  Future<void> _updateFileInfo(
    String path, {
    bool? isRead,
    int? lastPage,
    int? totalPages,
  }) async {
    final existing = state.fileInfos[path];
    final info = PDFFileInfo(
      path: path,
      isRead: isRead ?? existing?.isRead ?? false,
      lastPage: lastPage ?? existing?.lastPage ?? 0,
      totalPages: totalPages ?? existing?.totalPages ?? 0,
      lastOpenedAt: DateTime.now(),
    );

    await _database.insert(
      'pdf_info',
      info.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final updatedInfos = Map<String, PDFFileInfo>.from(state.fileInfos);
    updatedInfos[path] = info;
    state = state.copyWith(fileInfos: updatedInfos);
  }

  // PDFファイルの状態更新用のパブリックメソッド
  Future<void> updatePDFState(String path,
      {bool? isRead, int? lastPage, int? totalPages}) async {
    await _updateFileInfo(path,
        isRead: isRead, lastPage: lastPage, totalPages: totalPages);
  }

  // PDFファイル情報の取得
  PDFFileInfo? getPDFInfo(String path) {
    return state.fileInfos[path];
  }
}

class FileStoreState {
  final List<String> recentFiles;
  final List<String> favoriteFiles;
  final List<String> directories;
  final Map<String, PDFFileInfo> fileInfos;

  const FileStoreState({
    this.recentFiles = const [],
    this.favoriteFiles = const [],
    this.directories = const [],
    this.fileInfos = const {},
  });

  FileStoreState copyWith({
    List<String>? recentFiles,
    List<String>? favoriteFiles,
    List<String>? directories,
    Map<String, PDFFileInfo>? fileInfos,
  }) {
    return FileStoreState(
      recentFiles: recentFiles ?? this.recentFiles,
      favoriteFiles: favoriteFiles ?? this.favoriteFiles,
      directories: directories ?? this.directories,
      fileInfos: fileInfos ?? this.fileInfos,
    );
  }
}

final fileStoreProvider = NotifierProvider<FileStore, FileStoreState>(() {
  return FileStore();
});
