import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 端末の折りたたみ姿勢。
enum FoldPosture {
  /// 折り目が無い端末、または折り目を報告していない状態。
  none,

  /// 完全に開いている（平ら）。
  flat,

  /// 半開き。ノートPC のように立てた状態や、卓上に置いた tabletop モード。
  halfOpened,
}

/// 折り目が走る向き。
enum FoldOrientation {
  /// 折り目が縦に走る。画面は左右に分かれる。
  vertical,

  /// 折り目が横に走る。画面は上下に分かれる。
  horizontal,
}

/// 折りたたみ端末の姿勢と折り目の位置。
///
/// `MediaQuery.displayFeatures` から導出する。Flutter コアの情報だけを使い、
/// プラグインには依存しない。折り目を持たない端末では [posture] が
/// [FoldPosture.none]、[hinge] が null になり、通常の1画面として扱える。
@immutable
class FoldingInfo {
  final FoldPosture posture;

  /// 折り目の矩形。**画面全体の座標系**で表される。
  /// 折り目が無ければ null。
  final Rect? hinge;

  final FoldOrientation? orientation;

  const FoldingInfo({
    required this.posture,
    this.hinge,
    this.orientation,
  });

  static const none = FoldingInfo(posture: FoldPosture.none);

  /// 折り目が画面を実際に分断しているか。
  ///
  /// 隙間のない折り目（crease）を平らに開いている場合は、コンテンツを
  /// またいで描いても問題ないので false を返す。半開きのときは物理的に
  /// 折れているため、厚みが無くても分断として扱う。
  bool get isSeparating {
    final bounds = hinge;
    if (bounds == null) return false;
    if (posture == FoldPosture.halfOpened) return true;
    return orientation == FoldOrientation.vertical
        ? bounds.width > 0
        : bounds.height > 0;
  }

  /// 卓上モード（横向きの折り目で半開き）かどうか。
  /// 上半分に表示、下半分に操作系、という配置が向く姿勢。
  bool get isTabletop =>
      posture == FoldPosture.halfOpened &&
      orientation == FoldOrientation.horizontal;

  /// [MediaQueryData] から姿勢を読み取る。
  factory FoldingInfo.fromMediaQuery(MediaQueryData data) {
    for (final feature in data.displayFeatures) {
      if (feature.type != ui.DisplayFeatureType.fold &&
          feature.type != ui.DisplayFeatureType.hinge) {
        // cutout（パンチホール等）は折りたたみとは無関係なので無視する。
        continue;
      }

      // 縦長の矩形なら折り目は縦に走っている。正方形に近い場合は
      // 画面を左右に分ける方が一般的なので vertical に倒す。
      final bounds = feature.bounds;
      final orientation = bounds.height >= bounds.width
          ? FoldOrientation.vertical
          : FoldOrientation.horizontal;

      return FoldingInfo(
        posture: switch (feature.state) {
          ui.DisplayFeatureState.postureFlat => FoldPosture.flat,
          ui.DisplayFeatureState.postureHalfOpened => FoldPosture.halfOpened,
          ui.DisplayFeatureState.unknown => FoldPosture.flat,
        },
        hinge: bounds,
        orientation: orientation,
      );
    }
    return none;
  }

  static FoldingInfo of(BuildContext context) =>
      FoldingInfo.fromMediaQuery(MediaQuery.of(context));

  /// [area] を折り目で 2 つに割る。
  ///
  /// [area] は **画面全体の座標系**で渡す。ウィジェットのローカル座標を
  /// そのまま渡すと綴じ目がずれるため、変換はここに閉じ込めている。
  ///
  /// [minGutter] は空ける最小の幅。実機の折り目は 1px しか無いことがあり
  /// （fold AVD は 0.41dp）、そのまま使うと見た目上の綴じ目にならないため、
  /// 折り目の中心を基準に最低限の幅を確保する。
  ///
  /// 分断していない、または折り目が [area] の外にあるときは null。
  /// 縦の折り目なら (左, 右)、横の折り目なら (上, 下) を返す。
  (Rect, Rect)? split(Rect area, {double minGutter = 0}) {
    if (!isSeparating) return null;
    final bounds = hinge!;

    if (orientation == FoldOrientation.vertical) {
      // 折り目が area を跨いでいなければ分割しない。
      if (bounds.left <= area.left || bounds.right >= area.right) return null;

      final center = bounds.center.dx;
      final half = (bounds.width < minGutter ? minGutter : bounds.width) / 2;
      final left = (center - half).clamp(area.left, area.right);
      final right = (center + half).clamp(area.left, area.right);
      return (
        Rect.fromLTRB(area.left, area.top, left, area.bottom),
        Rect.fromLTRB(right, area.top, area.right, area.bottom),
      );
    }

    if (bounds.top <= area.top || bounds.bottom >= area.bottom) return null;

    final center = bounds.center.dy;
    final half = (bounds.height < minGutter ? minGutter : bounds.height) / 2;
    final top = (center - half).clamp(area.top, area.bottom);
    final bottom = (center + half).clamp(area.top, area.bottom);
    return (
      Rect.fromLTRB(area.left, area.top, area.right, top),
      Rect.fromLTRB(area.left, bottom, area.right, area.bottom),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FoldingInfo &&
      other.posture == posture &&
      other.hinge == hinge &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(posture, hinge, orientation);

  @override
  String toString() =>
      'FoldingInfo(posture: $posture, hinge: $hinge, orientation: $orientation)';
}
