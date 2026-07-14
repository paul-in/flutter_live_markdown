import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';
import '../model/offset_mapper.dart';
import '../parsing/inline_formatter.dart';

ExecutionInstruction unfoldBeforeAction({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  final isBackspace = keyEvent.logicalKey == LogicalKeyboardKey.backspace;
  final isDelete = keyEvent.logicalKey == LogicalKeyboardKey.delete;
  if (!isBackspace && !isDelete) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) return ExecutionInstruction.continueExecution;

  final document = editContext.document;
  final nodesToUnfold = <String>{};

  // Always unfold current selection nodes
  for (final n in document.getNodesInside(selection.base, selection.extent)) {
    nodesToUnfold.add(n.id);
  }

  // Backspace at offset 0 — unfold previous TextNode for merge
  if (isBackspace && selection.isCollapsed) {
    final pos = selection.extent;
    final node = document.getNodeById(pos.nodeId);
    if (node is TextNode &&
        pos.nodePosition is TextNodePosition &&
        (pos.nodePosition as TextNodePosition).offset == 0) {
      final prev = document.getNodeBeforeById(node.id);
      if (prev is TextNode) nodesToUnfold.add(prev.id);
    }
  }

  // Delete at end of text — unfold next TextNode for merge
  if (isDelete && selection.isCollapsed) {
    final pos = selection.extent;
    final node = document.getNodeById(pos.nodeId);
    if (node is TextNode &&
        pos.nodePosition is TextNodePosition &&
        (pos.nodePosition as TextNodePosition).offset == node.text.length) {
      final next = document.getNodeAfterById(node.id);
      if (next is TextNode) nodesToUnfold.add(next.id);
    }
  }

  // Only process folded (formatted) nodes
  final foldedIds = nodesToUnfold.where((id) {
    final n = document.getNodeById(id);
    return n is TextNode && n.metadata['isRawMode'] != true;
  }).toList();

  if (foldedIds.isEmpty) return ExecutionInstruction.continueExecution;

  // Build unfold requests (same logic as _processSelectionChange toFocus)
  final requests = <EditRequest>[];
  DocumentSelection? newSelection = selection;

  for (final id in foldedIds) {
    final n = document.getNodeById(id);
    if (n is! TextNode) continue;
    final meta = MarkdownNodeMetadata.fromNode(n);
    if (meta.isRawMode) continue;

    // Remap visual → raw offsets for this node
    if (newSelection != null) {
      final visual = n.text.toPlainText();
      final raw = meta.rawMarkdown;
      DocumentPosition? newBase = newSelection.base;
      DocumentPosition? newExtent = newSelection.extent;

      if (newSelection.base.nodeId == id &&
          newSelection.base.nodePosition is TextNodePosition) {
        final baseOff = (newSelection.base.nodePosition as TextNodePosition).offset;
        final mapped = mapVisualToRawOffset(visual, raw, baseOff);
        newBase = DocumentPosition(nodeId: id, nodePosition: TextNodePosition(offset: mapped));
      }
      if (newSelection.extent.nodeId == id &&
          newSelection.extent.nodePosition is TextNodePosition) {
        final extOff = (newSelection.extent.nodePosition as TextNodePosition).offset;
        final mapped = mapVisualToRawOffset(visual, raw, extOff);
        newExtent = DocumentPosition(nodeId: id, nodePosition: TextNodePosition(offset: mapped));
      }
      newSelection = DocumentSelection(base: newBase, extent: newExtent);
    }

    final formatted = applyInlineFormatting(meta.rawMarkdown);
    final newMeta = meta.copyWith(isRawMode: true);
    final newNodeMeta = newMeta.toMap();
    final blockType = n.metadata[NodeMetadata.blockType];
    if (blockType != null) newNodeMeta[NodeMetadata.blockType] = blockType;

    requests.add(ReplaceNodeRequest(
      existingNodeId: id,
      newNode: ParagraphNode(id: id, text: formatted, metadata: newNodeMeta),
    ));
  }

  if (newSelection != null && newSelection != selection) {
    requests.add(ChangeSelectionRequest(
      newSelection,
      SelectionChangeType.placeCaret,
      SelectionReason.userInteraction,
    ));
  }

  editContext.editor.execute(requests);

  return ExecutionInstruction.continueExecution;
}
