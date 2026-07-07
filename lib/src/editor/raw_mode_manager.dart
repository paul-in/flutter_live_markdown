import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';
import '../model/offset_mapper.dart';
import '../model/selection_expander.dart';
import '../parsing/inline_formatter.dart';
import 'editor_state.dart';

class RawModeManager {
  final EditorState editorState;
  final Set<String> _focusedNodeIds = {};

  RawModeManager(this.editorState);

  void onSelectionChange() {
    _processSelectionChange();
  }

  void _processSelectionChange() {
    final sel = editorState.composer.selection;
    if (sel == null) return;

    final nodes = _getNodes(sel);
    if (nodes.isEmpty) return;

    final node = nodes.first;
    if (_focusedNodeIds.contains(node.id)) return;

    // Check if this node has editable raw markdown
    final meta = MarkdownNodeMetadata.fromNode(node);
    if (meta.isRawMode) return;
    if (meta.rawMarkdown.isEmpty) return;

    _focusedNodeIds.add(node.id);

    final formatted = applyInlineFormatting(meta.rawMarkdown);
    final newMeta = meta.copyWith(isRawMode: true);
    final requests = <EditRequest>[
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(
          id: node.id,
          text: formatted,
          metadata: newMeta.toMap(),
        ),
      ),
    ];

    editorState.editor.execute(requests);

    // Set selection AFTER execute to avoid mid-transaction position mismatch
    if (node is TextNode) {
      final updatedSel = _remapSelectionOnFocus(node, sel);
      editorState.composer.setSelectionWithReason(updatedSel);
    } else {
      editorState.composer.setSelectionWithReason(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    }
  }

  DocumentSelection _remapSelectionOnFocus(TextNode node, DocumentSelection sel) {
    final visual = node.text.toPlainText();
    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = meta.rawMarkdown;

    DocumentPosition basePos = sel.base;
    DocumentPosition extentPos = sel.extent;
    if (basePos.nodePosition is UpstreamDownstreamNodePosition) {
      basePos = DocumentPosition(nodeId: node.id, nodePosition: const TextNodePosition(offset: 0));
    }
    if (extentPos.nodePosition is UpstreamDownstreamNodePosition) {
      final end = node.text.toPlainText().length;
      extentPos = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: end));
    }

    DocumentPosition? newBase = sel.base;
    DocumentPosition? newExtent = sel.extent;

    if (sel.base.nodeId == node.id && sel.base.nodePosition is TextNodePosition) {
      final pos = sel.base.nodePosition as TextNodePosition;
      final mapped = mapVisualToRawOffset(visual, raw, pos.offset);
      newBase = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: mapped));
    }
    if (sel.extent.nodeId == node.id && sel.extent.nodePosition is TextNodePosition) {
      final pos = sel.extent.nodePosition as TextNodePosition;
      final mapped = mapVisualToRawOffset(visual, raw, pos.offset);
      newExtent = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: mapped));
    }

    final baseOffset = newBase.nodePosition is TextNodePosition
        ? (newBase.nodePosition as TextNodePosition).offset
        : 0;
    final extentOffset = newExtent.nodePosition is TextNodePosition
        ? (newExtent.nodePosition as TextNodePosition).offset
        : 0;
    final formattedText = applyInlineFormatting(raw);
    final (newRawStart, newRawEnd) = expandSelectionToMarkers(
      raw, baseOffset, extentOffset, formattedText.spans,
    );

    return DocumentSelection(
      base: DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: newRawStart)),
      extent: DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: newRawEnd)),
    );
  }

  List<DocumentNode> _getNodes(DocumentSelection sel) {
    try {
      return editorState.document.getNodesInside(sel.base, sel.extent);
    } catch (_) {
      return [];
    }
  }
}
