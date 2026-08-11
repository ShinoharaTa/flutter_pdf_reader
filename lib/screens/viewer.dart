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

/// タップでページを送る左右の帯の幅（画面比）。中央はオーバーレイの開閉。
const _tapZoneFraction = 1 / 3;

/// 綴じ目に最低限確保する幅。実機のヒンジは 1px 程度しかない。
const _minGutter = 28.0;

/// ピンチで拡大できる上限。
const _maxZoom = 4.0;

/// 表示サイズより大きく描画しておく倍率。
///
/// PdfPageView はウィジェットの箱サイズ x devicePixelRatio で描画するため、
/// 等倍のまま拡大すると引き伸ばしになってぼやける。あらかじめ大きく描いて
/// 縮小表示しておくと、拡大しても解像度が残る。
/// 実際のピクセル数は PdfPageView 側の maximumDpi で頭打ちになる。
const _superSample = 2.5;

class PDFViewerPage extends ConsumerStatefulWidget {
  /// ライブラリ内の永続 ID。ファイルパスは Store から引く。
  final String documentId;

  const PDFViewerPage({super.key, required this.documentId});

  @override
  ConsumerState<PDFViewerPage> createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends ConsumerState<PDFViewerPage> {
  String? _errorMessage;

  /// ドキュメント参照は一度だけ作る。build のたびに作り直すと
  /// PDF が毎回読み込み直され、PageView も作り直されてページ送りが効かない。
  PdfDocumentRef? _documentRef;

  bool _isOverlayVisible = false;
  int _currentPage = 1;
  int _totalPages = 0;

  /// 現在の並べ方でのページの組。見開きなら [[1], [2,3], [4,5]]（1 始まり）。
  List<List<int>> _groups = const [];

  PageController? _pageController;

  /// _pageController が指している組の index。
  int _groupIndex = 0;

  /// いま拡大中か。拡大中はページ送りを止めてパンを優先する。
  bool _isZoomed = false;

  final TextEditingController _pageFieldController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'pdf-viewer-keys');
  Timer? _saveDebounce;

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
    _documentRef = PdfDocumentRefFile(doc.storedPath);
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
    _pageController?.dispose();
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

  // ------------------------------------------------------------ 組の管理

  /// 並べ方が変わったら組を作り直し、いま読んでいるページを含む組へ合わせる。
  ///
  /// 折りたたみ・展開で単ページ⇔見開きが切り替わっても、現在ページが
  /// 飛ばないようにするのがここの役目。
  void _rebuildGroups(layout.SpreadMode mode) {
    final groups = layout.groupPages(
      pageCount: _totalPages,
      mode: mode,
      facingStart: layout.FacingStart.cover,
    );
    if (_listEquals(groups, _groups)) return;

    final index = _indexOfGroupContaining(groups, _currentPage);
    _groups = groups;
    _groupIndex = index;

    _pageController?.dispose();
    _pageController = PageController(initialPage: index);
  }

