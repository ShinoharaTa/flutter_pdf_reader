import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import '../store/settings_store.dart';

class PDFViewerPage extends ConsumerStatefulWidget {
  final String filePath;

  const PDFViewerPage({super.key, required this.filePath});

  @override
  _PDFViewerPageState createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends ConsumerState<PDFViewerPage> {
  PdfController? _pdfController;
  bool _isOverlayVisible = false; // 初期状態ではオーバーレイは非表示

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      setState(() {
        _pdfController = PdfController(
          document: PdfDocument.openFile(widget.filePath),
        );
      });
    } catch (e) {
      _showErrorModal("Failed to open the PDF file. Please check the file.");
    }
  }

  Future<void> _showErrorModal(String message) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // ダイアログを閉じる
              Navigator.pop(context); // トップに戻る
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() {
      _isOverlayVisible = !_isOverlayVisible; // オーバーレイの表示状態を切り替え
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);
    Axis scrollDirection =
        ref.watch(settingsStoreProvider).scrollDirection; // 初期は縦スクロール

    return Scaffold(
      backgroundColor: Colors.black,
      body: Theme(
        data: ThemeData.dark().copyWith(
            // unselectedWidgetColor: Colors.grey, // チェックボックスの未選択時の色
            // toggleableActiveColor: Colors.blue, // チェックボックスの選択時の色
            ),
        child: SafeArea(
          child: Stack(children: [
            // PDFビュー
            PdfView(
              controller: _pdfController!,
              scrollDirection: scrollDirection,
            ),

            // 右上のメニューボタン
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: _toggleOverlay, // オーバーレイをトグル
              ),
            ),

            // 上部バー（オーバーレイ）
            if (_isOverlayVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _isOverlayVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    color: Colors.black.withOpacity(0.8),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          widget.filePath.split("/").last,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 18),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _toggleOverlay,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // 下部オーバーレイ（スクロール方向設定）
            if (_isOverlayVisible)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _isOverlayVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    color: Colors.black.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              title: const Text("Scroll Direction"),
                              subtitle: Text(
                                settings.scrollDirection == Axis.horizontal
                                    ? "Horizontal"
                                    : "Vertical",
                              ),
                              trailing: Switch(
                                value:
                                    settings.scrollDirection == Axis.horizontal,
                                onChanged: (value) =>
                                    settingsNotifier.toggleScrollDirection(),
                              ),
                            ),
                            ListTile(
                              title: const Text("Favorite"),
                              subtitle: Text(
                                  settings.scrollDirection == Axis.horizontal
                                      ? "Horizontal"
                                      : "Vertical"),
                              trailing: Checkbox(
                                value:
                                    settings.scrollDirection == Axis.horizontal,
                                onChanged: (value) =>
                                    settingsNotifier.toggleScrollDirection(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
