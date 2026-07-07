import 'package:flutter/foundation.dart';

class LiveMarkdownController extends ChangeNotifier {
  String _text = '';
  bool _hasUndo = false;
  bool _hasRedo = false;
  bool _isShowKeyboard = true;

  String get text => _text;
  bool get hasUndo => _hasUndo;
  bool get hasRedo => _hasRedo;
  bool get isShowKeyboard => _isShowKeyboard;

  VoidCallback? onChange;
  VoidCallback? onSelectionChange;
  VoidCallback? onFocusChange;

  LiveMarkdownController({String? initialMarkdown}) {
    if (initialMarkdown != null) {
      replaceContent(initialMarkdown);
    }
  }

  void replaceContent(String markdown) {
    _text = markdown;
    notifyListeners();
    onChange?.call();
  }

  (int, int) getSelectionOffsets() {
    return (0, 0);
  }

  String getContentBetween(int start, int end) {
    if (start < 0) start = 0;
    if (end > _text.length) end = _text.length;
    if (start >= end) return '';
    return _text.substring(start, end);
  }

  void setShowKeyboard(bool visible) {
    _isShowKeyboard = visible;
    notifyListeners();
  }

  void undo() {}
  void redo() {}
  void scrollTo(int rawOffset) {}
  void blur() {}
  void clearSelection() {}
  void clearHistory() {}

  @override
  void dispose() {
    super.dispose();
  }
}
