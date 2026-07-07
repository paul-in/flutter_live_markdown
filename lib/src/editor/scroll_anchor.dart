import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

class ScrollAnchor {
  String? _anchorNodeId;
  double _relativeY = 0;
  double? _fallbackOffset;

  void save(
    DocumentLayout layout,
    ScrollController scrollCtrl,
    Set<String> toBlur,
    Set<String> toFocus,
  ) {
    _anchorNodeId = null;
    _relativeY = 0;
    _fallbackOffset = null;

    if (!scrollCtrl.hasClients) return;

    final scrollOffset = scrollCtrl.offset;
    final viewportHeight = scrollCtrl.position.viewportDimension;

    if (viewportHeight <= 0) return;

    // Try to find a stable node (not blurring, not focusing) in the viewport
    String? stableId;
    double nodeTop = 0;

    for (final nodeId in _getVisibleNodeIds(layout, scrollOffset, scrollOffset + viewportHeight)) {
      if (!toBlur.contains(nodeId) && !toFocus.contains(nodeId)) {
        final rect = layout.getRectForPosition(
          DocumentPosition(nodeId: nodeId, nodePosition: const TextNodePosition(offset: 0)),
        );
        if (rect != null && rect.top >= scrollOffset) {
          stableId = nodeId;
          nodeTop = rect.top;
          break;
        }
      }
    }

    if (stableId != null) {
      _anchorNodeId = stableId;
      _relativeY = scrollOffset - nodeTop;
    } else {
      _fallbackOffset = scrollOffset;
    }
  }

  void restore(DocumentLayout layout, ScrollController scrollCtrl) {
    if (!scrollCtrl.hasClients) return;

    if (_anchorNodeId != null) {
      final rect = layout.getRectForPosition(
        DocumentPosition(nodeId: _anchorNodeId!, nodePosition: const TextNodePosition(offset: 0)),
      );
      if (rect != null) {
        final newOffset = rect.top + _relativeY;
        scrollCtrl.jumpTo(newOffset.clamp(0, scrollCtrl.position.maxScrollExtent));
        return;
      }
    }

    if (_fallbackOffset != null) {
      scrollCtrl.jumpTo(
        _fallbackOffset!.clamp(0, scrollCtrl.position.maxScrollExtent),
      );
    }
  }

  List<String> _getVisibleNodeIds(
    DocumentLayout layout,
    double top,
    double bottom,
  ) {
    final ids = <String>[];
    // Iterate through a range of positions to find visible nodes
    for (double y = top; y <= bottom; y += 50) {
      final pos = layout.getDocumentPositionAtOffset(Offset(0, y));
      if (pos != null && !ids.contains(pos.nodeId)) {
        ids.add(pos.nodeId);
      }
    }
    return ids;
  }
}
