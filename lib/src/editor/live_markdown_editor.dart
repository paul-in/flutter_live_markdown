import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../api/live_markdown_controller.dart';
import '../rendering/styles.dart';
import 'editor_state.dart';
import 'raw_mode_manager.dart';

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
        keyboardActions: [...defaultKeyboardActions],
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
