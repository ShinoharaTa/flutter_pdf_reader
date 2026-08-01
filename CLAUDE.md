# CLAUDE.md

Flutter 製の PDF リーダーアプリ。リポジトリ名は `flutter_pdf_reader`、Dart パッケージ名とアプリ名は **`flextapdf` / Flexta PDF Reader**。`import 'package:flextapdf/...'` で参照する。

## コマンド

```bash
flutter pub get
flutter analyze                    # コミット前に必ず通す
flutter run -d emulator-5554       # Android エミュレータ
flutter run -d macos               # デスクトップ確認用（最速）
flutter test
```

## アーキテクチャ

状態管理は **Riverpod**。UI は状態を持たず、2 つの Store が全永続化を担う。

- `lib/main.dart` — `ProviderScope` → `MyApp`。`lightTheme` / `darkTheme` を定義し、`navigatorKey`（グローバル）をエクスポート。
- `lib/screens/library.dart` — ホーム。Recent / Favorite / Directory の 3 タブ + FAB でファイル選択。Recent と Favorite は `_DocumentList` を共有する。
- `lib/screens/viewer.dart` — `pdfx` の `PdfController` / `PdfView` による表示。タップでオーバーレイ（戻る・スクロール方向切替・お気に入り・ページスライダー・ページ番号入力）。
- `lib/screens/settings.dart` — テーマとスクロール方向のトグル。
- `lib/store/library_store.dart` — `Notifier<LibraryState>`。ライブラリの取り込み・読書位置・お気に入り・削除をすべて担う。
- `lib/store/settings_store.dart` — `StateNotifier<SettingsState>`。テーマとスクロール方向。
- `lib/models/library_document.dart` — `LibraryDocument`。pdfx の `PdfDocument` と名前が衝突しないよう `Library` を冠している。
- `lib/components/confirm_dialog.dart` — `ConfirmationDialog.show()` 汎用確認ダイアログ。

### ファイルの取り込みと永続 ID

**`file_selector` が Android で返すのは cache 配下の UUID 付き一時パス**で、同じファイルを選び直すたびに変わる。これを ID にすると Recent が重複し読書位置も引き継がれないため、選択されたファイルは必ず `LibraryStore.importFile()` を通す。

`importFile` は「先頭 1MB + ファイルサイズ」の SHA-1 を ID とし、`getApplicationDocumentsDirectory()/library/<id>.pdf` へコピーする。同じ内容なら既存レコードに寄せるので、再取り込みしても重複せず読書位置が残る。画面側は常に `documentId` を持ち回り、生のパスを扱わない。

### 永続化

- **sqflite** (`pdf_info.db`, `version: 4`, テーブル `pdf_documents`) — ライブラリのすべて。Recent は `lastOpenedAt` 降順、Favorite は `isFavorite` で絞る。
  スキーマ変更時は `_dbVersion` を上げて `_openDb` の `onUpgrade` に分岐を追加する。v3 以前の `pdf_info` テーブルは一時パスを主キーにしていたため、v4 で破棄している。
- **SharedPreferences** — `directories`（`List<String>`）と `isDarkTheme` / `isScrollVertical`（`bool`）のみ。ファイル情報は置かない。

### 読書位置の保存

ページ変更のたびに 2 秒デバウンスで保存し、`PopScope` で画面離脱時に確実に書き切る。オーバーレイの戻るボタンだけでなく、システムバック・スワイプバックでも保存される。

## 規約

- コメントは日本語。
- Store 側のメソッドは state 更新と永続化を同一メソッド内で行う（`_upsert` が DB 書き込みと state 更新の両方をやる）。
- Viewer は常にダークテーマ固定（`Theme(data: darkTheme, ...)`）。

## ビルド環境

Flutter 3.44 系で動作確認済み。Android は Gradle 8.12 / AGP 8.7.3 / Kotlin 2.2.20 / Java 11。Flutter 側からはさらに新しいバージョン（Gradle 8.14+ / AGP 8.11.1+）を推奨する警告が出るが、ビルドは通る。

`key.properties` が無い環境でも debug ビルドが通るよう `android/app/build.gradle` の `signingConfigs` は存在チェックでガードしてある。外すと debug ビルドまで `path may not be null` で落ちる。

iOS / macOS は **CocoaPods 未インストールのためビルド不可**。`brew install cocoapods` が必要。

## 注意

- 依存は 2024/12 時点。`flutter analyze` の警告は `lib/main.dart` に 5 件残っている（Issue #21）。
- `dio` / `file_picker` / `google_fonts` は pubspec にあるがコードから未使用（Issue #20）。
- `test/widget_test.dart` は `flutter create` の雛形のまま（カウンタのテスト）で、`flutter test` は失敗する。
- `shared_preferences_android` にセキュリティ勧告あり（GHSA-3hpf-ff72-j67p）。
