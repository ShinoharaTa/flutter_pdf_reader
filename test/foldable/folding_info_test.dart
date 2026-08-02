import 'dart:ui' as ui;

import 'package:flextapdf/foldable/folding_info.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// fold エミュレータの内側画面（2076x2152 px / density 390）に相当する論理サイズ。
const _screen = Size(852, 883);

MediaQueryData _mq(List<ui.DisplayFeature> features) =>
    MediaQueryData(size: _screen, displayFeatures: features);

ui.DisplayFeature _fold({
  required Rect bounds,
  required ui.DisplayFeatureState state,
  ui.DisplayFeatureType type = ui.DisplayFeatureType.fold,
}) =>
    ui.DisplayFeature(bounds: bounds, type: type, state: state);

/// 縦に走る折り目（画面を左右に分ける）。
Rect get _verticalHinge => Rect.fromLTRB(420, 0, 432, _screen.height);

/// 横に走る折り目（画面を上下に分ける）。
Rect get _horizontalHinge => Rect.fromLTRB(0, 435, _screen.width, 447);

void main() {
  group('折り目のない端末', () {
    test('displayFeatures が空なら none', () {
      final info = FoldingInfo.fromMediaQuery(_mq(const []));

      expect(info.posture, FoldPosture.none);
      expect(info.hinge, isNull);
      expect(info.isSeparating, isFalse);
      expect(info.split(Offset.zero & _screen), isNull);
    });

    test('cutout は折りたたみとして扱わない', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: const Rect.fromLTRB(400, 0, 452, 40),
          type: ui.DisplayFeatureType.cutout,
          state: ui.DisplayFeatureState.unknown,
        ),
      ]));

      expect(info.posture, FoldPosture.none);
      expect(info.isSeparating, isFalse);
    });
  });

  group('姿勢の読み取り', () {
    test('postureFlat は flat', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(bounds: _verticalHinge, state: ui.DisplayFeatureState.postureFlat),
      ]));

      expect(info.posture, FoldPosture.flat);
      expect(info.orientation, FoldOrientation.vertical);
      expect(info.hinge, _verticalHinge);
    });

    test('postureHalfOpened は halfOpened', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: _verticalHinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ]));

      expect(info.posture, FoldPosture.halfOpened);
      expect(info.isSeparating, isTrue);
    });

    test('unknown は flat として扱う', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(bounds: _verticalHinge, state: ui.DisplayFeatureState.unknown),
      ]));

      expect(info.posture, FoldPosture.flat);
    });

    test('横長の折り目は horizontal', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: _horizontalHinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ]));

      expect(info.orientation, FoldOrientation.horizontal);
      expect(info.isTabletop, isTrue);
    });

    test('縦の折り目で半開きは tabletop ではない', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: _verticalHinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ]));

      expect(info.isTabletop, isFalse);
    });
  });

  group('厚みのない折り目', () {
    test('平らに開いていれば分断しない', () {
      // 隙間のない crease。またいで描画してよい。
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: const Rect.fromLTRB(426, 0, 426, 883),
          state: ui.DisplayFeatureState.postureFlat,
        ),
      ]));

      expect(info.isSeparating, isFalse);
      expect(info.split(Offset.zero & _screen), isNull);
    });

    test('半開きなら厚みが無くても分断する', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: const Rect.fromLTRB(426, 0, 426, 883),
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ]));

      expect(info.isSeparating, isTrue);
    });
  });

  group('split', () {
    final area = Offset.zero & _screen;

    test('縦の折り目は左右に分ける', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(bounds: _verticalHinge, state: ui.DisplayFeatureState.postureFlat),
      ]));

      final parts = info.split(area);

      expect(parts, isNotNull);
      final (left, right) = parts!;
      expect(left, const Rect.fromLTRB(0, 0, 420, 883));
      expect(right, const Rect.fromLTRB(432, 0, 852, 883));
      // 折り目の帯にはどちらの領域もかからない
      expect(left.right, lessThanOrEqualTo(_verticalHinge.left));
      expect(right.left, greaterThanOrEqualTo(_verticalHinge.right));
    });

    test('横の折り目は上下に分ける', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: _horizontalHinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ]));

      final parts = info.split(area);

      expect(parts, isNotNull);
      final (top, bottom) = parts!;
      expect(top, const Rect.fromLTRB(0, 0, 852, 435));
      expect(bottom, const Rect.fromLTRB(0, 447, 852, 883));
    });

    test('AppBar の下など、ずらした領域でも折り目の位置は保たれる', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(bounds: _verticalHinge, state: ui.DisplayFeatureState.postureFlat),
      ]));

      // 上部 120 を AppBar が占めている想定の領域。
      final body = const Rect.fromLTRB(0, 120, 852, 883);
      final parts = info.split(body);

      expect(parts, isNotNull);
      final (left, right) = parts!;
      // 縦方向は渡した領域に従い、横方向は折り目に従う
      expect(left, const Rect.fromLTRB(0, 120, 420, 883));
      expect(right, const Rect.fromLTRB(432, 120, 852, 883));
    });

    test('minGutter で最小の綴じ目幅を確保する', () {
      // fold AVD の実測値。折り目は 0.41dp しか無く、そのままでは
      // 見た目上の綴じ目にならない。
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(
          bounds: const Rect.fromLTRB(425.8, 0, 426.3, 883),
          state: ui.DisplayFeatureState.postureFlat,
        ),
      ]));

      final (left, right) = info.split(area, minGutter: 24)!;

      // 折り目の中心 (426.05) を挟んで 24dp が空く
      expect(right.left - left.right, closeTo(24, 0.01));
      expect((left.right + right.left) / 2, closeTo(426.05, 0.01));
    });

    test('折り目が minGutter より太ければ実寸を優先する', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(bounds: _verticalHinge, state: ui.DisplayFeatureState.postureFlat),
      ]));

      // 折り目の実寸 12dp > minGutter 4dp
      final (left, right) = info.split(area, minGutter: 4)!;

      expect(left.right, 420);
      expect(right.left, 432);
    });

    test('折り目が領域の外なら分割しない', () {
      final info = FoldingInfo.fromMediaQuery(_mq([
        _fold(bounds: _verticalHinge, state: ui.DisplayFeatureState.postureFlat),
      ]));

      // 折り目より右だけの領域
      expect(info.split(const Rect.fromLTRB(500, 0, 852, 883)), isNull);
    });
  });

  group('FoldingInfo.of', () {
    testWidgets('BuildContext から取得できる', (tester) async {
      late FoldingInfo captured;

      await tester.pumpWidget(
        MediaQuery(
          data: _mq([
            _fold(
              bounds: _verticalHinge,
              state: ui.DisplayFeatureState.postureHalfOpened,
            ),
          ]),
          child: Builder(
            builder: (context) {
              captured = FoldingInfo.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured.posture, FoldPosture.halfOpened);
      expect(captured.orientation, FoldOrientation.vertical);
    });
  });
}
