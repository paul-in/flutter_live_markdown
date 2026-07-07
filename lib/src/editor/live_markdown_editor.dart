import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../api/live_markdown_controller.dart';
import '../rendering/styles.dart';
import 'editor_state.dart';

class LiveMarkdownEditor extends StatefulWidget {
  final LiveMarkdownController controller;

  const LiveMarkdownEditor({super.key, required this.controller});

  @override
  State<LiveMarkdownEditor> createState() => _LiveMarkdownEditorState();
}

class _LiveMarkdownEditorState extends State<LiveMarkdownEditor> {
  late EditorState _editorState;

  @override
  void initState() {
    super.initState();
    _initEditor(widget.controller.text);
    widget.controller.onReloadRequested = _reload;
  }

  @override
  void dispose() {
    _editorState.document.removeListener(_onDocumentChange);
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
    _editorState.document.dispose();
    _editorState.composer.dispose();
    _editorState.editor.dispose();
    // Keep the same scroll controller (already attached to SuperEditor)
    _editorState.initializeFromMarkdown(
      widget.controller.text,
      reuseScrollController: oldScrollController,
    );
    _editorState.document.addListener(_onDocumentChange);
    setState(() {});
  }

  void _onDocumentChange(DocumentChangeLog changeLog) {
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
    return SuperEditor(
      editor: _editorState.editor,
      scrollController: _editorState.scrollController,
      keyboardActions: [...defaultKeyboardActions],
      componentBuilders: [
        const BlockquoteComponentBuilder(),
        const ImageComponentBuilder(),
        const MarkdownTableComponentBuilder(),
        ...defaultComponentBuilders,
      ],
      stylesheet: customStylesheet(defaultStylesheet),
    );
  }
}
