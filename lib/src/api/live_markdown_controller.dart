import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../editor/editor_state.dart';
import '../model/markdown_node_metadata.dart';
import '../parsing/inline_formatter.dart';


// Contains Public API
class LiveMarkdownController extends ChangeNotifier {
  String _text = '';
  EditorState? _editorState;

  String get text => _text;

  int? _pendingCursor;

  /// Internal. Consumes and returns the pending cursor value, if any.
  int? consumePendingCursor() {
    final c = _pendingCursor;
    _pendingCursor = null;
    return c;
  }

  VoidCallback? onChange;
  VoidCallback? onSelectionChange;
  ValueChanged<bool>? onFocusChange;
  VoidCallback? onReloadRequested;
  VoidCallback? onHistoryChange;

  LiveMarkdownController({String? initialMarkdown}) {
    if (initialMarkdown != null) {
      _text = initialMarkdown;
    }
  }

  /// Internal: attach to an EditorState after the widget initializes.
  void attachToEditor(EditorState editorState) {
    _editorState = editorState;
    editorState.composer.selectionNotifier.addListener(_onSelectionChanged);
    editorState.editorFocusNode.addListener(_onFocusChanged);
  }

  void _onSelectionChanged() {
    onSelectionChange?.call();
  }

  void _onFocusChanged() {
    onFocusChange?.call(_editorState!.editorFocusNode.hasFocus);
  }

  void detachFromEditor() {
    final es = _editorState;
    if (es != null) {
      es.composer.selectionNotifier.removeListener(_onSelectionChanged);
      es.editorFocusNode.removeListener(_onFocusChanged);
    }
    _editorState = null;
  }

  // ── Public API ──────────────────────────────────────────

  /// Replaces all content and reinitializes the editor.
  ///
  /// If [cursor] is provided, places the cursor at that global
  /// raw-markdown offset after the reload.
  void replaceContent(String markdown, {int? cursor}) {
    _text = markdown;
    _pendingCursor = cursor;
    onReloadRequested?.call();
    notifyListeners();
    onChange?.call();
  }

