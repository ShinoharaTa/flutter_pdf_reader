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
  bool _isDualPageMode = false; // 初期状態はシングルページモード

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      // PDFをロード
      setState(() {
        _pdfController = PdfController(
          document: PdfDocument.openFile(widget.filePath),
        );
      });
    } catch (e) {
      // エラーが発生した場合にモーダルを表示
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("PDF Viewer"),
      ),
      body: Column(
        children: [
          Expanded(
            child: _pdfController == null
                ? Center(child: CircularProgressIndicator())
                : PdfView(
                    controller: _pdfController!,
                    scrollDirection: _scrollDirection,
                  ),
          ),
          Container(
            color: Colors.grey[200],
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _scrollDirection = Axis.vertical;
                    });
                  },
                  child: Text("Vertical Scroll"),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _scrollDirection = Axis.horizontal;
                    });
                  },
                  child: Text("Horizontal Scroll"),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isDualPageMode = !_isDualPageMode; // モード切り替え
                    });
                  },
                  child: Text("Par Page"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
