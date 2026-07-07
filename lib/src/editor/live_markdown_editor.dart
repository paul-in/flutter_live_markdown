import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../api/live_markdown_controller.dart';
import '../rendering/blockquote_wrapper_builder.dart';
import '../rendering/styles.dart';
import 'editor_state.dart';
import 'raw_mode_manager.dart';
import 'selection_controller.dart';
import 'unfold_before_action.dart';

class LiveMarkdownEditor extends StatefulWidget {
  final LiveMarkdownController controller;

  const LiveMarkdownEditor({super.key, required this.controller});

  @override
  State<LiveMarkdownEditor> createState() => _LiveMarkdownEditorState();
}

class _LiveMarkdownEditorState extends State<LiveMarkdownEditor> {
  late EditorState _editorState;
  late RawModeManager _rawModeManager;
  late SelectionController _selectionController;
  late UnfoldBeforeActionHandler _unfoldHandler;

  @override
  void initState() {
    super.initState();
    _editorState = EditorState();
    _rawModeManager = RawModeManager(_editorState);
    _selectionController = SelectionController(_editorState);
    _unfoldHandler = UnfoldBeforeActionHandler(
      editorState: _editorState,
      rawModeManager: _rawModeManager,
    );

    _editorState.initializeFromMarkdown(widget.controller.text);

    _editorState.composer.selectionNotifier.addListener(_rawModeManager.onSelectionChange);
    _editorState.document.addListener(_onDocumentChange);

    // Wire controller
    widget.controller.editorState = _editorState;
    widget.controller.rawModeManager = _rawModeManager;
    widget.controller.selectionController = _selectionController;
  }

  @override
  void dispose() {
    _editorState.document.removeListener(_onDocumentChange);
    _editorState.composer.selectionNotifier.removeListener(_rawModeManager.onSelectionChange);
    _rawModeManager.dispose();
    _editorState.dispose();
    super.dispose();
  }

  void _onDocumentChange(DocumentChangeLog changeLog) {
    _rawModeManager.onDocumentChange(changeLog);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final markdown = _editorState.document
          .map((n) {
            final meta = n.metadata;
            if (meta['isRawMode'] == true && n is TextNode) {
              return n.text.toPlainText();
            }
            return meta['rawMarkdown'] as String? ?? (n is TextNode ? n.text.toPlainText() : '');
          })
          .join('\n\n');
      if (widget.controller.text != markdown) {
        widget.controller.replaceContent(markdown);
      }
    });
  }

  Stylesheet get _customStylesheet => customStylesheet(defaultStylesheet);

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
          _unfoldHandler.handle,
          _customEnterHandler,
          ...defaultKeyboardActions,
        ],
        componentBuilders: [
          BlockquoteWrapperBuilder(_editorState.document, defaultComponentBuilders),
          const ImageComponentBuilder(),
          const MarkdownTableComponentBuilder(),
          ...defaultComponentBuilders,
        ],
        stylesheet: _customStylesheet,
      ),
    );
  }

  ExecutionInstruction _customEnterHandler({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
      return ExecutionInstruction.continueExecution;
    }
    if (keyEvent.logicalKey != LogicalKeyboardKey.enter &&
        keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return ExecutionInstruction.continueExecution;
    }

    final selection = editContext.composer.selection;
    if (selection == null || !selection.isCollapsed) return ExecutionInstruction.continueExecution;

    final node = editContext.document.getNodeById(selection.extent.nodeId);
    if (node is! TextNode) return ExecutionInstruction.continueExecution;

    final text = node.text.toPlainText();
    final textTrimmed = text.trimLeft();

    // Multiline blocks: tables (|), blockquotes (>), code blocks (```)
    final isMultiLineMode = textTrimmed.startsWith('|') ||
        textTrimmed.startsWith('>') ||
        textTrimmed.startsWith('```');

    if (isMultiLineMode) {
      final offset = (selection.extent.nodePosition as TextNodePosition).offset;
      if (offset > 0 && text.substring(offset - 1, offset) == '\n') {
        // Double Enter: exit multiline block
        editContext.editor.execute([
          DeleteContentRequest(
            documentRange: DocumentRange(
              start: DocumentPosition(
                nodeId: node.id,
                nodePosition: TextNodePosition(offset: offset - 1),
              ),
              end: DocumentPosition(
                nodeId: node.id,
                nodePosition: TextNodePosition(offset: offset),
              ),
            ),
          ),
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: node.id,
                nodePosition: TextNodePosition(offset: offset - 1),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
        return ExecutionInstruction.continueExecution;
      } else {
        // Single Enter: insert newline
        editContext.editor.execute([
          InsertTextRequest(
            documentPosition: selection.extent,
            textToInsert: '\n',
            attributions: editContext.composer.preferences.currentAttributions,
          ),
        ]);
        return ExecutionInstruction.haltExecution;
      }
    }

    return ExecutionInstruction.continueExecution;
  }
}
