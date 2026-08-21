import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../parsing/inline_formatter.dart';
import '../parsing/markdown_splitter.dart';


// Listen every change, ask the Splitter the number of blocks and compare if it changes. It rebuilds blocks if number has changed.
class MarkdownReconciler extends EditReaction {
  final DocumentNode Function(MarkdownBlock) createNodeForBlock;

  MarkdownReconciler({required this.createNodeForBlock});

  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editorContext.find(Editor.documentKey) as Document;
    final composer = editorContext.find(Editor.composerKey) as MutableDocumentComposer;
    final selection = composer.selection;

    final allRequests = <EditRequest>[];
    bool selectionHandled = false;

    // Pass 1: raw-mode multi-block splits (Scenario A)
    for (final editEvent in changeList) {
      if (editEvent is! DocumentEdit) continue;
      final change = editEvent.change;
      if (change is! NodeDocumentChange) continue;

      final node = document.getNodeById(change.nodeId);
      if (node is! TextNode) continue;
      if (node.metadata['isRawMode'] != true) continue;

      final text = node.text.toPlainText();
      final blocks = splitMarkdownIntoBlocks(text);
      if (blocks.length <= 1) continue;

      final nodeIndex = document.getNodeIndexById(node.id);
      if (nodeIndex == -1) continue;
      allRequests.add(DeleteNodeRequest(nodeId: node.id));

      String? prevId;
      for (int i = 0; i < blocks.length; i++) {
        final newNode = _createRawModeNode(blocks[i]);
        if (i == 0) {
          allRequests.add(InsertNodeAtIndexRequest(nodeIndex: nodeIndex, newNode: newNode));
        } else {
          allRequests.add(InsertNodeAfterNodeRequest(existingNodeId: prevId!, newNode: newNode));
        }
        if (!selectionHandled) {
          _preserveSelectionOnSplit(selection, node.id, blocks[i], newNode, allRequests);
          if (allRequests.isNotEmpty && allRequests.last is ChangeSelectionRequest) {
            selectionHandled = true;
          }
        }
        prevId = newNode.id;
      }
    }

    // Execute any accumulated requests from Pass 1
    if (allRequests.isNotEmpty) {
      requestDispatcher.execute(allRequests);
    }
  }

  DocumentNode _createRawModeNode(MarkdownBlock block) {
    final base = createNodeForBlock(block);
    if (base is! TextNode) return base;

    final formatted = applyInlineFormatting(block.text);
    final meta = Map<String, dynamic>.from(base.metadata);
    meta['rawMarkdown'] = block.text;
    meta['isRawMode'] = true;

    return base.copyTextNodeWith(text: formatted, metadata: meta);
  }

  void _preserveSelectionOnSplit(
    DocumentSelection? selection,
    String oldNodeId,
    MarkdownBlock block,
    DocumentNode newNode,
    List<EditRequest> requests,
  ) {
    if (selection == null) return;
    if (selection.extent.nodeId != oldNodeId && selection.base.nodeId != oldNodeId) return;

    for (final pos in [selection.extent, selection.base]) {
      if (pos.nodeId != oldNodeId) continue;
      if (pos.nodePosition is! TextNodePosition) continue;

      final offset = (pos.nodePosition as TextNodePosition).offset;
      if (offset >= block.startOffset && offset <= block.endOffset) {
        if (newNode is TextNode) {
          requests.add(ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: newNode.id,
                nodePosition: TextNodePosition(offset: offset - block.startOffset),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        } else {
          requests.add(ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: newNode.id,
                nodePosition: const UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        }
        return;
      }
    }
  }
}
