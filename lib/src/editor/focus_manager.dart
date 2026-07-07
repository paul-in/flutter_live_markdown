import 'package:super_editor/super_editor.dart';

class FocusManager {
  final EditorState editorState;
  final Set<String> focusedNodeIds = {};

  FocusManager(this.editorState);

  List<EditRequest> onFocus(String nodeId) {
    return [];
  }

  List<EditRequest> onBlur(String nodeId) {
    return [];
  }

  void onSelectionChange() {}
}
