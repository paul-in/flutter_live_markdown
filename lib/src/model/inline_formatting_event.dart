import 'package:super_editor/super_editor.dart';

class InlineFormattingRefreshEvent extends NodeChangeEvent {
  const InlineFormattingRefreshEvent(super.nodeId);

  @override
  String describe() => "Inline formatting refresh: $nodeId";

  @override
  String toString() => "InlineFormattingRefreshEvent ($nodeId)";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineFormattingRefreshEvent &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId;

  @override
  int get hashCode => nodeId.hashCode;
}
