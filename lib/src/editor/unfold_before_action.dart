import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import 'editor_state.dart';
import 'raw_mode_manager.dart';

class UnfoldBeforeActionHandler {
  final EditorState editorState;
  final RawModeManager rawModeManager;

  UnfoldBeforeActionHandler({
    required this.editorState,
    required this.rawModeManager,
  });

  ExecutionInstruction handle({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
      return ExecutionInstruction.continueExecution;
    }

    final selection = editContext.composer.selection;
    if (selection == null) return ExecutionInstruction.continueExecution;

    if (rawModeManager.isPointerDown) {
      rawModeManager.setPointerDown(false);
    }

    final nodesToUnfold = editContext.document
        .getNodesInside(selection.base, selection.extent)
        .map((n) => n.id)
        .toSet();

    // Backspace at beginning of a node: might merge with previous
    if (keyEvent.logicalKey == LogicalKeyboardKey.backspace && selection.isCollapsed) {
      final pos = selection.extent;
      if (pos.nodePosition is TextNodePosition && (pos.nodePosition as TextNodePosition).offset == 0) {
        final node = editContext.document.getNodeById(pos.nodeId);
        if (node != null) {
          final prevNode = editorState.document.getNodeBeforeById(node.id);
          if (prevNode is TextNode) nodesToUnfold.add(prevNode.id);
        }
      }
    }

    // Delete at end of a node: might merge with next
    if (keyEvent.logicalKey == LogicalKeyboardKey.delete && selection.isCollapsed) {
      final pos = selection.extent;
      final node = editContext.document.getNodeById(pos.nodeId);
      if (node is TextNode && pos.nodePosition is TextNodePosition &&
          (pos.nodePosition as TextNodePosition).offset == node.text.length) {
        final nextNode = editorState.document.getNodeAfterById(node.id);
        if (nextNode is TextNode) nodesToUnfold.add(nextNode.id);
      }
    }

    rawModeManager.forceUnfold(nodesToUnfold);

    return ExecutionInstruction.continueExecution;
  }
}
