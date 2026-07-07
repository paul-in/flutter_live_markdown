import 'package:flutter/foundation.dart';

class LiveMarkdownController extends ChangeNotifier {
  String _text = '';
  bool _hasUndo = false;
  bool _hasRedo = false;
  bool _isShowKeyboard = true;

  // Package-private references wired by LiveMarkdownEditor
  dynamic editorState;
  dynamic rawModeManager;
  dynamic selectionController;

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
    editorState?.initializeFromMarkdown(markdown);
    notifyListeners();
    onChange?.call();
  }

  (int, int) getSelectionOffsets() {
    return selectionController?.getSelectionOffsets() ?? (0, 0);
  }

  String getContentBetween(int start, int end) {
    if (selectionController != null) {
      return selectionController.getContentBetween(start, end);
    }
    // Fallback to local text when not wired to an editor
    final s = start < 0 ? 0 : start;
    final e = end > _text.length ? _text.length : end;
    if (s >= e) return '';
    return _text.substring(s, e);
  }

  void setShowKeyboard(bool visible) {
    _isShowKeyboard = visible;
    notifyListeners();
  }

  void undo() {
    editorState?.editor.undo();
  }

  void redo() {
    editorState?.editor.redo();
  }

  void scrollTo(int rawOffset) {
    selectionController?.scrollTo(rawOffset);
  }

  void blur() {
    editorState?.composer.clearSelection();
  }

  void clearSelection() {
    selectionController?.clearSelection();
  }

  void clearHistory() {
    // Not supported by super_editor directly
  }
}
