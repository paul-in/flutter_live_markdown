import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';
import '../model/markdown_utils.dart';
import '../model/offset_mapper.dart';
import '../model/selection_expander.dart';
import '../parsing/inline_formatter.dart';
import 'editor_state.dart';

class RawModeManager {
  final EditorState editorState;
  final Set<String> _focusedNodeIds = {};
  bool _isApplyingFormatting = false;
  bool _formattingScheduled = false;
  bool _isPointerDown = false;

  final bool deferToPointerUp;

  RawModeManager(this.editorState, {this.deferToPointerUp = true});

  void setPointerDown(bool value) {
    _isPointerDown = value;
    if (!value && deferToPointerUp) {
      Future.microtask(_processSelectionChange);
    }
  }

  void onSelectionChange() {
    if (deferToPointerUp && _isPointerDown) return;
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

    // Capture visual texts BEFORE execute for later offset remapping
    final Map<String, String> preVisualTexts = {};
    for (final id in toFocus) {
      final node = editorState.document.getNodeById(id);
      if (node is TextNode) {
        preVisualTexts[id] = node.text.toPlainText();
      }
    }

    // Batch ALL blur and focus requests in a single execute
    final requests = <EditRequest>[];

    for (final id in toBlur) {
      final node = editorState.document.getNodeById(id);
      if (node == null) continue;
      if (node is! TextNode) continue;
      requests.addAll(_onBlur(node));
    }

    for (final id in toFocus) {
      final node = editorState.document.getNodeById(id);
      if (node == null) continue;
      if (node is! TextNode) continue;

      final meta = MarkdownNodeMetadata.fromNode(node);
      if (meta.isRawMode) continue;

      final formatted = applyInlineFormatting(meta.rawMarkdown);
      final blockType = node.metadata[NodeMetadata.blockType];
      final newMeta = meta.copyWith(isRawMode: true);
      final newNodeMeta = newMeta.toMap();
      if (blockType != null) newNodeMeta[NodeMetadata.blockType] = blockType;

      requests.add(ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(
          id: node.id,
          text: formatted,
          metadata: newNodeMeta,
        ),
      ));
    }

    if (requests.isEmpty) return;
    editorState.editor.execute(requests);

    // Remap selection for all affected nodes
    final base = _remapPosition(sel.base, toBlur, toFocus, preVisualTexts);
    final extent = _remapPosition(sel.extent, toBlur, toFocus, preVisualTexts);

    // Expand selection to include markers in focused nodes
    DocumentSelection finalSel;
    if (base.nodeId == extent.nodeId && toFocus.contains(base.nodeId)) {
      final node = editorState.document.getNodeById(base.nodeId);
      if (node is TextNode) {
        final meta = MarkdownNodeMetadata.fromNode(node);
        final raw = meta.rawMarkdown;
        final baseOffset = (base.nodePosition as TextNodePosition).offset;
        final extentOffset = (extent.nodePosition as TextNodePosition).offset;
        final formattedText = applyInlineFormatting(raw);
        final (newStart, newEnd) = expandSelectionToMarkers(
          raw, baseOffset, extentOffset, formattedText.spans,
        );
        finalSel = DocumentSelection(
          base: DocumentPosition(nodeId: base.nodeId, nodePosition: TextNodePosition(offset: newStart)),
          extent: DocumentPosition(nodeId: extent.nodeId, nodePosition: TextNodePosition(offset: newEnd)),
        );
      } else {
        finalSel = DocumentSelection(base: base, extent: extent);
      }
    } else {
      finalSel = DocumentSelection(base: base, extent: extent);
    }
    editorState.composer.setSelectionWithReason(finalSel);
  }

  DocumentPosition _remapPosition(
    DocumentPosition pos,
    Set<String> toBlur,
    Set<String> toFocus,
    Map<String, String> preVisualTexts,
  ) {
    if (pos.nodePosition is! TextNodePosition) return pos;

    final node = editorState.document.getNodeById(pos.nodeId);
    if (node is! TextNode) return pos;
    final currentOffset = (pos.nodePosition as TextNodePosition).offset;
    final meta = MarkdownNodeMetadata.fromNode(node);
    final postVisual = node.text.toPlainText(); // text after execute
    final raw = meta.rawMarkdown;

    if (toFocus.contains(pos.nodeId)) {
      // Node just focused: original visual → raw offset (expansion done elsewhere)
      final preVisual = preVisualTexts[pos.nodeId] ?? postVisual;
      final mapped = mapVisualToRawOffset(preVisual, raw, currentOffset);
      return DocumentPosition(nodeId: pos.nodeId, nodePosition: TextNodePosition(offset: mapped));
    }

    if (toBlur.contains(pos.nodeId)) {
      // Node just blurred: raw → visual offset
      // postVisual is the formatted text (after blur), raw is the raw markdown
      final mapped = mapRawToVisualOffset(postVisual, raw, currentOffset);
      return DocumentPosition(nodeId: pos.nodeId, nodePosition: TextNodePosition(offset: mapped));
    }

    return pos;
  }

  List<EditRequest> _onBlur(DocumentNode node) {
    if (node is TextNode) {
      final raw = node.text.toPlainText();
      final meta = MarkdownNodeMetadata.fromNode(node);

      // Check if this was originally a HorizontalRuleNode
      final wasHR = node is! HorizontalRuleNode && 
          (raw.trim() == '---' || raw.trim() == '***' || raw.trim() == '___');

      final parsed = parseBlockquote(raw);
      String innerRaw = parsed.text;
      bool isBlockquote = parsed.isBlockquote;

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

  List<DocumentNode> _getNodes(DocumentSelection sel) {
    try {
      return editorState.document.getNodesInside(sel.base, sel.extent);
    } catch (_) {
      return [];
    }
  }

  void dispose() {}

  void onDocumentChange(DocumentChangeLog changeLog) {
    if (_isApplyingFormatting) return;
    if (_focusedNodeIds.isEmpty) return;

    _scheduleFormattingUpdate();
  }

  void _scheduleFormattingUpdate() {
    if (_formattingScheduled) return;
    _formattingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _formattingScheduled = false;
      if (_isApplyingFormatting) return;
      for (final id in _focusedNodeIds) {
        _updateInlineFormatting(id);
      }
    });
  }

  void _updateInlineFormatting(String nodeId) {
    final node = editorState.document.getNodeById(nodeId);
    if (node == null) return;

    final meta = MarkdownNodeMetadata.fromNode(node);
    if (!meta.isRawMode) return;
    if (node is! TextNode) return;

    final raw = node.text.toPlainText();
    final formatted = applyInlineFormatting(raw);
    final newMeta = meta.copyWith(rawMarkdown: raw);

    // Re-parse to detect block type changes (#, >, etc.)
    final parsed = parseBlockquote(raw);
    final blockType = detectBlockType(parsed.text);

    final newNodeMeta = newMeta.toMap();
    if (blockType != null) {
      newNodeMeta[NodeMetadata.blockType] = blockType;
    }

    _isApplyingFormatting = true;
    try {
      editorState.editor.execute([
        ReplaceNodeRequest(
          existingNodeId: nodeId,
          newNode: ParagraphNode(
            id: nodeId,
            text: formatted,
            metadata: newNodeMeta,
          ),
        ),
      ]);
    } finally {
      _isApplyingFormatting = false;
    }
  }
}
