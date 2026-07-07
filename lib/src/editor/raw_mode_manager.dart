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
    // Debounce: wait for gesture arena to settle before reading selection
    Future.microtask(_processSelectionChange);
  }

  void _processSelectionChange() {
    final sel = editorState.composer.selection;
    if (sel == null) return;

    final nodes = _getNodes(sel);
    if (nodes.isEmpty) return;

    final node = nodes.first;
    if (_focusedNodeIds.contains(node.id)) return; // already focused

    final meta = MarkdownNodeMetadata.fromNode(node);
    if (meta.isRawMode) return; // already in raw mode

    _focusedNodeIds.add(node.id);

    // Remap selection from visual to raw offsets
    DocumentSelection? updatedSel;
    if (node is TextNode) {
      updatedSel = _remapSelectionOnFocus(node, sel);
    }

    // Replace node with raw mode version
    final raw = meta.rawMarkdown;
    final formatted = applyInlineFormatting(raw);
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

    if (updatedSel != null) {
      requests.add(ChangeSelectionRequest(
        updatedSel,
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ));
    }

    editorState.editor.execute(requests);
  }

  DocumentSelection _remapSelectionOnFocus(TextNode node, DocumentSelection sel) {
    final visual = node.text.toPlainText();
    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = meta.rawMarkdown;

    // Convert upstream/downstream positions to TextNodePosition for offset mapping
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

    // Expand to include markers at boundaries
    final baseOffset = newBase.nodePosition is TextNodePosition
        ? (newBase.nodePosition as TextNodePosition).offset
        : 0;
    final extentOffset = newExtent.nodePosition is TextNodePosition
        ? (newExtent.nodePosition as TextNodePosition).offset
        : 0;
    final formattedText = applyInlineFormatting(raw);
    final (newRawStart, newRawEnd) = expandSelectionToMarkers(
      raw,
      baseOffset,
      extentOffset,
      formattedText.spans,
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
