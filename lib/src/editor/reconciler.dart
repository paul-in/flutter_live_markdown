import 'package:super_editor/super_editor.dart';

class NodeReconciliationReaction implements EditReaction {
  @override
  Future<List<EditRequest>> react(EditContext context, List<EditEvent> changes) async {
    return [];
  }
}
