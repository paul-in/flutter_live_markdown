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
    final document = context.document;
    final currentNode = document.getNodeById(pastePosition.nodeId);
    if (currentNode is! TextNode) return;

    final pasteOffset = (pastePosition.nodePosition as TextNodePosition).offset;

    executor.executeCommand(ChangeComposingRegionCommand(null));

    executor.executeCommand(InsertTextCommand(
      documentPosition: pastePosition,
      textToInsert: content,
      attributions: {},
    ));

    executor.executeCommand(ChangeSelectionCommand(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: currentNode.id,
          nodePosition: TextNodePosition(offset: pasteOffset + content.length),
        ),
      ),
      SelectionChangeType.insertContent,
      SelectionReason.userInteraction,
    ));
  }
}
