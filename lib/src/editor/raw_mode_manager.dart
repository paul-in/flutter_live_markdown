import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';
import '../model/offset_mapper.dart';
import '../model/selection_expander.dart';
import '../parsing/inline_formatter.dart';
import 'editor_state.dart';
import 'scroll_anchor.dart';

void _log(String msg) => debugPrint('[LIVE_MD] $msg');

class RawModeManager {
  final EditorState editorState;
  final Set<String> _focusedNodeIds = {};
  bool _isApplyingFormatting = false;
  bool _isPointerDown = false;
  final ScrollAnchor _scrollAnchor = ScrollAnchor();
  Timer? _selectionTimer;

  RawModeManager(this.editorState) {
    _log('RawModeManager created');
  }

  void dispose() {
    _selectionTimer?.cancel();
    _log('RawModeManager disposed');
  }

  Set<String> get focusedNodeIds => Set.unmodifiable(_focusedNodeIds);
  bool get isPointerDown => _isPointerDown;

  void setPointerDown(bool value) {
    _isPointerDown = value;
    _log('setPointerDown: $value');
  }

  void onSelectionChange() {
    if (_isApplyingFormatting) {
      _log('onSelectionChange: SKIP (formatting in progress)');
      return;
    }
    _log('onSelectionChange: scheduling deferred processing');
    _selectionTimer?.cancel();
    _selectionTimer = Timer(Duration.zero, _processSelectionChange);
  }

