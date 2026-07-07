import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../parsing/inline_formatter.dart';
import '../parsing/markdown_splitter.dart';

class MarkdownReconciler extends EditReaction {
  final DocumentNode Function(MarkdownBlock) createNodeForBlock;

  MarkdownReconciler({required this.createNodeForBlock});

  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editorContext.find(Editor.documentKey) as Document;
    final composer = editorContext.find(Editor.composerKey) as MutableDocumentComposer;
    final selection = composer.selection;

    for (final editEvent in changeList) {
      if (editEvent is! DocumentEdit) continue;
      final change = editEvent.change;
      if (change is! NodeDocumentChange) continue;

      final node = document.getNodeById(change.nodeId);
      if (node is! TextNode) continue;
      if (node.metadata.containsKey('rawMarkdown') && node.metadata['isRawMode'] != true) continue;

      if (node.metadata['isRawMode'] == true) {
        // Scenario A: raw-mode node changed — check for multi-block content
        final raw = node.text.toPlainText();
        final blocks = splitMarkdownIntoBlocks(raw);
        if (blocks.length <= 1) continue;

        final reqs = <EditRequest>[];
        final nodeIndex = document.getNodeIndexById(node.id);
        reqs.add(DeleteNodeRequest(nodeId: node.id));

        String? prevId;
        for (int i = 0; i < blocks.length; i++) {
          final newNode = _createRawModeNode(blocks[i]);
          if (i == 0) {
            reqs.add(InsertNodeAtIndexRequest(nodeIndex: nodeIndex, newNode: newNode));
          } else {
            reqs.add(InsertNodeAfterNodeRequest(existingNodeId: prevId!, newNode: newNode));
          }
          _preserveSelectionOnSplit(selection, node.id, blocks[i], newNode.id, reqs);
          prevId = newNode.id;
        }

        requestDispatcher.execute(reqs);
        return;
      }

      if (!node.metadata.containsKey('rawMarkdown')) {
        // Scenario B: naked node — parse markdown to create correct node type
        final text = node.text.toPlainText();
        final block = MarkdownBlock(text, 0, text.length);
        final parsedNode = createNodeForBlock(block);
        final meta = Map<String, dynamic>.from(node.metadata);
        meta['rawMarkdown'] = text;
        meta['isRawMode'] = false;

        final DocumentNode replacement;
        if (parsedNode is TextNode) {
          final parsedMeta = Map<String, dynamic>.from(parsedNode.metadata);
          parsedMeta.addAll(meta);
          replacement = ParagraphNode(id: node.id, text: parsedNode.text, metadata: parsedMeta);
        } else {
          replacement = parsedNode;
        }

        final reqs = <EditRequest>[
          ReplaceNodeRequest(existingNodeId: node.id, newNode: replacement),
        ];
        _preserveSelectionOnReplace(selection, node.id, replacement.id, text, reqs);

        requestDispatcher.execute(reqs);
        return;
      }
    }
  }

  DocumentNode _createRawModeNode(MarkdownBlock block) {
    final base = createNodeForBlock(block);
    if (base is! TextNode) return base;

    final formatted = applyInlineFormatting(block.text);
    final meta = Map<String, dynamic>.from(base.metadata);
    meta['rawMarkdown'] = block.text;
    meta['isRawMode'] = true;

    return ParagraphNode(id: base.id, text: formatted, metadata: meta);
  }

  void _preserveSelectionOnSplit(
    DocumentSelection? selection,
    String oldNodeId,
    MarkdownBlock block,
    String newNodeId,
    List<EditRequest> requests,
  ) {
    if (selection == null) return;
    if (selection.extent.nodeId != oldNodeId && selection.base.nodeId != oldNodeId) return;

    for (final pos in [selection.extent, selection.base]) {
      if (pos.nodeId != oldNodeId) continue;
      if (pos.nodePosition is! TextNodePosition) continue;

      final offset = (pos.nodePosition as TextNodePosition).offset;
      if (offset >= block.startOffset && offset <= block.endOffset) {
        requests.add(ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: newNodeId,
              nodePosition: TextNodePosition(offset: offset - block.startOffset),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ));
        return;
      }
    }
  }

  void _preserveSelectionOnReplace(
    DocumentSelection? selection,
    String oldNodeId,
    String newNodeId,
    String text,
    List<EditRequest> requests,
  ) {
    if (selection == null) return;
    for (final pos in [selection.extent, selection.base]) {
      if (pos.nodeId != oldNodeId) continue;
      if (pos.nodePosition is! TextNodePosition) continue;

      requests.add(ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: newNodeId,
            nodePosition: TextNodePosition(offset: (pos.nodePosition as TextNodePosition).offset),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ));
      return;
    }
  }
}
