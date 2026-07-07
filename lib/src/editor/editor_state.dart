import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../model/markdown_node_metadata.dart';
import '../parsing/markdown_splitter.dart';
import 'reconciler.dart';

DocumentNode createNodeForBlock(MarkdownBlock block) {
  final nodeId = Editor.createNodeId();
  final raw = block.text;

  if (raw.isEmpty) {
    return ParagraphNode(
      id: nodeId,
      text: AttributedText(''),
      metadata: MarkdownNodeMetadata(rawMarkdown: '').toMap(),
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
      metadata: MarkdownNodeMetadata(rawMarkdown: raw).toMap(),
    );
  }

  final parsedNode = doc.first;
  final baseMetadata = MarkdownNodeMetadata(rawMarkdown: raw).toMap();
  final newMetadata = Map<String, dynamic>.from(parsedNode.metadata);
  newMetadata.addAll(baseMetadata);
  if (isBlockquote) {
    newMetadata[NodeMetadata.blockType] = blockquoteAttribution;
  }

  if (parsedNode is ImageNode) {
    newMetadata['isImage'] = true;
    newMetadata['imageUrl'] = parsedNode.imageUrl;
    return ParagraphNode(id: nodeId, text: AttributedText(raw), metadata: newMetadata);
  }

  if (parsedNode is TableBlockNode) {
    newMetadata['isTable'] = true;
    return ParagraphNode(id: nodeId, text: AttributedText(raw), metadata: newMetadata);
  }

  if (parsedNode is HorizontalRuleNode) {
    return HorizontalRuleNode(
      id: nodeId,
      metadata: MarkdownNodeMetadata(rawMarkdown: raw).toMap(),
    );
  }

  if (parsedNode is ListItemNode) {
    return ListItemNode(
      id: nodeId,
      itemType: parsedNode.type,
      text: parsedNode.text,
      indent: parsedNode.indent,
      metadata: newMetadata,
    );
  }

  if (parsedNode is TaskNode) {
    return TaskNode(
      id: nodeId,
      text: parsedNode.text,
      isComplete: parsedNode.isComplete,
      metadata: newMetadata,
    );
  }

  final text = parsedNode is TextNode ? parsedNode.text : AttributedText(raw);
  return ParagraphNode(id: nodeId, text: text, metadata: newMetadata);
}

class EditorState {
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late ScrollController scrollController;

  void initializeFromMarkdown(String raw, {ScrollController? reuseScrollController}) {
    document = MutableDocument(nodes: []);
    composer = MutableDocumentComposer();
    scrollController = reuseScrollController ?? ScrollController();

    final blocks = splitMarkdownIntoBlocks(raw);
    for (final block in blocks) {
      document.add(createNodeForBlock(block));
    }

    editor = Editor(
      editables: {
        Editor.documentKey: document,
        Editor.composerKey: composer,
      },
      requestHandlers: [...defaultRequestHandlers],
      reactionPipeline: [
        NakedNodeReconciler(),
      ],
      isHistoryEnabled: false,
    );
  }

  void dispose() {
    document.dispose();
    composer.dispose();
    editor.dispose();
    scrollController.dispose();
  }
}
