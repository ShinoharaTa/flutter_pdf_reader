import 'package:flutter/material.dart';

class ConfirmationDialog {
  /// 汎用的な確認ダイアログを表示
  static Future<bool?> show({
    required BuildContext context,
    String? title,
    required String content,
    String? confirmText,
    String? cancelText,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: title != null ? Text(title) : null,
          content: Text(content),
          actions: [
            if (cancelText != null)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false); // `false`を返す
                },
                child: Text(cancelText),
              ),
            if (confirmText != null)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true); // `true`を返す
                },
                child: Text(confirmText),
              ),
          ],
        );
      },
    );
  }
}