  void setCursorAfterReload(int globalOffset) {
    final es = _editorState;
    if (es == null) return;
    int accumulated = 0;
    for (final node in es.document) {
      final raw = node.metadata['rawMarkdown'] as String? ?? '';
      final rawLen = raw.length;
      if (globalOffset <= accumulated + rawLen) {
        final localRawOffset = (globalOffset - accumulated).clamp(0, rawLen);
        if (node is TextNode) {
          final meta = MarkdownNodeMetadata.fromNode(node);
          if (!meta.isRawMode) {
            _focusNodeRaw(node, localRawOffset);
          } else {
            es.composer.setSelectionWithReason(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: TextNodePosition(offset: localRawOffset),
                ),
              ),
            );
          }
        }
        return;
      }
      accumulated += rawLen + 2;
    }
  }

  void _focusNodeRaw(TextNode node, int targetRawOffset) {
    final es = _editorState;
    if (es == null) return;

    final meta = MarkdownNodeMetadata.fromNode(node);
    final formatted = applyInlineFormatting(meta.rawMarkdown);
    final newMeta = meta.copyWith(isRawMode: true);
    final newMetaMap = newMeta.toMap();
    final blockType = node.metadata[NodeMetadata.blockType];
    if (blockType != null) newMetaMap[NodeMetadata.blockType] = blockType;

    es.editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(
          id: node.id,
          text: formatted,
          metadata: newMetaMap,
        ),
      ),
    ]);

    final updatedNode = es.document.getNodeById(node.id);
    if (updatedNode is TextNode) {
      es.composer.setSelectionWithReason(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(
              offset: targetRawOffset.clamp(0, meta.rawMarkdown.length),
            ),
          ),
        ),
      );
    }
  }

  /// Internal: sync _text from the editor without reinitializing.
  void syncFromDocument(String markdown) {
    if (_text == markdown) return;
    _text = markdown;
    notifyListeners();
    onChange?.call();
  }

  /// Returns the absolute raw-markdown offset of the selection start.
  int get selectionStart {
    final es = _editorState;
    if (es == null) return 0;
    final sel = es.composer.selection;
    if (sel == null) return 0;
    if (sel.base.nodePosition is! TextNodePosition) {
      return _nodeToGlobalOffset(sel.base.nodeId, 0);
    }
    return _nodeToGlobalOffset(sel.base.nodeId, (sel.base.nodePosition as TextNodePosition).offset);
  }

  /// Returns the absolute raw-markdown offset of the selection extent.
  int get selectionEnd {
    final es = _editorState;
    if (es == null) return 0;
    final sel = es.composer.selection;
    if (sel == null) return 0;
    if (sel.extent.nodePosition is! TextNodePosition) {
      return _nodeToGlobalOffset(sel.extent.nodeId, 0);
    }
    return _nodeToGlobalOffset(sel.extent.nodeId, (sel.extent.nodePosition as TextNodePosition).offset);
  }

  int _nodeToGlobalOffset(String nodeId, int localOffset) {
    final doc = _editorState!.document;
    int global = 0;
    for (final n in doc) {
      if (n.id == nodeId) return global + localOffset;
      final raw = n.metadata['rawMarkdown'] as String? ?? (n is TextNode ? n.text.toPlainText() : '');
      global += raw.length + 2;
    }
    return global + localOffset;
  }

  /// Returns the raw markdown text between two absolute offsets.
  String getContentBetween(int start, int end) {
    if (start < 0) start = 0;
    if (end > _text.length) end = _text.length;
    if (start >= end) return '';
    return _text.substring(start, end);
  }

  /// Scrolls the editor to try to bring the position at [globalOffset] into view.
  /// Uses a rough approximation based on node index and scroll controller position.
  void scrollTo(int globalOffset) {
    final es = _editorState;
    if (es == null) return;
    int accumulated = 0;
    int nodeIndex = 0;
    for (final n in es.document) {
      final raw = n.metadata['rawMarkdown'] as String? ?? (n is TextNode ? n.text.toPlainText() : '');
      final rawLen = raw.length;
      if (globalOffset <= accumulated + rawLen) break;
      accumulated += rawLen + 2;
      nodeIndex++;
    }
    final nodeCount = es.document.length;
    if (nodeCount == 0) return;
    final ratio = nodeCount > 1 ? nodeIndex / (nodeCount - 1) : 0.0;
    final scrollPos = ratio * es.scrollController.position.maxScrollExtent;
    es.scrollController.jumpTo(scrollPos.clamp(0.0, es.scrollController.position.maxScrollExtent));
  }

  /// Removes focus from the editor.
  void blur() {
    _editorState?.editorFocusNode.unfocus();
  }

  /// Clears the current selection (collapses to a single point at cursor).
  void clearSelection() {
    final es = _editorState;
    if (es == null) return;
    final sel = es.composer.selection;
    if (sel != null && !sel.isCollapsed) {
      es.composer.setSelectionWithReason(
        DocumentSelection.collapsed(position: sel.extent),
      );
    }
  }

  /// Whether undo is available.
  bool get canUndo {
    final es = _editorState;
    if (es == null) return false;
    return es.editor.isHistoryEnabled && es.editor.history.isNotEmpty;
  }

  /// Whether redo is available.
  bool get canRedo {
    final es = _editorState;
    if (es == null) return false;
    return es.editor.isHistoryEnabled && es.editor.future.isNotEmpty;
  }

  /// Undoes the last undoable transaction.
  void undo() {
    final es = _editorState;
    if (es == null) return;
    es.isUndoing = true;
    es.editor.undo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      es.isUndoing = false;
    });
  }

  /// Redoes the last undone transaction.
  void redo() {
    final es = _editorState;
    if (es == null) return;
    es.isUndoing = true;
    es.editor.redo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      es.isUndoing = false;
    });
  }

  /// Controls whether the software keyboard should be shown.
  /// Requires a widget rebuild to take effect — stubbed until the widget infrastructure is ready.
  void setShowKeyboard(bool show) {
    debugPrint('[LiveMarkdownController] setShowKeyboard($show) — not yet wired');
  }

  /// Clears the undo/redo history.
  void clearHistory() {
    debugPrint('[LiveMarkdownController] clearHistory() — not yet wired');
  }
}
