import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../api/live_markdown_controller.dart';
import '../parsing/block_type_detector.dart' as btd;
import '../parsing/inline_formatter.dart';
import '../parsing/markdown_splitter.dart';
import '../rendering/styles.dart';
import 'editor_state.dart';
import 'raw_mode_manager.dart';
import 'unfold_before_action.dart';

ExecutionInstruction _customEnterHandler({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
  required void Function(DocumentChangeLog) onDocumentChange,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }
  if (keyEvent.logicalKey != LogicalKeyboardKey.enter &&
      keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }
  if (HardwareKeyboard.instance.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) return ExecutionInstruction.continueExecution;
  final node = editContext.document.getNodeById(selection.extent.nodeId);
  if (node is! TextNode) return ExecutionInstruction.continueExecution;
  if (node.metadata['isRawMode'] != true) return ExecutionInstruction.continueExecution;

  final text = node.text.toPlainText();
  final blockType = btd.detectBlockTypeFromAST(text);
  final offset = (selection.extent.nodePosition as TextNodePosition).offset;

  // Case 1: empty list/blockquote → exit (clear to empty paragraph)
  if (btd.isEmptyListItem(text) || btd.isEmptyBlockquoteLine(text)) {
    editContext.editor.execute([
      const ClearComposingRegionRequest(),
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(
          id: node.id,
          text: AttributedText(''),
          metadata: {...node.metadata, 'rawMarkdown': '', 'isRawMode': true},
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    return ExecutionInstruction.haltExecution;
  }

  // Case 2: multiline blocks (code, blockquote, table) + blockquotes
  if (btd.isMultilineBlock(blockType)) {
    final prefix = btd.detectContinuationPrefix(text);
    final insertion = prefix != null ? '\n$prefix' : '\n';
    final newText = '${text.substring(0, offset)}$insertion${text.substring(offset)}';

    // Guard: if \n would create >1 blocks → exit block (create new node after)
    if (splitMarkdownIntoBlocks(newText).length > 1) {
      final newId = Editor.createNodeId();
      editContext.editor.execute([
        InsertNodeAfterNodeRequest(
          existingNodeId: node.id,
          newNode: ParagraphNode(
            id: newId,
            text: AttributedText(''),
            metadata: {...node.metadata, 'rawMarkdown': '', 'isRawMode': true},
          ),
        ),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: newId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      return ExecutionInstruction.haltExecution;
    }

    // ≤1 block: safe continuation via direct node modification (no reconciler → no IME crash)
    final newNode = node.copyTextNodeWith(
      text: AttributedText(newText),
      metadata: {...node.metadata, 'rawMarkdown': newText, 'isRawMode': true},
    );
    final doc = editContext.document;
    if (doc is MutableDocument) {
      doc.replaceNodeById(node.id, newNode);
      onDocumentChange(DocumentChangeLog([]));
    }

    final newOffset = offset + insertion.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final comp = editContext.composer;
      if (comp is MutableDocumentComposer) {
        comp.setSelectionWithReason(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: newOffset),
            ),
          ),
        );
      }
    });
    return ExecutionInstruction.haltExecution;
  }

  // Case 3 & 4: standard blocks (headings, paragraphs) + lists + blockquotes
  // Handle split OURSELVES → no InsertNewlineAtCaretRequest → no recursive _processSelectionChange → no crash
  final listPrefix = btd.detectContinuationPrefix(text);
  final leftText = text.substring(0, offset);
  final rightText = text.substring(offset);
  final newId = Editor.createNodeId();

  editContext.editor.execute([
    const ClearComposingRegionRequest(),
    ReplaceNodeRequest(
      existingNodeId: node.id,
      newNode: ParagraphNode(
        id: node.id,
        text: applyInlineFormatting(leftText),
        metadata: {...node.metadata, 'rawMarkdown': leftText, 'isRawMode': true},
      ),
    ),
    InsertNodeAfterNodeRequest(
      existingNodeId: node.id,
      newNode: ParagraphNode(
        id: newId,
        text: applyInlineFormatting(listPrefix != null ? '$listPrefix$rightText' : rightText),
        metadata: {
          ...node.metadata,
          'rawMarkdown': listPrefix != null ? '$listPrefix$rightText' : rightText,
          'isRawMode': true,
        },
      ),
    ),
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: newId,
          nodePosition: TextNodePosition(offset: listPrefix != null ? listPrefix.length : 0),
        ),
      ),
      SelectionChangeType.placeCaret,
      SelectionReason.userInteraction,
    ),
  ]);
  return ExecutionInstruction.haltExecution;
}

