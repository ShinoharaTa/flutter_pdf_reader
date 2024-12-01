class PdfFileInfo {
  final String filePath;
  final String fileName;
  final DateTime downloadedAt;
  DateTime lastOpenedAt;
  final int fileSize;
  final int totalPages;
  int lastOpenedPage;

  PdfFileInfo({
    required this.filePath,
    required this.fileName,
    required this.downloadedAt,
    required this.lastOpenedAt,
    required this.fileSize,
    required this.totalPages,
    required this.lastOpenedPage,
  });
}
