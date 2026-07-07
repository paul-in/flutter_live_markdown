import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';
import '../model/offset_mapper.dart';
import '../parsing/inline_formatter.dart';
import 'editor_state.dart';

class RawModeManager {
  final EditorState editorState;
  final Set<String> _focusedNodeIds = {};
  bool _isApplyingFormatting = false;
  bool _isPointerDown = false;

  RawModeManager(this.editorState);

  Set<String> get focusedNodeIds => Set.unmodifiable(_focusedNodeIds);
  bool get isPointerDown => _isPointerDown;

  void setPointerDown(bool value) {
    _isPointerDown = value;
    if (!value) {
      onSelectionChange();
    }
  }

  void onSelectionChange() {
    if (_isApplyingFormatting) return;
    if (_isPointerDown) return;

    final sel = editorState.composer.selection;
    final nextIds = <String>{};
    if (sel != null) {
      try {
        final nodes = editorState.document.getNodesInside(sel.base, sel.extent);
        nextIds.addAll(nodes.map((n) => n.id));
      } catch (_) {}
    }

    final toBlur = _focusedNodeIds.difference(nextIds);
    final toFocus = nextIds.difference(_focusedNodeIds);

    if (toBlur.isEmpty && toFocus.isEmpty) return;

    _focusedNodeIds.clear();
    _focusedNodeIds.addAll(nextIds);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isApplyingFormatting) {
        _applyFocusBlur(toBlur, toFocus);
      }
    });
  }

  void _applyFocusBlur(Set<String> toBlur, Set<String> toFocus) {
    _isApplyingFormatting = true;
    try {
      DocumentSelection? newSelection = editorState.composer.selection;
      final requests = <EditRequest>[];

      for (final id in toBlur) {
        final node = editorState.document.getNodeById(id);
        if (node != null) {
          if (node is TextNode && newSelection != null) {
            newSelection = _remapSelectionOnBlur(node, newSelection);
          }
          final reqs = _onBlur(id);
          if (reqs.isNotEmpty) requests.addAll(reqs);
        }
      }

      if (requests.isNotEmpty) {
        editorState.editor.execute(requests);
      }

      if (newSelection != null && newSelection != editorState.composer.selection) {
        editorState.composer.setSelectionWithReason(newSelection);
      }

      _forceUnfoldNodes(toFocus);

    } finally {
      _isApplyingFormatting = false;
    }
  }

  DocumentSelection _remapSelectionOnBlur(TextNode node, DocumentSelection selection) {
    final visual = node.text.toPlainText();
    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = meta.rawMarkdown;

    DocumentPosition? newBase = selection.base;
    DocumentPosition? newExtent = selection.extent;

    if (selection.base.nodeId == node.id && selection.base.nodePosition is TextNodePosition) {
      final pos = selection.base.nodePosition as TextNodePosition;
      final mapped = mapRawToVisualOffset(visual, raw, pos.offset);
      newBase = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: mapped));
    }
    if (selection.extent.nodeId == node.id && selection.extent.nodePosition is TextNodePosition) {
      final pos = selection.extent.nodePosition as TextNodePosition;
      final mapped = mapRawToVisualOffset(visual, raw, pos.offset);
      newExtent = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: mapped));
    }
    return DocumentSelection(base: newBase, extent: newExtent);
  }

  List<EditRequest> _onFocus(String nodeId) {
    final node = editorState.document.getNodeById(nodeId);
    if (node == null) return [];
    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = meta.rawMarkdown;

    final formatted = applyInlineFormatting(raw);

    final newMeta = meta.copyWith(isRawMode: true);
    return [
      ReplaceNodeRequest(
        existingNodeId: nodeId,
        newNode: ParagraphNode(
          id: nodeId,
          text: formatted,
          metadata: newMeta.toMap(),
        ),
      ),
    ];
  }

  List<EditRequest> _onBlur(String nodeId) {
    final node = editorState.document.getNodeById(nodeId);
    if (node is! TextNode) return [];

    final raw = node.text.toPlainText();
    final meta = MarkdownNodeMetadata.fromNode(node);

    bool isBlockquote = false;
    String innerRaw = raw;
    if (raw.trim().startsWith('>')) {
      isBlockquote = true;
      innerRaw = raw.split('\n').map((l) {
        final match = RegExp(r'^>\s?').firstMatch(l);
        return match != null ? l.substring(match.end) : l;
      }).join('\n');
    }

    final doc = deserializeMarkdownToDocument(innerRaw);
    final newMeta = meta.copyWith(
      isRawMode: false,
      isBlockquote: isBlockquote,
    );

    final requests = <EditRequest>[];

    if (doc.isEmpty) {
      newMeta.rawMarkdown;
      requests.add(ReplaceNodeRequest(
        existingNodeId: nodeId,
        newNode: ParagraphNode(
          id: nodeId,
          text: AttributedText(''),
          metadata: newMeta.toMap(),
        ),
      ));
      return requests;
    }

    int insertIndex = editorState.document.getNodeIndexById(nodeId);
    if (insertIndex < 0) return [];

    requests.add(DeleteNodeRequest(nodeId: nodeId));

    for (final parsedNode in doc) {
      String serialized;
      if (doc.length == 1) {
        serialized = raw;
      } else {
        final singleDoc = MutableDocument(nodes: [parsedNode]);
        serialized = serializeDocumentToMarkdown(singleDoc).trimRight();
      }

      final itemMetadata = Map<String, dynamic>.from(parsedNode.metadata);
      itemMetadata.addAll(newMeta.copyWith(rawMarkdown: serialized).toMap());

      DocumentNode newNode;
      if (parsedNode is HorizontalRuleNode) {
        newNode = HorizontalRuleNode(id: Editor.createNodeId());
      } else if (parsedNode is ListItemNode) {
        newNode = ListItemNode(
          id: Editor.createNodeId(),
          itemType: parsedNode.type,
          text: parsedNode.text,
          indent: parsedNode.indent,
          metadata: itemMetadata,
        );
      } else if (parsedNode is TaskNode) {
        newNode = TaskNode(
          id: Editor.createNodeId(),
          text: parsedNode.text,
          isComplete: parsedNode.isComplete,
          metadata: itemMetadata,
        );
      } else if (parsedNode is ImageNode) {
        itemMetadata['isImage'] = true;
        itemMetadata['imageUrl'] = parsedNode.imageUrl;
        newNode = ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(serialized),
          metadata: itemMetadata,
        );
      } else if (parsedNode is TableBlockNode) {
        itemMetadata['isTable'] = true;
        newNode = ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(serialized),
          metadata: itemMetadata,
        );
      } else {
        final text = parsedNode is TextNode ? parsedNode.text : AttributedText(serialized);
        newNode = ParagraphNode(
          id: Editor.createNodeId(),
          text: text,
          metadata: itemMetadata,
        );
      }

      requests.add(InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: newNode));
      insertIndex++;
    }

    return requests;
  }

  EditRequest? _updateInlineFormatting(String nodeId) {
    final node = editorState.document.getNodeById(nodeId);
    if (node == null) return null;

    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = (meta.isRawMode && node is TextNode)
        ? node.text.toPlainText()
        : meta.rawMarkdown;

    bool isBlockquote = false;
    String innerRaw = raw;
    if (raw.trim().startsWith('>')) {
      isBlockquote = true;
      innerRaw = raw.split('\n').map((l) {
        final match = RegExp(r'^>\s?').firstMatch(l);
        return match != null ? l.substring(match.end) : l;
      }).join('\n');
    }

    final doc = deserializeMarkdownToDocument(innerRaw);
    final blockType = doc.isNotEmpty
        ? doc.first.getMetadataValue(NodeMetadata.blockType)
        : (innerRaw.trim().isEmpty ? paragraphAttribution : null);

    final formatted = applyInlineFormatting(raw);
    return ReplaceNodeRequest(
      existingNodeId: nodeId,
      newNode: ParagraphNode(
        id: nodeId,
        text: formatted,
        metadata: {
          if (blockType != null) NodeMetadata.blockType: blockType,
          if (isBlockquote) 'isBlockquote': true,
          'rawMarkdown': raw,
          'isRawMode': meta.isRawMode,
        },
      ),
    );
  }

  void _forceUnfoldNodes(Set<String> nodeIds) {
    if (nodeIds.isEmpty) return;

    DocumentSelection? newSelection = editorState.composer.selection;
    final requests = <EditRequest>[];

    for (final id in nodeIds) {
      final node = editorState.document.getNodeById(id);
      if (node is TextNode) {
        final meta = MarkdownNodeMetadata.fromNode(node);
        if (!meta.isRawMode) {
          if (newSelection != null) {
            newSelection = _remapSelectionOnFocus(node, newSelection);
          }
          final reqs = _onFocus(id);
          if (reqs.isNotEmpty) {
            requests.addAll(reqs);
            _focusedNodeIds.add(id);
          }
        }
      }
    }

    if (newSelection != null && newSelection != editorState.composer.selection) {
      requests.add(ChangeSelectionRequest(
        newSelection,
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ));
    }

    if (requests.isNotEmpty) {
      editorState.editor.execute(requests);
    }
  }

  void forceUnfold(Set<String> nodeIds) {
    if (_isApplyingFormatting) return;
    _forceUnfoldNodes(nodeIds);
  }

  DocumentSelection _remapSelectionOnFocus(TextNode node, DocumentSelection selection) {
    final visual = node.text.toPlainText();
    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = meta.rawMarkdown;

    DocumentPosition? newBase = selection.base;
    DocumentPosition? newExtent = selection.extent;

    if (selection.base.nodeId == node.id && selection.base.nodePosition is TextNodePosition) {
      final pos = selection.base.nodePosition as TextNodePosition;
      final mapped = mapVisualToRawOffset(visual, raw, pos.offset);
      newBase = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: mapped));
    }
    if (selection.extent.nodeId == node.id && selection.extent.nodePosition is TextNodePosition) {
      final pos = selection.extent.nodePosition as TextNodePosition;
      final mapped = mapVisualToRawOffset(visual, raw, pos.offset);
      newExtent = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: mapped));
    }
    return DocumentSelection(base: newBase, extent: newExtent);
  }

  void onDocumentChange(DocumentChangeLog changeLog) {
    if (_isApplyingFormatting) return;

    bool immediateUpdate = false;
    for (final event in changeLog.changes) {
      if (event is NodeChangeEvent || event is NodeInsertedEvent) {
        final nodeId = event is NodeChangeEvent ? event.nodeId : (event as NodeInsertedEvent).nodeId;
        final node = editorState.document.getNodeById(nodeId);
        if (node is TextNode) {
          final meta = MarkdownNodeMetadata.fromNode(node);
          if (meta.isRawMode) {
            MarkdownNodeMetadata.applyToNode(node, meta.copyWith(rawMarkdown: node.text.toPlainText()));
          }
        }
      }
      if (event is NodeInsertedEvent) {
        immediateUpdate = true;
      }
    }

    if (_focusedNodeIds.isEmpty) return;

    if (immediateUpdate) {
      _scheduleFormattingUpdate();
    } else {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scheduleFormattingUpdate();
      });
    }
  }

  void _scheduleFormattingUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isApplyingFormatting) return;
      final requests = <EditRequest>[];
      for (final id in _focusedNodeIds) {
        final req = _updateInlineFormatting(id);
        if (req != null) requests.add(req);
      }
      if (requests.isNotEmpty) {
        _isApplyingFormatting = true;
        try {
          editorState.editor.execute(requests);
        } finally {
          _isApplyingFormatting = false;
        }
      }
    });
  }
}
