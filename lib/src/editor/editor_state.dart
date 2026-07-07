import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../model/markdown_node_metadata.dart';
import '../parsing/markdown_splitter.dart';
import '../parsing/inline_formatter.dart';
import 'reconciler.dart';

void _log(String msg) => debugPrint('[LIVE_MD] $msg');

DocumentNode createNodeForBlock(MarkdownBlock block, {bool isRawMode = false}) {
  final raw = block.text;
  final nodeId = Editor.createNodeId();

  if (raw.isEmpty) {
    return ParagraphNode(
      id: nodeId,
      text: AttributedText(''),
      metadata: MarkdownNodeMetadata(
        rawMarkdown: '',
        isRawMode: isRawMode,
      ).toMap(),
    );
  }

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
  if (doc.isEmpty) {
    return ParagraphNode(
      id: nodeId,
      text: AttributedText(raw),
      metadata: MarkdownNodeMetadata(
        rawMarkdown: raw,
        isRawMode: isRawMode,
      ).toMap(),
    );
  }

  final parsedNode = doc.first;
  final baseMetadata = MarkdownNodeMetadata(
    rawMarkdown: raw,
    isRawMode: isRawMode,
    isBlockquote: isBlockquote,
  );

  if (parsedNode is ImageNode) {
    baseMetadata.toMap();
    return ParagraphNode(
      id: nodeId,
      text: isRawMode ? applyInlineFormatting(raw) : AttributedText(raw),
      metadata: {
        ...baseMetadata.toMap(),
        'isImage': true,
        'imageUrl': parsedNode.imageUrl,
      },
    );
  }

  if (parsedNode is TableBlockNode) {
    return ParagraphNode(
      id: nodeId,
      text: isRawMode ? applyInlineFormatting(raw) : AttributedText(raw),
      metadata: {
        ...baseMetadata.toMap(),
        'isTable': true,
      },
    );
  }

  final newMetadata = Map<String, dynamic>.from(parsedNode.metadata);
  newMetadata.addAll(baseMetadata.toMap());

  if (parsedNode is ParagraphNode) {
    return ParagraphNode(
      id: nodeId,
      text: isRawMode ? applyInlineFormatting(raw) : parsedNode.text,
      metadata: newMetadata,
    );
  }

  if (parsedNode is HorizontalRuleNode) {
    return HorizontalRuleNode(id: nodeId);
  }

  if (parsedNode is ListItemNode) {
    return ListItemNode(
      id: nodeId,
      itemType: parsedNode.type,
      text: isRawMode ? applyInlineFormatting(raw) : parsedNode.text,
      indent: parsedNode.indent,
      metadata: newMetadata,
    );
  }

  if (parsedNode is TaskNode) {
    return TaskNode(
      id: nodeId,
      text: isRawMode ? applyInlineFormatting(raw) : parsedNode.text,
      isComplete: parsedNode.isComplete,
      metadata: newMetadata,
    );
  }

  return ParagraphNode(
    id: nodeId,
    text: isRawMode ? applyInlineFormatting(raw) : parsedNode is TextNode ? parsedNode.text : AttributedText(raw),
    metadata: newMetadata,
  );
}

class EditorState {
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late ScrollController scrollController;

  void initializeFromMarkdown(String raw) {
    _log('initializeFromMarkdown: raw="${raw.substring(0, raw.length.clamp(0, 60))}"');
    document = MutableDocument(nodes: []);
    composer = MutableDocumentComposer();
    scrollController = ScrollController();

    final blocks = splitMarkdownIntoBlocks(raw);
    _log('initializeFromMarkdown: split into ${blocks.length} blocks');
    for (final block in blocks) {
      final node = createNodeForBlock(block);
      document.add(node);
      _log('initializeFromMarkdown: added node ${node.id} type=${node.runtimeType}');
    }

    final editableMap = <String, Editable>{
      Editor.documentKey: document,
      Editor.composerKey: composer,
    };
    editor = Editor(
      editables: editableMap,
      requestHandlers: [...defaultRequestHandlers],
      reactionPipeline: [
        NodeReconciliationReaction(editorState: this),
      ],
      isHistoryEnabled: true,
    );
    _log('initializeFromMarkdown: done (${document.length} nodes)');
  }

  void rebuild() {
    final raw = document
        .map((n) => MarkdownNodeMetadata.fromNode(n).rawMarkdown)
        .join('\n\n');
    _log('rebuild: raw length=${raw.length}');
    dispose();
    initializeFromMarkdown(raw);
  }

  void dispose() {
    _log('EditorState dispose');
    document.dispose();
    composer.dispose();
    editor.dispose();
    scrollController.dispose();
  }
}
