import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// ページ1枚分の寸法。pdfrx の `PdfPage` からこの形に落として渡す。
///
/// レイアウト計算を pdfrx の型から切り離しておくことで、ユニットテストで
/// PDF を用意せずに検証できる。
@immutable
class PageSize {
  final double width;
  final double height;
  const PageSize(this.width, this.height);
}

/// ページの並べ方。
enum SpreadMode {
  /// 1ページずつ縦に積む。
  singleVertical,

  /// 1ページずつ横に並べる。
  singleHorizontal,

  /// 2ページの見開きを横に並べる。
  facing,
}

/// レイアウト結果。pdfrx の `PdfPageLayout` にそのまま渡せる形。
@immutable
class PageLayoutResult {
  /// ページ番号順の矩形。
  final List<Rect> pageRects;
  final Size documentSize;

  /// 同時に見せる組。見開きなら [[0], [1,2], [3,4]] のようになる。
  /// 単ページ表示では 1 ページずつの組になる。
  final List<List<int>> groups;

  const PageLayoutResult({
    required this.pageRects,
    required this.documentSize,
    required this.groups,
  });

  /// [pageNumber]（1 始まり）が属する組を囲む矩形。
  ///
  /// 見開きでは 1 ページ分ではなく組全体にフィットさせたいので、
  /// ビューアの移動先はこの矩形を使う。
  Rect? groupBoundsOf(int pageNumber) {
    final index = pageNumber - 1;
    if (index < 0 || index >= pageRects.length) return null;

    for (final group in groups) {
      if (!group.contains(index)) continue;
      var bounds = pageRects[group.first];
      for (final i in group.skip(1)) {
        bounds = bounds.expandToInclude(pageRects[i]);
      }
      return bounds;
    }
    return pageRects[index];
  }
}

/// 見開きの始まり方。
enum FacingStart {
  /// 1ページ目を単独の表紙として置き、2-3 / 4-5 … を見開きにする。
  cover,

  /// 1-2 / 3-4 … を見開きにする。
  spread,
}

/// ページを並べて矩形を返す。
///
/// [gutter] は見開きの綴じ目に空ける幅。折りたたみ端末では
/// `FoldingInfo` から求めたヒンジ幅を渡す。
PageLayoutResult layoutPages({
  required List<PageSize> pages,
  required SpreadMode mode,
  double margin = 8.0,
  double gutter = 0,
  FacingStart facingStart = FacingStart.cover,
}) {
  if (pages.isEmpty) {
    return const PageLayoutResult(
      pageRects: [],
      documentSize: Size.zero,
      groups: [],
    );
  }

  return switch (mode) {
    SpreadMode.singleVertical => _vertical(pages, margin),
    SpreadMode.singleHorizontal => _horizontal(pages, margin),
    SpreadMode.facing => _facing(pages, margin, gutter, facingStart),
  };
}

PageLayoutResult _vertical(List<PageSize> pages, double margin) {
  final width = pages.fold(0.0, (w, p) => math.max(w, p.width)) + margin * 2;
  final rects = <Rect>[];
  var y = margin;
  for (final page in pages) {
    rects.add(
        Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height));
    y += page.height + margin;
  }
  return PageLayoutResult(
    pageRects: rects,
    documentSize: Size(width, y),
    groups: [
      for (var i = 0; i < pages.length; i++) [i]
    ],
  );
}

PageLayoutResult _horizontal(List<PageSize> pages, double margin) {
  final height = pages.fold(0.0, (h, p) => math.max(h, p.height)) + margin * 2;
  final rects = <Rect>[];
  var x = margin;
  for (final page in pages) {
    rects.add(
        Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
    x += page.width + margin;
  }
  return PageLayoutResult(
    pageRects: rects,
    documentSize: Size(x, height),
    groups: [
      for (var i = 0; i < pages.length; i++) [i]
    ],
  );
}

/// 2ページを1組にして横に並べる。
///
/// [FacingStart.cover] では 1ページ目だけ単独で置く。紙の本と同じく、
/// 表紙は片側だけに現れるため。
PageLayoutResult _facing(
  List<PageSize> pages,
  double margin,
  double gutter,
  FacingStart start,
) {
  // 各組を [左ページ index, 右ページ index?] に分ける。
  final groups = <List<int>>[];
  var index = 0;
  if (start == FacingStart.cover) {
    groups.add([0]);
    index = 1;
  }
  while (index < pages.length) {
    if (index + 1 < pages.length) {
      groups.add([index, index + 1]);
      index += 2;
    } else {
      groups.add([index]);
      index += 1;
    }
  }

  final height = pages.fold(0.0, (h, p) => math.max(h, p.height)) + margin * 2;

  // 組の幅は「最大ページ幅 x 2 + 綴じ目」で揃える。組ごとに幅が変わると
  // スワイプの見え方が不揃いになるため。
  final maxPageWidth = pages.fold(0.0, (w, p) => math.max(w, p.width));
  final groupWidth = maxPageWidth * 2 + gutter;

  final rects = List<Rect>.filled(pages.length, Rect.zero);
  var x = margin;
  for (final group in groups) {
    final centerX = x + groupWidth / 2;
    if (group.length == 1) {
      // 単独ページは組の中央に置く。
      final page = pages[group.first];
      rects[group.first] = Rect.fromLTWH(
        centerX - page.width / 2,
        (height - page.height) / 2,
        page.width,
        page.height,
      );
    } else {
      final left = pages[group[0]];
      final right = pages[group[1]];
      // 綴じ目を挟んで左右に寄せる。
      rects[group[0]] = Rect.fromLTWH(
        centerX - gutter / 2 - left.width,
        (height - left.height) / 2,
        left.width,
        left.height,
      );
      rects[group[1]] = Rect.fromLTWH(
        centerX + gutter / 2,
        (height - right.height) / 2,
        right.width,
        right.height,
      );
    }
    x += groupWidth + margin;
  }

  return PageLayoutResult(
    pageRects: rects,
    documentSize: Size(x, height),
    groups: groups,
  );
}
