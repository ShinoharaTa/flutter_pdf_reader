import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import '../store/settings_store.dart';

class PDFViewerPage extends ConsumerStatefulWidget {
  final String filePath;
  final int currentPage;
  const PDFViewerPage(
      {super.key, required this.filePath, this.currentPage = 1});

  @override
  _PDFViewerPageState createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends ConsumerState<PDFViewerPage> {
  PdfController? _pdfController;
  bool _isOverlayVisible = false; // 初期状態ではオーバーレイは非表示
  int currentPage = 1; // 現在のページ
  int totalPages = 1; // 全体のページ数
  final TextEditingController _pageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      _pdfController = PdfController(
        document: PdfDocument.openFile(widget.filePath),
      );
      _pdfController!.document.then((doc) {
        setState(() {
          totalPages = doc.pagesCount;
          _pageController.text = currentPage.toString();
        });
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

  // キーボード操作の処理
  void _handleKeyEvent(event) {
    if (event) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        // 左矢印キーで前のページへ
        _pdfController?.previousPage(
          curve: Curves.ease,
          duration: const Duration(milliseconds: 200),
        );
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        // 右矢印キーで次のページへ
        _pdfController?.nextPage(
          curve: Curves.ease,
          duration: const Duration(milliseconds: 200),
        );
      }
    }
  }

  void _goToPage(String pageText) {
    final page = int.tryParse(pageText); // 入力を数値に変換
    if (page != null && page > 0 && page <= totalPages) {
      _pdfController?.jumpToPage(page); // 該当ページに移動
      setState(() {
        currentPage = page;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid page number')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);
    Axis scrollDirection =
        ref.watch(settingsStoreProvider).scrollDirection; // 初期スクロール方向のロード

    return Scaffold(
      backgroundColor: Colors.black,
      body: Theme(
        data: ThemeData.dark(),
        child: SafeArea(
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: _handleKeyEvent, // キーボード操作を検知
            child: Stack(children: [
              GestureDetector(
                onTap: _toggleOverlay,
                child: PdfView(
                  controller: _pdfController!,
                  scrollDirection: scrollDirection,
                  onPageChanged: (page) {
                    setState(() {
                      currentPage = page;
                      _pageController.text =
                          currentPage.toString(); // テキストボックスを更新
                    });
                  },
                ),
              ),
              // 右上のメニューボタン
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: _toggleOverlay,
                ),
              ),

              // 右上のメニューボタン
              Positioned(
                bottom: 16,
                right: 32,
                child: TextButton(
                  onPressed: _toggleOverlay,
                  child: Text("$currentPage / $totalPages",
                      style: TextStyle(color: Colors.white)),
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
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      settings.scrollDirection ==
                                              Axis.horizontal
                                          ? Icons
                                              .swap_horizontal_circle_outlined
                                          : Icons.swap_vertical_circle_outlined,
                                      size: 36.0,
                                    ),
                                    onPressed: () => settingsNotifier
                                        .toggleScrollDirection(),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      settings.scrollDirection ==
                                              Axis.horizontal
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      color: settings.scrollDirection ==
                                              Axis.horizontal
                                          ? Colors.yellow
                                          : Colors.white60,
                                      size: 36.0,
                                    ),
                                    onPressed: _toggleOverlay,
                                  ),
                                ],
                              ),
                              Slider(
                                value: currentPage.toDouble(),
                                max: totalPages.toDouble(),
                                divisions: totalPages - 1,
                                onChanged: (double value) {
                                  _goToPage(value.toInt().toString());
                                },
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Page: ",
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 16),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: TextField(
                                      controller: _pageController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      onSubmitted: _goToPage,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 16),
                                    ),
                                  ),
                                  // Text("$currentPage"),
                                  Text(
                                    "/ $totalPages",
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 16),
                                  ),
                                ],
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
      ),
    );
  }
}
