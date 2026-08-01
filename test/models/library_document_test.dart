import 'package:flextapdf/models/library_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final addedAt = DateTime.utc(2026, 1, 1, 9, 0);
  final openedAt = DateTime.utc(2026, 2, 3, 12, 34, 56);

  LibraryDocument sample() => LibraryDocument(
        id: 'abc123',
        fileName: 'sample.pdf',
        storedPath: '/library/abc123.pdf',
        isRead: true,
        lastPage: 7,
        totalPages: 20,
        isFavorite: true,
        addedAt: addedAt,
        lastOpenedAt: openedAt,
      );

  group('LibraryDocument', () {
    test('未指定のページは 1 始まり', () {
      final doc = LibraryDocument(
        id: 'x',
        fileName: 'x.pdf',
        storedPath: '/x.pdf',
        addedAt: addedAt,
        lastOpenedAt: openedAt,
      );

      // pdfx のページは 1 始まりなので、既定値が 0 だと
      // initialPage: 0 になって範囲外になる。
      expect(doc.lastPage, 1);
      expect(doc.totalPages, 0);
      expect(doc.isRead, isFalse);
      expect(doc.isFavorite, isFalse);
    });

    test('toMap / fromMap で往復できる', () {
      final restored = LibraryDocument.fromMap(sample().toMap());

      expect(restored.id, 'abc123');
      expect(restored.fileName, 'sample.pdf');
      expect(restored.storedPath, '/library/abc123.pdf');
      expect(restored.isRead, isTrue);
      expect(restored.lastPage, 7);
      expect(restored.totalPages, 20);
      expect(restored.isFavorite, isTrue);
      expect(restored.addedAt, addedAt);
      expect(restored.lastOpenedAt, openedAt);
    });

    test('bool は sqlite 用に 0/1 で保存される', () {
      final map = sample().toMap();

      expect(map['isRead'], 1);
      expect(map['isFavorite'], 1);
    });

    test('copyWith は id と addedAt を変更しない', () {
      final updated = sample().copyWith(lastPage: 12, isFavorite: false);

      expect(updated.id, 'abc123');
      expect(updated.addedAt, addedAt);
      expect(updated.lastPage, 12);
      expect(updated.isFavorite, isFalse);
      // 指定しなかったフィールドは維持される
      expect(updated.totalPages, 20);
      expect(updated.fileName, 'sample.pdf');
    });
  });
}
