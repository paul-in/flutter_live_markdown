import 'dart:ui' as ui;

import 'package:super_editor/super_editor.dart';

// Bypass the super_editor paste because it decomposes every \n into different nodes, but we set a custom decomposition logic, done after pasting by the reconciler
class MarkdownPasteCommand extends EditCommand {
  MarkdownPasteCommand({
    required this.content,
    required this.pastePosition,
  });

  final String content;
  final DocumentPosition pastePosition;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    if (content.isEmpty) return;

    final document = context.document;
    final currentNode = document.getNodeById(pastePosition.nodeId);
    if (currentNode is! TextNode) {
      throw Exception('Cannot paste into non-text node: $currentNode');
    }

    final pasteOffset = (pastePosition.nodePosition as TextNodePosition).offset;

    final pastedNodeId = Editor.createNodeId();
    final pastedNode = ParagraphNode(
      id: pastedNodeId,
      text: AttributedText(content),
      metadata: {
        'isRawMode': true,
        'rawMarkdown': content,
      },
    );

    String selectionNodeId;

    if (currentNode.text.isEmpty && pasteOffset == 0) {
      executor.executeCommand(ReplaceNodeCommand(
        existingNodeId: currentNode.id,
        newNode: ParagraphNode(
          id: currentNode.id,
          text: AttributedText(content),
          metadata: {
            'isRawMode': true,
            'rawMarkdown': content,
          },
        ),
      ));
      selectionNodeId = currentNode.id;
    } else if (pasteOffset == 0) {
      final index = document.getNodeIndexById(currentNode.id);
      executor.executeCommand(InsertNodeAtIndexCommand(
        nodeIndex: index,
        newNode: pastedNode,
      ));
      selectionNodeId = pastedNodeId;
    } else if (pasteOffset >= currentNode.text.length) {
      document.insertNodeAfter(
        existingNodeId: currentNode.id,
        newNode: pastedNode,
      );
      executor.logChanges([
        DocumentEdit(NodeInsertedEvent(pastedNodeId, document.getNodeIndexById(pastedNodeId))),
      ]);
      selectionNodeId = pastedNodeId;
    } else {
      final downstreamNodeId = Editor.createNodeId();
      executor.executeCommand(SplitParagraphCommand(
        nodeId: currentNode.id,
          splitPosition: ui.TextPosition(offset: pasteOffset),
        newNodeId: downstreamNodeId,
        replicateExistingMetadata: true,
      ));
      document.insertNodeAfter(
        existingNodeId: currentNode.id,
        newNode: pastedNode,
      );
      executor.logChanges([
        DocumentEdit(NodeInsertedEvent(pastedNodeId, document.getNodeIndexById(pastedNodeId))),
      ]);
      selectionNodeId = pastedNodeId;
    }

    executor.executeCommand(ChangeSelectionCommand(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: selectionNodeId,
          nodePosition: TextNodePosition(offset: content.length),
        ),
      ),
      SelectionChangeType.insertContent,
      SelectionReason.userInteraction,
    ));
  }
}
