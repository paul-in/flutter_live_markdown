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

  bool deferToPointerUp;
  bool cursorInsideMarkers;

  RawModeManager(this.editorState, {this.deferToPointerUp = true, this.cursorInsideMarkers = true});

  void updateConfig({bool? deferToPointerUp, bool? cursorInsideMarkers}) {
    if (deferToPointerUp != null) this.deferToPointerUp = deferToPointerUp;
    if (cursorInsideMarkers != null) this.cursorInsideMarkers = cursorInsideMarkers;
  }

  void setPointerDown(bool value) {
    _isPointerDown = value;
    if (!value && deferToPointerUp) {
      Future.microtask(_processSelectionChange);
    }
  }

  void beginApplyingFormatting() {
    _isApplyingFormatting = true;
  }

  void endApplyingFormatting() {
    _isApplyingFormatting = false;
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
    final convertedNonTextNodeIds = <String>{};

    for (final id in toBlur) {
      final node = editorState.document.getNodeById(id);
      if (node == null) continue;
      if (node is! TextNode) continue;
      requests.addAll(_onBlur(node));
    }

    for (final id in toFocus) {
      final node = editorState.document.getNodeById(id);
      if (node == null) continue;

      if (node is! TextNode) {
        // Non-TextNode block (e.g., HorizontalRuleNode):
        // defer entire conversion to post-frame callback to avoid
        // sync IME serialization on mismatched position type
        final meta = MarkdownNodeMetadata.fromNode(node);
        if (meta.isRawMode) continue;
        convertedNonTextNodeIds.add(id);
        continue;
      }

      final meta = MarkdownNodeMetadata.fromNode(node);
      if (meta.isRawMode) {
        // New raw-mode node from split (InsertNewlineAtCaretRequest inherits metadata).
        // Fix stale rawMarkdown in-place — _updateInlineFormatting post-frame will
        // recreate the AttributedText with applyInlineFormatting.
        final currentText = node.text.toPlainText();
        if (meta.rawMarkdown != currentText) {
          node.metadata['rawMarkdown'] = currentText;
        }
        continue;
      }

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

    if (requests.isNotEmpty) {
      editorState.editor.execute(requests);

      // Remap selection for all affected nodes
      final base = _remapPosition(sel.base, toBlur, toFocus, preVisualTexts);
      final extent = _remapPosition(sel.extent, toBlur, toFocus, preVisualTexts);

      // Expand selection to include markers in focused nodes
      DocumentPosition newBase = base;
      DocumentPosition newExtent = extent;

      void expandSingle() {
        final node = editorState.document.getNodeById(base.nodeId);
        if (node is! TextNode) return;
        if (base.nodePosition is! TextNodePosition) return;
        if (extent.nodePosition is! TextNodePosition) return;
        final meta = MarkdownNodeMetadata.fromNode(node);
        final raw = meta.rawMarkdown;

        final baseOffset = (base.nodePosition as TextNodePosition).offset;
        final extentOffset = (extent.nodePosition as TextNodePosition).offset;

        final visual = preVisualTexts[base.nodeId];
        if (visual == null) return;
        final (newStart, newEnd) = expandSelectionToMarkers(
          visual,
          raw,
          baseOffset,
          extentOffset,
        );
        newBase = DocumentPosition(
          nodeId: base.nodeId,
          nodePosition: TextNodePosition(offset: newStart),
        );
        newExtent = DocumentPosition(
          nodeId: extent.nodeId,
          nodePosition: TextNodePosition(offset: newEnd),
        );
      }

      void expandBaseEdge(bool baseIsEarlier) {
        final node = editorState.document.getNodeById(base.nodeId);
        if (node is! TextNode) return;
        if (base.nodePosition is! TextNodePosition) return;
        final meta = MarkdownNodeMetadata.fromNode(node);
        final visual = preVisualTexts[base.nodeId];
        if (visual == null) return;
        final offset = (base.nodePosition as TextNodePosition).offset;
        final expanded = baseIsEarlier
            ? expandStartEdge(visual, meta.rawMarkdown, offset)
            : expandEndEdge(visual, meta.rawMarkdown, offset);
        newBase = DocumentPosition(
          nodeId: base.nodeId,
          nodePosition: TextNodePosition(offset: expanded),
        );
      }

      void expandExtentEdge(bool baseIsEarlier) {
        final node = editorState.document.getNodeById(extent.nodeId);
        if (node is! TextNode) return;
        if (extent.nodePosition is! TextNodePosition) return;
        final meta = MarkdownNodeMetadata.fromNode(node);
        final visual = preVisualTexts[extent.nodeId];
        if (visual == null) return;
        final offset = (extent.nodePosition as TextNodePosition).offset;
        final expanded = baseIsEarlier
            ? expandEndEdge(visual, meta.rawMarkdown, offset)
            : expandStartEdge(visual, meta.rawMarkdown, offset);
        newExtent = DocumentPosition(
          nodeId: extent.nodeId,
          nodePosition: TextNodePosition(offset: expanded),
        );
      }

      if (base.nodeId == extent.nodeId && toFocus.contains(base.nodeId)) {
        expandSingle();
      } else {
        final baseIdx = editorState.document.getNodeIndexById(base.nodeId);
        final extentIdx = editorState.document.getNodeIndexById(extent.nodeId);
        final baseIsEarlier = baseIdx != -1 && extentIdx != -1 && baseIdx < extentIdx;

        if (toFocus.contains(base.nodeId)) expandBaseEdge(baseIsEarlier);
        if (toFocus.contains(extent.nodeId)) expandExtentEdge(baseIsEarlier);
      }

      final DocumentSelection finalSel;
      if (identical(newBase, base) && identical(newExtent, extent)) {
        finalSel = DocumentSelection(base: base, extent: extent);
      } else {
        finalSel = DocumentSelection(base: newBase, extent: newExtent);
      }
      editorState.composer.setSelectionWithReason(finalSel);
    }

    if (convertedNonTextNodeIds.isNotEmpty) {
      // Defer entire conversion to after widget tree rebuild,
      // so the new text component exists before we set TextNodePosition
      final capturedIds = Set<String>.from(convertedNonTextNodeIds);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _convertDeferredNonTextNodes(capturedIds);
      });
    }
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
      final adjusted = adjustCursorAtMarkerBoundary(preVisual, raw, mapped, insideMarkers: cursorInsideMarkers);
      return DocumentPosition(nodeId: pos.nodeId, nodePosition: TextNodePosition(offset: adjusted));
    }

    if (toBlur.contains(pos.nodeId)) {
      // Node just blurred: raw → visual offset
      // postVisual is the formatted text (after blur), raw is the raw markdown
      final mapped = mapRawToVisualOffset(postVisual, raw, currentOffset);
      return DocumentPosition(nodeId: pos.nodeId, nodePosition: TextNodePosition(offset: mapped));
    }

    return pos;
  }

  void _convertDeferredNonTextNodes(Set<String> nodeIds) {
    final requests = <EditRequest>[];
    final sel = editorState.composer.selection;

    for (final id in nodeIds) {
      final node = editorState.document.getNodeById(id);
      if (node == null || node is TextNode) continue;
      final meta = MarkdownNodeMetadata.fromNode(node);
      if (meta.isRawMode) continue;
      final formatted = applyInlineFormatting(meta.rawMarkdown);
      requests.add(ReplaceNodeRequest(
        existingNodeId: id,
        newNode: ParagraphNode(
          id: id,
          text: formatted,
          metadata: meta.copyWith(isRawMode: true).toMap(),
        ),
      ));

      // Include selection fix in the same transaction, so the presenter
      // sees the correct position type synchronously after execute
      if (sel != null) {
        final baseIsHere = sel.base.nodeId == id;
        final extentIsHere = sel.extent.nodeId == id;
        if (baseIsHere || extentIsHere) {
          final textPos = DocumentPosition(
            nodeId: id,
            nodePosition: const TextNodePosition(offset: 0),
          );
          final base = baseIsHere ? textPos : sel.base;
          final extent = extentIsHere ? textPos : sel.extent;
          requests.add(ChangeSelectionRequest(
            DocumentSelection(base: base, extent: extent),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        }
      }
    }
    if (requests.isEmpty) return;
    editorState.editor.execute(requests);
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
      final newMeta = meta.copyWith(rawMarkdown: raw, isRawMode: false);

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
