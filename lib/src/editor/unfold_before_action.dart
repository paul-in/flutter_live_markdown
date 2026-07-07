import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

class UnfoldBeforeActionHandler {
  ExecutionInstruction handle({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    return ExecutionInstruction.continueExecution;
  }
}
