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
  }

  void restore(DocumentLayout layout, ScrollController scrollCtrl) {}
}