  bool _listEquals(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  int _indexOfGroupContaining(List<List<int>> groups, int page) {
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].contains(page)) return i;
    }
    return 0;
  }

  /// PageView が動いたときに、現在ページを組の先頭に合わせる。
  void _onGroupChanged(int index) {
    if (index < 0 || index >= _groups.length) return;
    setState(() {
      _groupIndex = index;
      _currentPage = _groups[index].first;
      _pageFieldController.text = '$_currentPage';
      // ページを送ったら倍率は戻す。拡大したまま送ると迷子になる。
      _isZoomed = false;
    });
    _scheduleSave();
  }

  void _onZoomChanged(bool zoomed) {
    if (_isZoomed == zoomed) return;
    setState(() => _isZoomed = zoomed);
  }

  /// タップ位置に応じてページを送る。中央はオーバーレイの開閉。
  ///
  /// 右綴じでは進む向きが逆になるため、[_TapZone.forward] / [_TapZone.backward]
  /// への変換は _SpreadItem 側で綴じ方向を見て行う。
  void _handleTapZone(_TapZone zone) {
    // オーバーレイが出ているときは、まず閉じる操作を優先する。
    if (_isOverlayVisible) {
      _toggleOverlay();
      return;
    }
    switch (zone) {
      case _TapZone.forward:
        _nextGroup();
      case _TapZone.backward:
        _previousGroup();
      case _TapZone.center:
        _toggleOverlay();
    }
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
        _previousGroup();
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _nextGroup();
    }
  }

  void _nextGroup() => _animateToGroup(_groupIndex + 1);
  void _previousGroup() => _animateToGroup(_groupIndex - 1);

  void _animateToGroup(int index) {
    if (index < 0 || index >= _groups.length) return;
    _pageController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// ページ番号を指定して移動する。その番号を含む組へ飛ぶ。
  void _goToPage(int? page) {
    if (page == null || _totalPages <= 0) return;
    if (page < 1 || page > _totalPages) return;
    _animateToGroup(_indexOfGroupContaining(_groups, page));
  }

  // ------------------------------------------------------------ レイアウト

  /// 表示領域の形と手動設定から並べ方を決める。
  ///
  /// 幅だけで判定すると iPad の縦持ち（幅 834dp）でも見開きになってしまう。
  /// 判定は page_layout 側の純粋関数に寄せてテストできるようにしている。
  layout.SpreadMode _spreadModeFor(
    BoxConstraints constraints,
    SettingsState settings,
  ) {
    return layout.resolveSpreadMode(
      viewport: Size(constraints.maxWidth, constraints.maxHeight),
      preference: settings.spreadPreference,
      scrollDirection: settings.scrollDirection,
    );
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
    return _buildViewer(_documentRef!);
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

  Widget _buildViewer(PdfDocumentRef documentRef) {
    final settings = ref.watch(settingsStoreProvider);
    final library = ref.watch(libraryStoreProvider);
    final doc = library.documents[widget.documentId];
    final folding = FoldingInfo.of(context);

    return PdfDocumentViewBuilder(
      documentRef: documentRef,
      loadingBuilder: (context) =>
          const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error, stackTrace) =>
          _buildError('PDF を開けませんでした。ファイルが壊れている可能性があります。'),
      builder: (context, document) {
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // ページ数が確定したらここで一度だけ取り込む。
        if (_totalPages != document.pages.length) {
          _totalPages = document.pages.length;
          if (_currentPage > _totalPages) _currentPage = _totalPages;
          _groups = const [];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final mode = _spreadModeFor(constraints, settings);
            _rebuildGroups(mode);

            if (_groups.isEmpty || _pageController == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return KeyboardListener(
              focusNode: _keyboardFocusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: Stack(children: [
                Positioned.fill(
                  child: _buildPager(
                    document: document,
                    mode: mode,
                    gutter: _gutterFor(folding),
                    settings: settings,
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
                  _buildBottomBar(settings, doc?.isFavorite ?? false),
              ]),
            );
          },
        );
      },
    );
  }

  /// 1 アイテム = 1 組の PageView。
  ///
  /// スナップとページめくりは PageView が持っているものをそのまま使う。
  /// 自前で位置計算しない。
  Widget _buildPager({
    required PdfDocument document,
    required layout.SpreadMode mode,
    required double gutter,
    required SettingsState settings,
  }) {
    final vertical = mode == layout.SpreadMode.singleVertical;

    return PageView.builder(
      controller: _pageController,
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      // 右綴じでは次へで左に進む。縦スクロールには綴じ方向がない。
      reverse: !vertical && settings.bindingEdge == BindingEdge.right,
      // 拡大中はページ送りを止め、パンを優先する。
      physics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: _groups.length,
      onPageChanged: _onGroupChanged,
      itemBuilder: (context, index) {
        return _SpreadItem(
          key: ValueKey('spread-$index-${settings.bindingEdge.name}'),
          document: document,
          pages: _groups[index],
          gutter: gutter,
          bindingEdge: settings.bindingEdge,
          vertical: vertical,
          onTapZone: _handleTapZone,
          onZoomChanged: _onZoomChanged,
        );
      },
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

  Widget _buildBottomBar(SettingsState settings, bool isFavorite) {
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'スクロール方向',
                      icon: Icon(
                        settings.scrollDirection == Axis.horizontal
                            ? Icons.swap_horiz_rounded
                            : Icons.swap_vert_rounded,
                        size: 32.0,
                      ),
                      onPressed: settingsNotifier.toggleScrollDirection,
                    ),
                    IconButton(
                      tooltip: switch (settings.spreadPreference) {
                        layout.SpreadPreference.auto => '見開き: 自動',
                        layout.SpreadPreference.single => '見開き: 常に単ページ',
                        layout.SpreadPreference.facing => '見開き: 常に見開き',
                      },
                      icon: Icon(
                        switch (settings.spreadPreference) {
                          layout.SpreadPreference.auto => Icons.auto_awesome,
                          layout.SpreadPreference.single =>
                            Icons.crop_portrait,
                          layout.SpreadPreference.facing => Icons.import_contacts,
                        },
                        size: 32.0,
                      ),
                      onPressed: () {
                        const order = layout.SpreadPreference.values;
                        final next = order[
                            (order.indexOf(settings.spreadPreference) + 1) %
                                order.length];
                        settingsNotifier.setSpreadPreference(next);
                      },
                    ),
                    IconButton(
                      tooltip: settings.bindingEdge == BindingEdge.left
                          ? '左綴じ'
                          : '右綴じ',
                      icon: Icon(
                        settings.bindingEdge == BindingEdge.left
                            ? Icons.chrome_reader_mode_outlined
                            : Icons.chrome_reader_mode,
                        size: 32.0,
                      ),
                      onPressed: () => settingsNotifier.setBindingEdge(
                        settings.bindingEdge == BindingEdge.left
                            ? BindingEdge.right
                            : BindingEdge.left,
                      ),
                    ),
                    IconButton(
                      tooltip: 'お気に入り',
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: isFavorite ? Colors.yellow : Colors.white70,
                        size: 32.0,
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
                      onPressed: _previousGroup,
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
                      onPressed: _nextGroup,
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
    // 組が 1 つしかない場合（1ページ PDF など）が該当する。
    if (_groups.length <= 1) {
      return const SizedBox(height: 48);
    }
    return Slider(
      value: _groupIndex.clamp(0, _groups.length - 1).toDouble(),
      max: (_groups.length - 1).toDouble(),
      divisions: _groups.length - 1,
      onChanged: (value) => _animateToGroup(value.toInt()),
    );
  }
}

/// タップされた位置の意味。綴じ方向を解決した後の値。
enum _TapZone { backward, center, forward }

/// 1 組（単ページまたは見開き）を描画し、ピンチ拡大とタップ送りを受け持つ。
class _SpreadItem extends StatefulWidget {
  final PdfDocument document;

  /// 1 始まりのページ番号。1 つなら単ページ、2 つなら見開き。
  final List<int> pages;
  final double gutter;
  final BindingEdge bindingEdge;

  /// 縦送りのときは上下でタップゾーンを分ける。
  final bool vertical;
  final ValueChanged<_TapZone> onTapZone;
  final ValueChanged<bool> onZoomChanged;

  const _SpreadItem({
    super.key,
    required this.document,
    required this.pages,
    required this.gutter,
    required this.bindingEdge,
    required this.vertical,
    required this.onTapZone,
    required this.onZoomChanged,
  });

  @override
  State<_SpreadItem> createState() => _SpreadItemState();
}

class _SpreadItemState extends State<_SpreadItem> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _lastTapDown;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_notifyZoom);
  }

  @override
  void dispose() {
    _transform.removeListener(_notifyZoom);
    _transform.dispose();
    super.dispose();
  }

  void _notifyZoom() {
    // 誤差で 1.0 をわずかに超えることがあるので余裕を持たせる。
    widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01);
  }

  /// ダブルタップで拡大・等倍をトグルする。
  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
      return;
    }
    final position = _lastTapDown?.localPosition;
    if (position == null) return;
    const scale = 2.5;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// タップ位置から意味を決める。
  ///
  /// 拡大中はパンを優先するため、常に中央（オーバーレイ）扱いにして
  /// 誤ってページが飛ばないようにする。
  _TapZone _zoneFor(Offset position, Size size) {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) return _TapZone.center;

    final extent = widget.vertical ? size.height : size.width;
    final along = widget.vertical ? position.dy : position.dx;
    final edge = extent * _tapZoneFraction;

    if (along < edge) {
      // 縦送りでは上が前。横送りでは綴じ方向で反転する。
      if (widget.vertical) return _TapZone.backward;
      return widget.bindingEdge == BindingEdge.right
          ? _TapZone.forward
          : _TapZone.backward;
    }
    if (along > extent - edge) {
      if (widget.vertical) return _TapZone.forward;
      return widget.bindingEdge == BindingEdge.right
          ? _TapZone.backward
          : _TapZone.forward;
    }
    return _TapZone.center;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) => widget.onTapZone(
            _zoneFor(details.localPosition, constraints.biggest),
          ),
          onDoubleTapDown: (details) => _lastTapDown = details,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1.0,
            maxScale: _maxZoom,
            child: _buildSpread(),
          ),
        );
      },
    );
  }

  Widget _buildSpread() {
    if (widget.pages.length == 1) {
      return _page(widget.pages.first);
    }

    // 右綴じでは若い番号を右に置く。
    final ordered = widget.bindingEdge == BindingEdge.right
        ? widget.pages.reversed.toList()
        : widget.pages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _page(ordered[0]),
          ),
        ),
        // 綴じ目。折りたたみ端末ではヒンジ幅に合わせる。
        SizedBox(width: widget.gutter),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _page(ordered[1]),
          ),
        ),
      ],
    );
  }

  /// 表示サイズより大きい箱に描かせてから縮小して置く。
  ///
  /// PdfPageView は箱サイズ x devicePixelRatio で描画するため、そのまま
  /// 拡大すると引き伸ばしになる。先に高い解像度で描いておく。
  Widget _page(int pageNumber) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: constraints.maxWidth * _superSample,
            height: constraints.maxHeight * _superSample,
            child: PdfPageView(
              document: widget.document,
              pageNumber: pageNumber,
              alignment: Alignment.center,
              backgroundColor: Colors.black,
            ),
          ),
        );
      },
    );
  }
}
