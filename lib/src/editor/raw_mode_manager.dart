import 'package:super_editor/super_editor.dart';

import 'editor_state.dart';

class RawModeManager {
  final EditorState editorState;
  final Set<String> focusedNodeIds = {};

  RawModeManager(this.editorState);

  List<EditRequest> onFocus(String nodeId) {
    return [];
  }

  List<EditRequest> onBlur(String nodeId) {
    return [];
  }

  void onSelectionChange() {}
}
