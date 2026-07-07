import 'package:super_editor/super_editor.dart';

class SelectionController {
  final EditorState editorState;

  SelectionController(this.editorState);

  int getGlobalRawOffset(DocumentPosition position) {
    return 0;
  }

  (int, int) getSelectionOffsets() {
    final sel = editorState.composer.selection;
    if (sel == null) return (0, 0);
    return (getGlobalRawOffset(sel.base), getGlobalRawOffset(sel.extent));
  }

  String getContentBetween(int start, int end) {
    return '';
  }

  void scrollTo(int rawOffset) {}

  void clearSelection() {
    editorState.composer.clearSelection();
  }
}
