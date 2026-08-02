import 'package:flextapdf/foldable/page_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A4 相当のページ。
const _a4 = PageSize(595, 842);

List<PageSize> _pages(int count) => List.filled(count, _a4);

void main() {
  group('空のドキュメント', () {
    test('ページが無ければ空の結果', () {
      final result = layoutPages(pages: const [], mode: SpreadMode.facing);

      expect(result.pageRects, isEmpty);
      expect(result.documentSize, Size.zero);
    });
  });

  group('単ページ縦積み', () {
    test('上から順に積まれ、重ならない', () {
      final result = layoutPages(
        pages: _pages(3),
        mode: SpreadMode.singleVertical,
        margin: 8,
      );

      expect(result.pageRects, hasLength(3));
      for (var i = 1; i < 3; i++) {
        expect(
          result.pageRects[i].top,
          greaterThanOrEqualTo(result.pageRects[i - 1].bottom),
        );
      }
      // 縦積みなので文書は縦長になる
      expect(result.documentSize.height, greaterThan(result.documentSize.width));
    });
  });

  group('単ページ横並び', () {
    test('左から順に並び、重ならない', () {
      final result = layoutPages(
        pages: _pages(3),
        mode: SpreadMode.singleHorizontal,
        margin: 8,
      );

      for (var i = 1; i < 3; i++) {
        expect(
          result.pageRects[i].left,
          greaterThanOrEqualTo(result.pageRects[i - 1].right),
        );
      }
      expect(result.documentSize.width, greaterThan(result.documentSize.height));
    });
  });

  group('見開き', () {
    test('表紙は単独で、以降は2ページずつ組になる', () {
      // 5ページ: [1] [2,3] [4,5]
      final result = layoutPages(
        pages: _pages(5),
        mode: SpreadMode.facing,
        gutter: 28,
      );

      final r = result.pageRects;
      // 2 と 3 は同じ組 = 縦位置が同じで横に並ぶ
      expect(r[1].top, r[2].top);
      expect(r[1].right, lessThan(r[2].left));
      // 4 と 5 も同じ組
      expect(r[3].top, r[4].top);
      expect(r[3].right, lessThan(r[4].left));
      // 組をまたぐと右へ進む
      expect(r[2].right, lessThan(r[3].left));
    });

    test('綴じ目の幅が左右ページの間に確保される', () {
      final result = layoutPages(
        pages: _pages(3),
        mode: SpreadMode.facing,
        gutter: 28,
      );

      // 2ページ目と3ページ目が見開きの組
      final gap = result.pageRects[2].left - result.pageRects[1].right;
      expect(gap, closeTo(28, 0.01));
    });

    test('表紙は組の中央に置かれる', () {
      final result = layoutPages(
        pages: _pages(3),
        mode: SpreadMode.facing,
        gutter: 28,
        margin: 8,
      );

      final cover = result.pageRects[0];
      final spreadCenter =
          (result.pageRects[1].left + result.pageRects[2].right) / 2;
      // 表紙の中心と、次の見開きの中心は組の幅ぶんだけ離れる
      expect(cover.center.dx, lessThan(spreadCenter));
      // 表紙は片側に寄らず組の中央に来る
      final groupWidth = 595 * 2 + 28;
      expect(cover.center.dx, closeTo(8 + groupWidth / 2, 0.01));
    });

    test('FacingStart.spread なら1ページ目から組になる', () {
      final result = layoutPages(
        pages: _pages(4),
        mode: SpreadMode.facing,
        gutter: 28,
        facingStart: FacingStart.spread,
      );

      final r = result.pageRects;
      // 1 と 2 が同じ組
      expect(r[0].top, r[1].top);
      expect(r[0].right, lessThan(r[1].left));
    });

    test('総ページ数が偶数なら最後は単独ページになる', () {
      // cover 始まりで 4ページ: [1] [2,3] [4]
      final result = layoutPages(
        pages: _pages(4),
        mode: SpreadMode.facing,
        gutter: 28,
      );

      final r = result.pageRects;
      expect(r[1].top, r[2].top);
      // 4ページ目は単独。3ページ目より右で、組の中央に来る
      expect(r[3].left, greaterThan(r[2].right));
    });

    test('1ページだけの PDF でも破綻しない', () {
      final result = layoutPages(
        pages: _pages(1),
        mode: SpreadMode.facing,
        gutter: 28,
      );

      expect(result.pageRects, hasLength(1));
      expect(result.documentSize.width, greaterThan(0));
      expect(result.documentSize.height, greaterThan(0));
      expect(result.pageRects.first.isEmpty, isFalse);
    });

    test('ページごとに寸法が違っても矩形が欠けない', () {
      final result = layoutPages(
        pages: const [PageSize(595, 842), PageSize(842, 595), PageSize(400, 400)],
        mode: SpreadMode.facing,
        gutter: 28,
      );

      expect(result.pageRects, hasLength(3));
      for (final rect in result.pageRects) {
        expect(rect, isNot(Rect.zero));
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
      }
    });

    test('すべてのページが文書サイズの内側に収まる', () {
      final result = layoutPages(
        pages: _pages(7),
        mode: SpreadMode.facing,
        gutter: 28,
        margin: 8,
      );

      final bounds = Offset.zero & result.documentSize;
      for (final rect in result.pageRects) {
        expect(bounds.contains(rect.topLeft), isTrue,
            reason: '$rect が $bounds をはみ出している');
        expect(bounds.contains(rect.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: '$rect が $bounds をはみ出している');
      }
    });
  });
}
