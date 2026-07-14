import 'package:super_editor/super_editor.dart';

import '../model/inline_formatting_event.dart';

class RefreshInlineFormattingRequest implements EditRequest {
  final String nodeId;
  final DocumentNode newNode;

  const RefreshInlineFormattingRequest({
    required this.nodeId,
    required this.newNode,
  });
}

class RefreshInlineFormattingCommand extends EditCommand {
  final String nodeId;
  final DocumentNode newNode;

  RefreshInlineFormattingCommand({
    required this.nodeId,
    required this.newNode,
  });

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.find(Editor.documentKey) as MutableDocument;
    document.replaceNodeById(nodeId, newNode);
    executor.logChanges([
      DocumentEdit(InlineFormattingRefreshEvent(nodeId)),
    ]);
  }

  @override
  String describe() => "RefreshInlineFormatting($nodeId)";
}

EditCommand? refreshInlineFormattingRequestHandler(Editor editor, EditRequest request) {
  if (request is! RefreshInlineFormattingRequest) return null;
  return RefreshInlineFormattingCommand(
    nodeId: request.nodeId,
    newNode: request.newNode,
  );
}