class LiveMarkdownEditor extends StatefulWidget {
  final LiveMarkdownController controller;
  final bool deferToPointerUp;
  final bool cursorInsideMarkers;

  const LiveMarkdownEditor({
    super.key,
    required this.controller,
    this.deferToPointerUp = true,
    this.cursorInsideMarkers = true,
  });

  @override
  State<LiveMarkdownEditor> createState() => _LiveMarkdownEditorState();
}

class _LiveMarkdownEditorState extends State<LiveMarkdownEditor> {
  late EditorState _editorState;
  late RawModeManager _rawModeManager;

  @override
  void initState() {
    super.initState();
    _initEditor(widget.controller.text);
    _rawModeManager = RawModeManager(
      _editorState,
      deferToPointerUp: widget.deferToPointerUp,
      cursorInsideMarkers: widget.cursorInsideMarkers,
    );
    _editorState.composer.selectionNotifier.addListener(_rawModeManager.onSelectionChange);
    widget.controller.onReloadRequested = _reload;
  }

  @override
  void dispose() {
    _editorState.document.removeListener(_onDocumentChange);
    _editorState.composer.selectionNotifier.removeListener(_rawModeManager.onSelectionChange);
    _rawModeManager.dispose();
    _editorState.dispose();
    widget.controller.onReloadRequested = null;
    super.dispose();
  }

  void _initEditor(String markdown) {
    _editorState = EditorState();
    _editorState.initializeFromMarkdown(markdown);
    _editorState.document.addListener(_onDocumentChange);
  }

  void _reload() {
    final oldScrollController = _editorState.scrollController;
    _editorState.document.removeListener(_onDocumentChange);
    _editorState.composer.selectionNotifier.removeListener(_rawModeManager.onSelectionChange);
    _rawModeManager.dispose();
    _editorState.document.dispose();
    _editorState.composer.dispose();
    _editorState.editor.dispose();
    _editorState.initializeFromMarkdown(
      widget.controller.text,
      reuseScrollController: oldScrollController,
    );
    _editorState.document.addListener(_onDocumentChange);
    _rawModeManager = RawModeManager(
      _editorState,
      deferToPointerUp: widget.deferToPointerUp,
      cursorInsideMarkers: widget.cursorInsideMarkers,
    );
    _editorState.composer.selectionNotifier.addListener(_rawModeManager.onSelectionChange);
    setState(() {});
  }

  void _onDocumentChange(DocumentChangeLog changeLog) {
    _rawModeManager.onDocumentChange(changeLog);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final markdown = _editorState.document
          .map((n) {
            final meta = n.metadata;
            return meta['rawMarkdown'] as String? ?? (n is TextNode ? n.text.toPlainText() : '');
          })
          .join('\n\n');
      widget.controller.syncFromDocument(markdown);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _rawModeManager.setPointerDown(true),
      onPointerUp: (_) => _rawModeManager.setPointerDown(false),
      onPointerCancel: (_) => _rawModeManager.setPointerDown(false),
      child: SuperEditor(
        editor: _editorState.editor,
        scrollController: _editorState.scrollController,
        keyboardActions: [
          ({required SuperEditorContext editContext, required KeyEvent keyEvent}) =>
            unfoldBeforeAction(editContext: editContext, keyEvent: keyEvent, rawModeManager: _rawModeManager),
          ({required SuperEditorContext editContext, required KeyEvent keyEvent}) =>
            _customEnterHandler(editContext: editContext, keyEvent: keyEvent, onDocumentChange: _onDocumentChange),
          ...defaultKeyboardActions,
        ],
        componentBuilders: [
          const BlockquoteComponentBuilder(),
          const ImageComponentBuilder(),
          const MarkdownTableComponentBuilder(),
          ...defaultComponentBuilders,
        ],
        stylesheet: customStylesheet(defaultStylesheet),
      ),
    );
  }
}
