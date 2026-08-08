import 'package:flextapdf/foldable/page_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('単ページ', () {
    test('1ページずつの組になる', () {
      expect(
        groupPages(pageCount: 3, mode: SpreadMode.singleHorizontal),
        [
          [1],
          [2],
          [3]
        ],
      );
    });

    test('縦送りでも組の分け方は同じ', () {
      expect(
        groupPages(pageCount: 2, mode: SpreadMode.singleVertical),
        [
          [1],
          [2]
        ],
      );
    });
  });

  group('見開き（表紙は単独）', () {
    test('5ページは [1] [2,3] [4,5]', () {
      expect(
        groupPages(pageCount: 5, mode: SpreadMode.facing),
        [
          [1],
          [2, 3],
          [4, 5]
        ],
      );
    });

    test('偶数ページは最後が単独になる', () {
      expect(
        groupPages(pageCount: 4, mode: SpreadMode.facing),
        [
          [1],
          [2, 3],
          [4]
        ],
      );
    });

    test('1ページだけなら組は1つ', () {
      expect(groupPages(pageCount: 1, mode: SpreadMode.facing), [
        [1]
      ]);
    });

    test('2ページなら表紙と単独の2組', () {
      expect(
        groupPages(pageCount: 2, mode: SpreadMode.facing),
        [
          [1],
          [2]
        ],
      );
    });
  });

  group('見開き（1ページ目から組にする）', () {
    test('4ページは [1,2] [3,4]', () {
      expect(
        groupPages(
          pageCount: 4,
          mode: SpreadMode.facing,
          facingStart: FacingStart.spread,
        ),
        [
          [1, 2],
          [3, 4]
        ],
      );
    });

    test('奇数ページなら最後が単独', () {
      expect(
        groupPages(
          pageCount: 5,
          mode: SpreadMode.facing,
          facingStart: FacingStart.spread,
        ),
        [
          [1, 2],
          [3, 4],
          [5]
        ],
      );
    });
  });

  group('不変条件', () {
    test('ページ数が0以下なら空', () {
      expect(groupPages(pageCount: 0, mode: SpreadMode.facing), isEmpty);
      expect(groupPages(pageCount: -1, mode: SpreadMode.facing), isEmpty);
    });

    test('すべてのページが過不足なく1回だけ現れる', () {
      for (final mode in SpreadMode.values) {
        for (final count in [1, 2, 3, 7, 20]) {
          final flat =
              groupPages(pageCount: count, mode: mode).expand((g) => g).toList();
          expect(flat, [for (var i = 1; i <= count; i++) i],
              reason: 'mode=$mode count=$count');
        }
      }
    });

    test('見開きの組は最大2ページ', () {
      final groups = groupPages(pageCount: 20, mode: SpreadMode.facing);
      for (final group in groups) {
        expect(group.length, lessThanOrEqualTo(2));
        expect(group, isNotEmpty);
      }
    });
  });
}
