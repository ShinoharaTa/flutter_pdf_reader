import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../foldable/folding_info.dart';
import '../foldable/page_layout.dart' as layout;
import '../main.dart';
import '../store/library_store.dart';
import '../store/settings_store.dart';

/// ページ変更のたびに DB へ書かないよう、この間隔でまとめて保存する。
const _progressSaveDebounce = Duration(seconds: 2);

/// 見開きに切り替える最小の幅。これ未満は 1 ページ表示のままにする。
///
/// 全開の折りたたみ端末ではヒンジ情報が報告されないことがあるため、
/// 見開きの判定は幅で行う。ヒンジは綴じ目の位置合わせにのみ使う。
const _facingMinWidth = 720.0;

/// 綴じ目に最低限確保する幅。実機のヒンジは 1px 程度しかない。
const _minGutter = 28.0;

class PDFViewerPage extends ConsumerStatefulWidget {
  /// ライブラリ内の永続 ID。ファイルパスは Store から引く。
  final String documentId;

  const PDFViewerPage({super.key, required this.documentId});

  @override
  ConsumerState<PDFViewerPage> createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends ConsumerState<PDFViewerPage> {
  final PdfViewerController _controller = PdfViewerController();

  String? _storedPath;
  String? _errorMessage;

  bool _isOverlayVisible = false;
  int _currentPage = 1;
  int _totalPages = 0;

  final TextEditingController _pageFieldController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'pdf-viewer-keys');
  Timer? _saveDebounce;

  /// 直近に組んだレイアウト。見開きの組にフィットさせるために使う。
  layout.PageLayoutResult? _layout;

  @override
  void initState() {
    super.initState();
    final doc =
        ref.read(libraryStoreProvider.notifier).getById(widget.documentId);
    if (doc == null) {
      _errorMessage = 'ライブラリにファイルが見つかりませんでした。';
      return;
    }
    // lastPage は 1 始まり。保存値が壊れていても 1 未満にはしない。
    _currentPage = doc.lastPage < 1 ? 1 : doc.lastPage;
    _pageFieldController.text = '$_currentPage';
    _storedPath = doc.storedPath;
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
    super.dispose();
  }

  // -------------------------------------------------------------- 進捗保存

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

    _showGroupOf(page);
    setState(() {
      _currentPage = page;
      _pageFieldController.text = '$page';
    });
    _scheduleSave();
  }

  /// [page] が属する組が画面に収まるように移動する。
  ///
  /// 見開きでは 1 ページ分にフィットさせると片側しか見えないため、
  /// 組全体を囲む矩形へ移動する。
  void _showGroupOf(int page) {
    if (!_controller.isReady) return;
    final bounds = _layout?.groupBoundsOf(page);
    if (bounds == null) {
      _controller.goToPage(pageNumber: page);
      return;
    }
    // anchor: all が矩形全体にフィットさせる。既定の top だと
    // 高さだけ合わせるため、見開きが画面に収まらない。
    _controller.goToArea(rect: bounds, anchor: PdfPageAnchor.all);
  }

  // ------------------------------------------------------------ レイアウト

  /// 表示領域と姿勢からページの並べ方を決める。
  layout.SpreadMode _spreadModeFor(BoxConstraints constraints, Axis scroll) {
    if (constraints.maxWidth >= _facingMinWidth) {
      return layout.SpreadMode.facing;
    }
    return scroll == Axis.horizontal
        ? layout.SpreadMode.singleHorizontal
        : layout.SpreadMode.singleVertical;
  }

  /// 綴じ目の幅。ヒンジがあればその実寸を、無ければ既定値を使う。
  double _gutterFor(FoldingInfo folding) {
    final hinge = folding.hinge;
    if (hinge == null || !folding.isSeparating) return _minGutter;
    final thickness = folding.orientation == FoldOrientation.vertical
        ? hinge.width
        : hinge.height;
    return thickness > _minGutter ? thickness : _minGutter;
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
    return _buildViewer(_storedPath!);
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

  Widget _buildViewer(String path) {
    final settings = ref.watch(settingsStoreProvider);
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);
    final library = ref.watch(libraryStoreProvider);
    final doc = library.documents[widget.documentId];
    final folding = FoldingInfo.of(context);

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mode =
                  _spreadModeFor(constraints, settings.scrollDirection);
              final gutter = _gutterFor(folding);

              return PdfViewer.file(
                path,
                controller: _controller,
                initialPageNumber: _currentPage,
                params: PdfViewerParams(
                  backgroundColor: Colors.black,
                  // 既定では最小ズームが「1ページが収まる倍率」に固定され、
                  // 見開き全体まで引けない。制限を外す。
                  sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
                    useAlternativeFitScaleAsMinScale: false,
                    minScale: 0.1,
                  ),
                  pageAnchor: PdfPageAnchor.all,
                  // pdfrx が自前でジェスチャを処理するため、外側の
                  // GestureDetector ではタップを拾えない。
                  onGeneralTap: (context, controller, details) {
                    if (details.type != PdfViewerGeneralTapType.tap) {
                      return false;
                    }
                    _toggleOverlay();
                    return true;
                  },
                  // テキスト選択が有効だとタップでオーバーレイを出す操作と
                  // 競合する。検索・選択は別途 Issue で扱う。
                  textSelectionParams:
                      const PdfTextSelectionParams(enabled: false),
                  layoutPages: (pages, params) {
                    final result = layout.layoutPages(
                      pages: pages
                          .map((p) => layout.PageSize(p.width, p.height))
                          .toList(),
                      mode: mode,
                      margin: params.margin,
                      gutter: gutter,
                    );
                    _layout = result;
                    return PdfPageLayout(
                      pageLayouts: result.pageRects,
                      documentSize: result.documentSize,
                    );
                  },
                  onViewerReady: (document, controller) {
                    setState(() {
                      _totalPages = document.pages.length;
                      if (_currentPage > _totalPages) {
                        _currentPage = _totalPages;
                      }
                      _pageFieldController.text = '$_currentPage';
                    });
                    // レイアウトとビューサイズが確定してから組に合わせる。
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showGroupOf(_currentPage);
                    });
                  },
                  onPageChanged: (page) {
                    if (page == null) return;
                    setState(() {
                      _currentPage = page;
                      _pageFieldController.text = '$page';
                    });
                    _scheduleSave();
                  },
                  errorBannerBuilder:
                      (context, error, stackTrace, documentRef) =>
                          _buildError('PDF を開けませんでした。ファイルが壊れている可能性があります。'),
                ),
              );
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
          _buildBottomBar(
            settings.scrollDirection,
            settingsNotifier,
            doc?.isFavorite ?? false,
          ),
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
                      icon:
                          const Icon(Icons.navigate_before_rounded, size: 36.0),
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
