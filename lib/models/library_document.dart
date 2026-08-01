/// アプリ内ライブラリに取り込んだ PDF 1件を表す。
///
/// [id] は内容から導出した永続 ID。ファイル選択のたびに変わる一時パスと違い、
/// 同じ PDF なら常に同じ値になるため、Recent / Favorite / 読書位置の
/// 紐付けキーとして使える。
class LibraryDocument {
  /// 内容ハッシュ + サイズから導出した永続 ID。
  final String id;

  /// 取り込み時の元ファイル名。一覧の表示に使う。
  final String fileName;

  /// アプリ内ライブラリ配下の実体パス。
  final String storedPath;

  final bool isRead;

  /// 最後に開いていたページ。pdfx に合わせて 1 始まり。
  final int lastPage;

  final int totalPages;
  final bool isFavorite;
  final DateTime addedAt;
  final DateTime lastOpenedAt;

  const LibraryDocument({
    required this.id,
    required this.fileName,
    required this.storedPath,
    this.isRead = false,
    this.lastPage = 1,
    this.totalPages = 0,
    this.isFavorite = false,
    required this.addedAt,
    required this.lastOpenedAt,
  });

  LibraryDocument copyWith({
    String? fileName,
    String? storedPath,
    bool? isRead,
    int? lastPage,
    int? totalPages,
    bool? isFavorite,
    DateTime? lastOpenedAt,
  }) {
    return LibraryDocument(
      id: id,
      fileName: fileName ?? this.fileName,
      storedPath: storedPath ?? this.storedPath,
      isRead: isRead ?? this.isRead,
      lastPage: lastPage ?? this.lastPage,
      totalPages: totalPages ?? this.totalPages,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'storedPath': storedPath,
      'isRead': isRead ? 1 : 0,
      'lastPage': lastPage,
      'totalPages': totalPages,
      'isFavorite': isFavorite ? 1 : 0,
      'addedAt': addedAt.toIso8601String(),
      'lastOpenedAt': lastOpenedAt.toIso8601String(),
    };
  }

  factory LibraryDocument.fromMap(Map<String, dynamic> map) {
    return LibraryDocument(
      id: map['id'] as String,
      fileName: map['fileName'] as String,
      storedPath: map['storedPath'] as String,
      isRead: map['isRead'] == 1,
      lastPage: map['lastPage'] as int,
      totalPages: map['totalPages'] as int,
      isFavorite: map['isFavorite'] == 1,
      addedAt: DateTime.parse(map['addedAt'] as String),
      lastOpenedAt: DateTime.parse(map['lastOpenedAt'] as String),
    );
  }
}
