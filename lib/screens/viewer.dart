import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PDFViewerPage extends StatefulWidget {
  final String filePath;

  const PDFViewerPage({required this.filePath});

  @override
  _PDFViewerPageState createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends State<PDFViewerPage> {
  PdfController? _pdfController;
  Axis _scrollDirection = Axis.vertical; // 初期は縦スクロール
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
        title: Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // ダイアログを閉じる
              Navigator.pop(context); // トップに戻る
            },
            child: Text("OK"),
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
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // PDFビュー
            PdfView(
              controller: _pdfController!,
              scrollDirection: _scrollDirection,
            ),

            // 右上のメニューボタン
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: Icon(Icons.menu),
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
                  duration: Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          "PDF Viewer",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white),
                          onPressed: _toggleOverlay, // 閉じるボタン
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 下部バー（オーバーレイ）
            if (_isOverlayVisible)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _isOverlayVisible ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _scrollDirection = Axis.vertical;
                            });
                          },
                          // style: ElevatedButton.styleFrom(
                          //   primary: Colors.white,
                          //   onPrimary: Colors.black,
                          // ),
                          child: Text("Vertical Scroll"),
                        ),
                        SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _scrollDirection = Axis.horizontal;
                            });
                          },
                          // style: ElevatedButton.styleFrom(
                          //   primary: Colors.white,
                          //   onPrimary: Colors.black,
                          // ),
                          child: Text("Horizontal Scroll"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
