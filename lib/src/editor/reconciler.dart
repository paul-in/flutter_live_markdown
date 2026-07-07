import 'package:super_editor/super_editor.dart';

class NakedNodeReconciler extends EditReaction {
  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editorContext.find(Editor.documentKey) as Document;
    final requests = <EditRequest>[];

    for (final editEvent in changeList) {
      if (editEvent is! DocumentEdit) continue;
      final change = editEvent.change;
      if (change is! NodeDocumentChange) continue;

      final node = document.getNodeById(change.nodeId);
      if (node is! TextNode) continue;
      if (node.metadata.containsKey('rawMarkdown')) continue;

      final text = node.text.toPlainText();
      final existingMeta = Map<String, dynamic>.from(node.metadata);
      existingMeta['rawMarkdown'] = text;
      existingMeta['isRawMode'] = false;

      requests.add(ReplaceNodeRequest(
        existingNodeId: change.nodeId,
        newNode: ParagraphNode(
          id: change.nodeId,
          text: node.text,
          metadata: existingMeta,
        ),
      ));
    }

    if (requests.isNotEmpty) {
      requestDispatcher.execute(requests);
    }
  }
}