  void _processSelectionChange() {
    if (_isApplyingFormatting) {
      _log('_processSelectionChange: SKIP (formatting in progress)');
      return;
    }

    final sel = editorState.composer.selection;
    final nextIds = <String>{};
    if (sel != null) {
      try {
        final nodes = editorState.document.getNodesInside(sel.base, sel.extent);
        nextIds.addAll(nodes.map((n) => n.id));
      } catch (e) {
        _log('_processSelectionChange: error getting nodes: $e');
      }
    }

    final toBlur = _focusedNodeIds.difference(nextIds);
    final toFocus = nextIds.difference(_focusedNodeIds);

    _log('_processSelectionChange: focused=$_focusedNodeIds next=$nextIds toBlur=$toBlur toFocus=$toFocus sel=$sel');

    if (toBlur.isEmpty && toFocus.isEmpty) return;

    _focusedNodeIds.clear();
    _focusedNodeIds.addAll(nextIds);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isApplyingFormatting) {
        _log('_processSelectionChange: executing _applyFocusBlur');
        _applyFocusBlur(toBlur, toFocus);
      } else {
        _log('_processSelectionChange: _applyFocusBlur SKIPPED (formatting in progress)');
      }
    });
  }

  void _applyFocusBlur(Set<String> toBlur, Set<String> toFocus) {
    _log('_applyFocusBlur: toBlur=$toBlur toFocus=$toFocus');
    _isApplyingFormatting = true;
    try {
      final layout = editorState.editor.context.findMaybe<DocumentLayoutEditable>(Editor.layoutKey);
      if (layout != null) {
        _scrollAnchor.save(
          layout.documentLayout,
          editorState.scrollController,
          toBlur,
          toFocus,
        );
      }

      DocumentSelection? newSelection = editorState.composer.selection;
      final requests = <EditRequest>[];

      for (final id in toBlur) {
        final node = editorState.document.getNodeById(id);
        _log('_applyFocusBlur: blur node=$id nodeType=${node.runtimeType}');
        if (node != null) {
          if (node is TextNode && newSelection != null) {
            newSelection = _remapSelectionOnBlur(node, newSelection);
          }
          final reqs = _onBlur(id);
          _log('_applyFocusBlur: _onBlur returned ${reqs.length} requests');
          if (reqs.isNotEmpty) requests.addAll(reqs);
        }
      }

      if (requests.isNotEmpty) {
        _log('_applyFocusBlur: executing ${requests.length} blur requests');
        editorState.editor.execute(requests);
      }

      if (newSelection != null && newSelection != editorState.composer.selection) {
        _log('_applyFocusBlur: restoring selection');
        editorState.composer.setSelectionWithReason(newSelection);
      }

      _log('_applyFocusBlur: unfolding ${toFocus.length} nodes');
      _forceUnfoldNodes(toFocus);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (layout != null) {
          _scrollAnchor.restore(
            layout.documentLayout,
            editorState.scrollController,
          );
        }
      });

    } catch (e, st) {
      _log('_applyFocusBlur: ERROR $e\n$st');
    } finally {
      _isApplyingFormatting = false;
      _log('_applyFocusBlur: done');
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
    if (node == null) {
      _log('_onFocus: node $nodeId not found');
      return [];
    }
    final meta = MarkdownNodeMetadata.fromNode(node);
    final raw = meta.rawMarkdown;
    _log('_onFocus: node=$nodeId raw="${raw.substring(0, raw.length.clamp(0, 50))}"');

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
    if (node is! TextNode) {
      _log('_onBlur: node $nodeId not a TextNode (${node.runtimeType})');
      return [];
    }

    final raw = node.text.toPlainText();
    final meta = MarkdownNodeMetadata.fromNode(node);
    _log('_onBlur: node=$nodeId raw="${raw.substring(0, raw.length.clamp(0, 50))}"');

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
      _log('_onBlur: doc empty, creating ReplaceNodeRequest');
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
    if (insertIndex < 0) {
      _log('_onBlur: node $nodeId not found in document');
      return [];
    }

    requests.add(DeleteNodeRequest(nodeId: nodeId));
    _log('_onBlur: parsed doc has ${doc.length} nodes');

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
    if (node == null) {
      _log('_updateInlineFormatting: node $nodeId not found');
      return null;
    }

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
        _log('_forceUnfoldNodes: node=$id isRawMode=${meta.isRawMode}');
        if (!meta.isRawMode) {
          if (newSelection != null) {
            newSelection = _remapSelectionOnFocus(node, newSelection);
          }
          final reqs = _onFocus(id);
          if (reqs.isNotEmpty) {
            requests.addAll(reqs);
            _focusedNodeIds.add(id);
            _log('_forceUnfoldNodes: focus request added for $id');
          }
        } else {
          _log('_forceUnfoldNodes: node $id already in raw mode, skipping');
        }
      } else {
        _log('_forceUnfoldNodes: node $id is ${node.runtimeType}, not TextNode');
      }
    }

    if (newSelection != null && newSelection != editorState.composer.selection) {
      _log('_forceUnfoldNodes: adding selection change request');
      requests.add(ChangeSelectionRequest(
        newSelection,
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ));
    }

    if (requests.isNotEmpty) {
      _log('_forceUnfoldNodes: executing ${requests.length} requests');
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
    newBase = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: newRawStart));
    newExtent = DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: newRawEnd));

    return DocumentSelection(base: newBase, extent: newExtent);
  }

  void onDocumentChange(DocumentChangeLog changeLog) {
    if (_isApplyingFormatting) {
      _log('onDocumentChange: SKIP (formatting in progress)');
      return;
    }

    bool immediateUpdate = false;
    for (final event in changeLog.changes) {
      if (event is NodeChangeEvent || event is NodeInsertedEvent) {
        final nodeId = event is NodeChangeEvent ? event.nodeId : (event as NodeInsertedEvent).nodeId;
        final node = editorState.document.getNodeById(nodeId);
        if (node is TextNode) {
          final meta = MarkdownNodeMetadata.fromNode(node);
          if (meta.isRawMode) {
            // rawMarkdown is kept in sync via node.text; metadata is updated
            // on the next _updateInlineFormatting or _onBlur call
          }
        }
      }
      if (event is NodeInsertedEvent) {
        immediateUpdate = true;
      }
    }

    if (_focusedNodeIds.isEmpty) return;

    _log('onDocumentChange: scheduling formatting update (immediate=$immediateUpdate)');

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
        _log('_scheduleFormattingUpdate: executing ${requests.length} formatting requests');
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
