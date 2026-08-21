import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../model/markdown_node_metadata.dart';
import '../parsing/markdown_utils.dart';
import '../parsing/markdown_splitter.dart';
import 'merge_rapid_markdown_typing_policy.dart';
import 'raw_formatting_reaction.dart';
import 'reconciler.dart';
import 'markdown_paste_command.dart';
import 'refresh_inline_formatting.dart';

// Used by the editor_state. Called once at doc init and then by the reconciler when blocks change.
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
  {
    final result = parseBlockquote(raw);
    innerRaw = result.text;
    isBlockquote = result.isBlockquote;
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

EditRequestHandler markdownPasteHandler = (editor, request) {
  if (request is PasteEditorRequest) {
    return MarkdownPasteCommand(
      content: request.content,
      pastePosition: request.pastePosition,
    );
  }
  return null;
};

class EditorState {
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late FocusNode editorFocusNode;
  late ScrollController scrollController;

  bool isUndoing = false;

  // Entry point 
  void initializeFromMarkdown(String raw, {ScrollController? reuseScrollController}) {
    composer = MutableDocumentComposer();
    editorFocusNode = FocusNode();
    scrollController = reuseScrollController ?? ScrollController();

    final blocks = splitMarkdownIntoBlocks(raw);
    document = MutableDocument(nodes: blocks.map(createNodeForBlock).toList());

    editor = Editor(
      editables: {
        Editor.documentKey: document,
        Editor.composerKey: composer,
      },
      requestHandlers: [
        refreshInlineFormattingRequestHandler,
        markdownPasteHandler,
        ...defaultRequestHandlers,
      ],
      reactionPipeline: [ // listen every actions
        MarkdownReconciler(createNodeForBlock: createNodeForBlock),
        RawFormattingReaction(),
      ],
      historyGroupingPolicy: HistoryGroupingPolicyList([
        mergeRepeatSelectionChangesPolicy,
        mergeRapidTextInputPolicy,
        const MergeRapidMarkdownTypingPolicy(),
      ]),
      isHistoryEnabled: true,
    );
  }

  void dispose() {
    document.dispose();
    composer.dispose();
    editor.dispose();
    editorFocusNode.dispose();
    scrollController.dispose();
  }
}
