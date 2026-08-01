import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../main.dart';
import '../store/library_store.dart';
import '../store/settings_store.dart';

/// ページ変更のたびに DB へ書かないよう、この間隔でまとめて保存する。
const _progressSaveDebounce = Duration(seconds: 2);

class PDFViewerPage extends ConsumerStatefulWidget {
  /// ライブラリ内の永続 ID。ファイルパスは Store から引く。
  final String documentId;

  const PDFViewerPage({super.key, required this.documentId});

  @override
  ConsumerState<PDFViewerPage> createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends ConsumerState<PDFViewerPage> {
  PdfController? _pdfController;
  String? _errorMessage;

  bool _isOverlayVisible = false;
  int _currentPage = 1;
  int _totalPages = 0;

  final TextEditingController _pageFieldController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'pdf-viewer-keys');
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final store = ref.read(libraryStoreProvider.notifier);
    final doc = store.getById(widget.documentId);

    if (doc == null) {
      setState(() => _errorMessage = 'ライブラリにファイルが見つかりませんでした。');
      return;
    }

    // lastPage は 1 始まり。保存値が壊れていても 1 未満にはしない。
    _currentPage = doc.lastPage < 1 ? 1 : doc.lastPage;
    _pageFieldController.text = '$_currentPage';

    try {
      final controller = PdfController(
        document: PdfDocument.openFile(doc.storedPath),
        initialPage: _currentPage,
      );
      // openFile は Future を返すため、失敗はこちらで待って捕まえる必要がある。
      // 同期の try/catch では届かない。
      final document = await controller.document;
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _pdfController = controller;
        _totalPages = document.pagesCount;
        if (_currentPage > _totalPages) _currentPage = _totalPages;
        _pageFieldController.text = '$_currentPage';
      });
      await store.markOpened(widget.documentId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'PDF を開けませんでした。ファイルが壊れている可能性があります。');
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _keyboardFocusNode.dispose();
    _pageFieldController.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- 進捗保存

  /// ページ変更のたびに呼ばれる。実際の書き込みはデバウンスする。
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_progressSaveDebounce, _saveProgress);
  }

  /// 画面離脱時など、確実に書き切りたいときに呼ぶ。
  void _saveProgress() {
    _saveDebounce?.cancel();
    if (_totalPages <= 0) return;
    // Notifier は画面の生存に依存しないので、await せず投げてよい。
    ref.read(libraryStoreProvider.notifier).updateProgress(
          widget.documentId,
          lastPage: _currentPage,
          totalPages: _totalPages,
        );
  }

  // ---------------------------------------------------------------- 操作

  void _toggleOverlay() {
    setState(() => _isOverlayVisible = !_isOverlayVisible);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
        _goToPage(_currentPage - 1);
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _goToPage(_currentPage + 1);
    }
  }

  void _goToPage(int? page) {
    if (page == null || _totalPages <= 0) return;
    if (page < 1 || page > _totalPages) return;

    _pdfController?.jumpToPage(page);
    setState(() {
      _currentPage = page;
      _pageFieldController.text = '$page';
    });
    _scheduleSave();
  }

  // ---------------------------------------------------------------- 描画

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 画面を離れる経路（システムバック・スワイプ・戻るボタン）すべてで保存する。
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveProgress();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Theme(
            data: darkTheme,
            child: SafeArea(child: _buildBody()),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final error = _errorMessage;
    if (error != null) return _buildError(error);

    final controller = _pdfController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildViewer(controller);
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ライブラリに戻る'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer(PdfController controller) {
    final settings = ref.watch(settingsStoreProvider);
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);
    final library = ref.watch(libraryStoreProvider);
    final doc = library.documents[widget.documentId];
    final isFavorite = doc?.isFavorite ?? false;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(children: [
        GestureDetector(
          onTap: _toggleOverlay,
          child: PdfView(
            controller: controller,
            scrollDirection: settings.scrollDirection,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
                _pageFieldController.text = '$page';
              });
              _scheduleSave();
            },
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _toggleOverlay,
          ),
        ),
        if (_isOverlayVisible) _buildTopBar(doc?.fileName ?? ''),
        if (_isOverlayVisible)
          _buildBottomBar(settings.scrollDirection, settingsNotifier, isFavorite),
      ]),
    );
  }

  Widget _buildTopBar(String fileName) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                fileName,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleOverlay,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    Axis scrollDirection,
    SettingsStore settingsNotifier,
    bool isFavorite,
  ) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
                        scrollDirection == Axis.horizontal
                            ? Icons.swap_horiz_rounded
                            : Icons.swap_vert_rounded,
                        size: 36.0,
                      ),
                      onPressed: settingsNotifier.toggleScrollDirection,
                    ),
                    IconButton(
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: isFavorite ? Colors.yellow : Colors.white70,
                        size: 36.0,
                      ),
                      onPressed: () => ref
                          .read(libraryStoreProvider.notifier)
                          .toggleFavorite(widget.documentId),
                    ),
                  ],
                ),
                _buildSlider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.navigate_before_rounded, size: 36.0),
                      onPressed: () => _goToPage(_currentPage - 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Page: ", style: TextStyle(fontSize: 16)),
                        SizedBox(
                          width: 48,
                          child: TextField(
                            controller: _pageFieldController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onSubmitted: (value) =>
                                _goToPage(int.tryParse(value)),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        Text("/ $_totalPages",
                            style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.navigate_next_rounded, size: 36.0),
                      onPressed: () => _goToPage(_currentPage + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider() {
    // Slider は divisions <= 0 と value が範囲外の両方でアサーションに落ちる。
    // 1 ページの PDF と、読み込み完了前（totalPages == 0）が該当する。
    if (_totalPages <= 1) {
      return const SizedBox(height: 48);
    }
    return Slider(
      value: _currentPage.clamp(1, _totalPages).toDouble(),
      min: 1,
      max: _totalPages.toDouble(),
      divisions: _totalPages - 1,
      onChanged: (value) => _goToPage(value.toInt()),
    );
  }
}
