import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../api/live_markdown_controller.dart';
import '../rendering/blockquote_wrapper_builder.dart';
import '../rendering/styles.dart';
import 'editor_state.dart';
import 'focus_manager.dart';
import 'reconciler.dart';
import 'scroll_anchor.dart';
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
  late FocusManager _focusManager;
  late SelectionController _selectionController;
  late UnfoldBeforeActionHandler _unfoldHandler;
  late ScrollAnchor _scrollAnchor;
  bool _isApplyingFormatting = false;
  bool _isPointerDown = false;

  @override
  void initState() {
    super.initState();
    _editorState = EditorState();
    _focusManager = FocusManager(_editorState);
    _selectionController = SelectionController(_editorState);
    _unfoldHandler = UnfoldBeforeActionHandler();
    _scrollAnchor = ScrollAnchor();

    _editorState.composer.selectionNotifier.addListener(_onSelectionChange);
    _editorState.document.addListener(_onDocumentChange);
  }

  @override
  void dispose() {
    _editorState.document.removeListener(_onDocumentChange);
    _editorState.composer.selectionNotifier.removeListener(_onSelectionChange);
    _editorState.dispose();
    super.dispose();
  }

  void _onSelectionChange() {}

  void _onDocumentChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final markdown = _editorState.document
          .map((n) => n.metadata['rawMarkdown'] as String? ?? (n is TextNode ? n.text.toPlainText() : ''))
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
      onPointerDown: (_) => _isPointerDown = true,
      onPointerUp: (_) {
        _isPointerDown = false;
        _onSelectionChange();
      },
      onPointerCancel: (_) {
        _isPointerDown = false;
        _onSelectionChange();
      },
      child: SuperEditor(
        editor: _editorState.editor,
        scrollController: _editorState.scrollController,
        keyboardActions: [
          _unfoldHandler.handle,
          ...defaultKeyboardActions,
        ],
        componentBuilders: [
          BlockquoteWrapperBuilder(defaultComponentBuilders),
          const ImageComponentBuilder(),
          const MarkdownTableComponentBuilder(),
          ...defaultComponentBuilders,
        ],
        stylesheet: _customStylesheet,
      ),
    );
  }
}
