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

    final nextIds = nodes.map((n) => n.id).toSet();
    final toBlur = _focusedNodeIds.difference(nextIds);
    final toFocus = nextIds.difference(_focusedNodeIds);

    if (toBlur.isEmpty && toFocus.isEmpty) return;

    _focusedNodeIds.clear();
    _focusedNodeIds.addAll(nextIds);

    // Build requests: blur first, then focus
    final requests = <EditRequest>[];

    for (final id in toBlur) {
      final node = editorState.document.getNodeById(id);
      if (node == null) continue;
      if (node is! TextNode) continue;
      final blurRequests = _onBlur(node);
      requests.addAll(blurRequests);
    }

    editorState.editor.execute(requests);

    // Now focus new nodes
    for (final id in toFocus) {
      final node = editorState.document.getNodeById(id);
      if (node == null) continue;
      if (node is! TextNode) continue;

      final meta = MarkdownNodeMetadata.fromNode(node);
      if (meta.isRawMode) continue;
      if (meta.rawMarkdown.isEmpty) continue;

      // Focus: replace with ParagraphNode in raw mode
      final formatted = applyInlineFormatting(meta.rawMarkdown);
      final newMeta = meta.copyWith(isRawMode: true);
      editorState.editor.execute([
        ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: ParagraphNode(
            id: node.id,
            text: formatted,
            metadata: newMeta.toMap(),
          ),
        ),
      ]);

      // Set selection position
      final updatedSel = _remapSelectionOnFocus(node, sel);
      editorState.composer.setSelectionWithReason(updatedSel);
    }
  }

  List<EditRequest> _onBlur(DocumentNode node) {
    if (node is TextNode) {
      final raw = node.text.toPlainText();
      final meta = MarkdownNodeMetadata.fromNode(node);

      // Check if this was originally a HorizontalRuleNode
      final wasHR = node is! HorizontalRuleNode && 
          (raw.trim() == '---' || raw.trim() == '***' || raw.trim() == '___');

      String innerRaw = raw;
      bool isBlockquote = false;
      if (raw.trim().startsWith('>')) {
        isBlockquote = true;
        innerRaw = raw.split('\n').map((l) {
          final match = RegExp(r'^>\s?').firstMatch(l);
          return match != null ? l.substring(match.end) : l;
        }).join('\n');
      }

      final doc = deserializeMarkdownToDocument(innerRaw);
      final newMeta = meta.copyWith(isRawMode: false);

      if (wasHR || innerRaw.trim() == '---' || innerRaw.trim() == '***' || innerRaw.trim() == '___') {
        return [
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: HorizontalRuleNode(
              id: node.id,
              metadata: newMeta.toMap(),
            ),
          ),
        ];
      }

      if (doc.isEmpty) {
        return [
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: ParagraphNode(
              id: node.id,
              text: AttributedText(''),
              metadata: newMeta.toMap(),
            ),
          ),
        ];
      }

      final parsedNode = doc.first;
      final itemMetadata = Map<String, dynamic>.from(parsedNode.metadata);
      itemMetadata.addAll(newMeta.toMap());
      if (isBlockquote) {
        itemMetadata[NodeMetadata.blockType] = blockquoteAttribution;
      }

      if (parsedNode is HorizontalRuleNode) {
        return [
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: HorizontalRuleNode(
              id: node.id,
              metadata: newMeta.toMap(),
            ),
          ),
        ];
      }

      if (parsedNode is ListItemNode) {
        return [
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: ListItemNode(
              id: node.id,
              itemType: parsedNode.type,
              text: parsedNode.text,
              indent: parsedNode.indent,
              metadata: itemMetadata,
            ),
          ),
        ];
      }

      if (parsedNode is TaskNode) {
        return [
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: TaskNode(
              id: node.id,
              text: parsedNode.text,
              isComplete: parsedNode.isComplete,
              metadata: itemMetadata,
            ),
          ),
        ];
      }

      if (parsedNode is ParagraphNode) {
        return [
          ReplaceNodeRequest(
            existingNodeId: node.id,
            newNode: ParagraphNode(
              id: node.id,
              text: parsedNode.text,
              metadata: itemMetadata,
            ),
          ),
        ];
      }

      // Fallback
      return [
        ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: ParagraphNode(
            id: node.id,
            text: parsedNode is TextNode ? parsedNode.text : AttributedText(raw),
            metadata: itemMetadata,
          ),
        ),
      ];
    }

    if (node is HorizontalRuleNode) {
      final meta = MarkdownNodeMetadata.fromNode(node);
      return [
        ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: HorizontalRuleNode(
            id: node.id,
            metadata: meta.copyWith(isRawMode: false).toMap(),
          ),
        ),
      ];
    }

    return [];
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
