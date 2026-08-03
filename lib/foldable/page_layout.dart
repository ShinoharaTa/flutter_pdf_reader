/// ページの並べ方。
enum SpreadMode {
  /// 1ページずつ縦に送る。
  singleVertical,

  /// 1ページずつ横に送る。
  singleHorizontal,

  /// 2ページの見開きで送る。
  facing,
}

/// 見開きの始まり方。
enum FacingStart {
  /// 1ページ目を単独の表紙として置き、2-3 / 4-5 … を見開きにする。
  cover,

  /// 1-2 / 3-4 … を見開きにする。
  spread,
}

/// ページを「同時に見せる組」に分ける。
///
/// 返すのは **1 始まりのページ番号**のリスト。見開きなら
/// `[[1], [2,3], [4,5]]` のようになる。
///
/// 矩形の計算はしない。表示は PageView が 1 アイテム = 1 組として扱い、
/// 各ページの配置は Row と PdfPageView に任せる。位置を自前で計算すると
/// ページャにならず、スナップもページめくりも失われる。
List<List<int>> groupPages({
  required int pageCount,
  required SpreadMode mode,
  FacingStart facingStart = FacingStart.cover,
}) {
  if (pageCount <= 0) return const [];

  if (mode != SpreadMode.facing) {
    return [for (var i = 1; i <= pageCount; i++) [i]];
  }

  final groups = <List<int>>[];
  var page = 1;
  if (facingStart == FacingStart.cover) {
    groups.add([1]);
    page = 2;
  }
  while (page <= pageCount) {
    if (page + 1 <= pageCount) {
      groups.add([page, page + 1]);
      page += 2;
    } else {
      groups.add([page]);
      page += 1;
    }
  }
  return groups;
}
