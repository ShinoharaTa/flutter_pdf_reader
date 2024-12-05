import 'package:flextapdf/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flextapdf/store/file_store.dart';
import 'package:pdfx/pdfx.dart';
import 'package:flextapdf/store/settings_store.dart';

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
      final pdfInfo =
          ref.read(fileStoreProvider.notifier).getPDFInfo(widget.filePath);
      currentPage = pdfInfo?.lastPage ?? 1;
      print(pdfInfo?.lastPage);
      _pageController.text = currentPage.toString();
      _pdfController = PdfController(
          document: PdfDocument.openFile(widget.filePath),
          initialPage: currentPage);
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

  void _goToPage(int? page) {
    if (page != null && page > 0 && page <= totalPages) {
      _pdfController?.jumpToPage(page); // 該当ページに移動
      setState(() {
        currentPage = page;
      });
    } else {
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Invalid page number')),
      // );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);
    Axis scrollDirection =
        ref.watch(settingsStoreProvider).scrollDirection; // 初期スクロール方向のロード
    final fileStore = ref.watch(fileStoreProvider);
    final fileStoreNotifier = ref.read(fileStoreProvider.notifier);
    final isFavorite = fileStore.favoriteFiles.contains(widget.filePath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Theme(
        data: darkTheme,
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
              // Positioned(
              //   bottom: 16,
              //   right: 32,
              //   child: TextButton(
              //     onPressed: _toggleOverlay,
              //     child: Text("$currentPage / $totalPages"),
              //   ),
              // ),

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
                            onPressed: () async {
                              await ref
                                  .read(fileStoreProvider.notifier)
                                  .updatePDFState(
                                    widget.filePath,
                                    lastPage: currentPage,
                                    totalPages: totalPages,
                                    isRead: currentPage == totalPages,
                                  );
                              Navigator.of(context).pop();
                            },
                          ),
                          Text(
                            widget.filePath.split("/").last,
                            style: const TextStyle(fontSize: 18),
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
                                          ? Icons.swap_horiz_rounded
                                          : Icons.swap_vert_rounded,
                                      size: 36.0,
                                    ),
                                    onPressed: () => settingsNotifier
                                        .toggleScrollDirection(),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      color: isFavorite
                                          ? Colors.yellow
                                          : Colors.white70,
                                      size: 36.0,
                                    ),
                                    onPressed: () async {
                                      if (isFavorite) {
                                        await fileStoreNotifier
                                            .removeFavoriteFile(
                                                widget.filePath);
                                      } else {
                                        await fileStoreNotifier
                                            .addFavoriteFile(widget.filePath);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              Slider(
                                value: currentPage.toDouble(),
                                max: totalPages.toDouble(),
                                divisions: totalPages - 1,
                                onChanged: (double value) {
                                  _goToPage(value.toInt());
                                },
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.navigate_before_rounded,
                                      size: 36.0,
                                    ),
                                    onPressed: () => _goToPage(currentPage - 1),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        "Page: ",
                                        style: TextStyle(fontSize: 16),
                                      ),
                                      SizedBox(
                                        width: 48,
                                        child: TextField(
                                          controller: _pageController,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          onSubmitted: (value) =>
                                              _goToPage(int.tryParse(value)),
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      Text(
                                        "/ $totalPages",
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.navigate_next_rounded,
                                      size: 36.0,
                                    ),
                                    onPressed: () => _goToPage(currentPage + 1),
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
