import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileStore extends Notifier<FileStoreState> {
  @override
  FileStoreState build() {
    _loadData();
    return const FileStoreState();
  }

  // データの永続化をロード
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      recentFiles: prefs.getStringList('recentFiles') ?? [],
      favoriteFiles: prefs.getStringList('favoriteFiles') ?? [],
      directories: prefs.getStringList('directories') ?? [],
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
  }

  // Favoriteファイルの削除
  Future<void> removeRecentFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedRecentFiles = List<String>.from(state.recentFiles)..remove(filePath);
    state = state.copyWith(recentFiles: updatedRecentFiles);
    await prefs.setStringList('recentFiles', updatedRecentFiles);
  }

  // Favoriteファイルの追加
  Future<void> addFavoriteFile(String filePath) async {
    if (!state.favoriteFiles.contains(filePath)) {
      final prefs = await SharedPreferences.getInstance();
      final updatedFavorites = List<String>.from(state.favoriteFiles)..add(filePath);
      state = state.copyWith(favoriteFiles: updatedFavorites);
      await prefs.setStringList('favoriteFiles', updatedFavorites);
    }
  }

  // Favoriteファイルの削除
  Future<void> removeFavoriteFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedFavorites = List<String>.from(state.favoriteFiles)..remove(filePath);
    state = state.copyWith(favoriteFiles: updatedFavorites);
    await prefs.setStringList('favoriteFiles', updatedFavorites);
  }

  // Directoryの追加
  Future<void> addDirectory(String directoryPath) async {
    if (!state.directories.contains(directoryPath)) {
      final prefs = await SharedPreferences.getInstance();
      final updatedDirectories = List<String>.from(state.directories)..add(directoryPath);
      state = state.copyWith(directories: updatedDirectories);
      await prefs.setStringList('directories', updatedDirectories);
    }
  }
}

class FileStoreState {
  final List<String> recentFiles;
  final List<String> favoriteFiles;
  final List<String> directories;

  const FileStoreState({
    this.recentFiles = const [],
    this.favoriteFiles = const [],
    this.directories = const [],
  });

  FileStoreState copyWith({
    List<String>? recentFiles,
    List<String>? favoriteFiles,
    List<String>? directories,
  }) {
    return FileStoreState(
      recentFiles: recentFiles ?? this.recentFiles,
      favoriteFiles: favoriteFiles ?? this.favoriteFiles,
      directories: directories ?? this.directories,
    );
  }
}
