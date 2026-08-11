import 'package:flutter/widgets.dart';

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

/// 見開きにするかどうかの手動設定。
enum SpreadPreference {
  /// 画面の形から自動で決める。
  auto,

  /// 常に単ページ。
  single,

  /// 常に見開き。
  facing,
}

/// 見開きが成立する最小の短辺。
///
/// これを下回ると 1 ページあたりが小さくなりすぎる。iPhone の横向き
/// (393dp) を弾くための下限。
const facingMinShortSide = 480.0;

/// 見開きが成立する最小のアスペクト比（幅 / 高さ）。
///
/// 見開きは A4 を 2 枚並べた横長の形になるため、画面がおおむね正方形以上に
/// 横長でないと単ページより小さくなる。iPad の縦持ち (0.70) を弾くための下限。
const facingMinAspect = 0.9;

/// 表示領域の形から見開きにすべきか判定する。
///
/// 幅だけで判定すると iPad の縦持ち（幅 834dp）でも見開きになってしまう。
/// 短辺とアスペクト比の両方を見る。
bool shouldUseFacing(Size viewport) {
  if (viewport.width <= 0 || viewport.height <= 0) return false;
  final shortSide =
      viewport.width < viewport.height ? viewport.width : viewport.height;
  if (shortSide < facingMinShortSide) return false;
  return viewport.width / viewport.height >= facingMinAspect;
}

/// 手動設定を加味して並べ方を決める。
SpreadMode resolveSpreadMode({
  required Size viewport,
  required SpreadPreference preference,
  required Axis scrollDirection,
}) {
  final facing = switch (preference) {
    SpreadPreference.facing => true,
    SpreadPreference.single => false,
    SpreadPreference.auto => shouldUseFacing(viewport),
  };
  if (facing) return SpreadMode.facing;
  return scrollDirection == Axis.horizontal
      ? SpreadMode.singleHorizontal
      : SpreadMode.singleVertical;
}
