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
- `lib/screens/library.dart` — ホーム。Recent / Favorite / Directory の 3 タブ + FAB でファイル選択。
- `lib/screens/viewer.dart` — `pdfx` の `PdfController` / `PdfView` による表示。タップでオーバーレイ（戻る・スクロール方向切替・お気に入り・ページスライダー・ページ番号入力）。
- `lib/screens/settings.dart` — テーマとスクロール方向のトグル。
- `lib/store/file_store.dart` — `Notifier<FileStoreState>`。Recent / Favorite / Directory と `PDFFileInfo`（既読・最終ページ・総ページ数・最終閲覧日時）を管理。
- `lib/store/settings_store.dart` — `StateNotifier<SettingsState>`。テーマとスクロール方向。
- `lib/components/confirm_dialog.dart` — `ConfirmationDialog.show()` 汎用確認ダイアログ。
- `lib/models/data_model.dart` — **未使用**。`PDFFileInfo` の実体は `file_store.dart` 側にある。

### 永続化が 2 系統に分かれている

- **sqflite** (`pdf_info.db`, `version: 3`) — `PDFFileInfo` のみ。スキーマ変更時は `version` を上げて `onUpgrade` に分岐を追加する（既存の v2/v3 マイグレーションを参照）。
- **SharedPreferences** — `recentFiles` / `favoriteFiles` / `directories`（`List<String>`）と `isDarkTheme` / `isScrollVertical`（`bool`）。

ファイルは**絶対パス文字列がキー**。ただし Android では `file_selector` が返すのは元ファイルではなく**アプリ cache 配下の UUID ディレクトリにコピーされた一時ファイル**のパス（例 `/data/user/0/net.shino3.flextapdf/cache/<uuid>/foo.pdf`）。同じファイルを開き直すたびに UUID が変わるため、Recent には同じファイルが重複して並び、読書位置も引き継がれない。永続 ID の設計変更が必要（SAF の persistable URI 権限か、コンテンツハッシュ + 自前コピー）。

## 規約

- コメントは日本語。
- Store 側のメソッドは state 更新と永続化を同一メソッド内で行う（`copyWith` → `prefs.set...`）。
- Viewer は常にダークテーマ固定（`Theme(data: darkTheme, ...)`）。

## ビルド環境

Flutter 3.44 系で動作確認済み。Android は Gradle 8.12 / AGP 8.7.3 / Kotlin 2.2.20 / Java 11。Flutter 側からはさらに新しいバージョン（Gradle 8.14+ / AGP 8.11.1+）を推奨する警告が出るが、ビルドは通る。

`key.properties` が無い環境でも debug ビルドが通るよう `android/app/build.gradle` の `signingConfigs` は存在チェックでガードしてある。外すと debug ビルドまで `path may not be null` で落ちる。

iOS / macOS は **CocoaPods 未インストールのためビルド不可**。`brew install cocoapods` が必要。

## 注意

- 依存は 2024/12 時点。`flutter analyze` に deprecated 警告が 21 件残っている（`withOpacity`、`ColorScheme.background` など）。
- `dio` / `path_provider` / `file_picker` / `google_fonts` は pubspec にあるがコードから未使用。
- `path` パッケージを `file_store.dart` が import しているが pubspec に未宣言（sqflite 経由の推移的依存に頼っている）。
- `lib/models/data_model.dart` はどこからも参照されていないデッドコード。
- `test/widget_test.dart` は `flutter create` の雛形のまま（カウンタのテスト）で、`flutter test` は失敗する。
- `shared_preferences_android` にセキュリティ勧告あり（GHSA-3hpf-ff72-j67p）。
