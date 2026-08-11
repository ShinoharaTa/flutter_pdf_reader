import 'package:flextapdf/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('起動するとライブラリのタブが表示される', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    // フォルダ登録は SAF の制約で機能しなかったため廃止した (#45)
    expect(find.text('Directory'), findsNothing);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
  });

  testWidgets('設定画面へ遷移できる', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('テーマ'), findsOneWidget);
    // System を選べること（追従が潰されていた回帰の検知）
    expect(find.text('System'), findsOneWidget);
    expect(find.text('スクロール方向'), findsOneWidget);
  });
}
