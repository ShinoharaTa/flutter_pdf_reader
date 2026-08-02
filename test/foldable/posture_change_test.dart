import 'dart:io';
import 'dart:ui' as ui;

import 'package:flextapdf/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 展開時（内側画面）の論理サイズ。fold AVD の実測値。
const _unfolded = Size(852, 883);

/// 折りたたみ時に相当する狭い幅。
const _folded = Size(360, 883);

/// fold AVD が報告する実測のヒンジ。
final _hinge = ui.DisplayFeature(
  bounds: const Rect.fromLTRB(425.8, 0, 426.3, 883),
  type: ui.DisplayFeatureType.hinge,
  state: ui.DisplayFeatureState.postureFlat,
);

/// 姿勢を差し替えられるアプリ。MediaQuery を外から与えて
/// 折りたたみ・展開による再構築を再現する。
Widget _app({required Size size, List<ui.DisplayFeature> features = const []}) {
  return ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(size: size, displayFeatures: features),
      child: const MyApp(),
    ),
  );
}

/// ライブラリの初期ロードが終わるまで進める。
///
/// DB のオープンは実 I/O なのでウィジェットテストの疑似時計では進まない。
/// runAsync で実時間を進めてから pump する。ロード中は
/// CircularProgressIndicator が回り続けるので pumpAndSettle も使えない。
Future<void> _settleLoad(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

/// タブ切り替えのアニメーションを進める。
Future<void> _settleTab(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('flextapdf_posture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempRoot.path,
    );
    await deleteDatabase(p.join(await getDatabasesPath(), 'pdf_info.db'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  testWidgets('姿勢が変わっても選択中のタブが保たれる', (tester) async {
    await tester.pumpWidget(_app(size: _unfolded));
    await _settleLoad(tester);

    await tester.tap(find.text('Favorite'));
    await _settleTab(tester);
    expect(find.text('ビューアの星ボタンでお気に入りに追加できます'), findsOneWidget);

    // 展開 -> 半開き（ヒンジあり）
    await tester.pumpWidget(_app(size: _unfolded, features: [_hinge]));
    await _settleTab(tester);
    expect(find.text('ビューアの星ボタンでお気に入りに追加できます'), findsOneWidget);

    // 折りたたみ相当の狭い幅へ
    await tester.pumpWidget(_app(size: _folded, features: [_hinge]));
    await _settleTab(tester);
    expect(find.text('ビューアの星ボタンでお気に入りに追加できます'), findsOneWidget);
  });

  testWidgets('姿勢を往復してもライブラリが破綻しない', (tester) async {
    await tester.pumpWidget(_app(size: _unfolded));
    await _settleLoad(tester);
    expect(find.text('Library'), findsOneWidget);

    for (final size in [_folded, _unfolded, _folded, _unfolded]) {
      await tester.pumpWidget(_app(size: size, features: [_hinge]));
      await _settleTab(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Library'), findsOneWidget);
    }
  });

  testWidgets('リストにスクロール位置保持用のキーが付いている', (tester) async {
    await tester.pumpWidget(_app(size: _unfolded));
    await _settleLoad(tester);

    // Recent は空だと Center になるため、常にリストがある Directory で確認する。
    await tester.tap(find.text('Directory'));
    await _settleTab(tester);

    expect(
      find.byKey(const PageStorageKey('library-directory')),
      findsOneWidget,
    );
  });
}
