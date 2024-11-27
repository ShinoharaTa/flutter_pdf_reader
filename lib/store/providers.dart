import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'file_store.dart';

// FileStoreプロバイダ
final fileStoreProvider = NotifierProvider<FileStore, FileStoreState>(() {
  return FileStore();
});
