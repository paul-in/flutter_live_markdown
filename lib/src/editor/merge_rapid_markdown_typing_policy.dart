import 'package:super_editor/super_editor.dart';

import '../model/inline_formatting_event.dart';

// override default super_editor input merging for undo/redo that considers each input + styling as separate transactions (which is not the case from the user pov).
// This is the standard way of doing it to implement HistoryGroupingPolicy
class MergeRapidMarkdownTypingPolicy implements HistoryGroupingPolicy {
  const MergeRapidMarkdownTypingPolicy([this._maxMergeTime = const Duration(milliseconds: 100)]);

  final Duration _maxMergeTime;

  @override
  TransactionMerge shouldMergeLatestTransaction(
      CommandTransaction newTransaction, CommandTransaction previousTransaction) {
    final newContentEvents = newTransaction.changes
        .where((change) => change is! SelectionChangeEvent && change is! ComposingRegionChangeEvent)
        .toList();
    if (newContentEvents.isEmpty) {
      return TransactionMerge.noOpinion;
    }

    if (!_allAreTypingOrRefresh(newContentEvents)) {
      return TransactionMerge.noOpinion;
    }

    final previousContentEvents = previousTransaction.changes
        .where((change) => change is! SelectionChangeEvent && change is! ComposingRegionChangeEvent)
        .toList();
    if (previousContentEvents.isEmpty) {
      return TransactionMerge.noOpinion;
    }

    if (!_allAreTypingOrRefresh(previousContentEvents)) {
      return TransactionMerge.noOpinion;
    }

    if (newTransaction.firstChangeTime.difference(previousTransaction.lastChangeTime) > _maxMergeTime) {
      return TransactionMerge.noOpinion;
    }

    return TransactionMerge.mergeOnTop;
  }

  bool _allAreTypingOrRefresh(List<EditEvent> events) {
    for (final event in events) {
      if (event is! DocumentEdit) return false;
      final change = event.change;
      if (change is TextInsertionEvent) continue;
      if (change is InlineFormattingRefreshEvent) continue;
      return false;
    }
    return true;
  }
}
