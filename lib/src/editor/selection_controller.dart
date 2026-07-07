import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';
import '../model/offset_mapper.dart';
import 'editor_state.dart';

class SelectionController {
  final EditorState editorState;

  SelectionController(this.editorState);

  int getGlobalRawOffset(DocumentPosition position) {
    int globalRawOffset = 0;

    for (final node in editorState.document) {
      if (node.id == position.nodeId) {
        if (node is TextNode && position.nodePosition is TextNodePosition) {
          final pos = position.nodePosition as TextNodePosition;
          int localRawOffset = pos.offset;

          final meta = MarkdownNodeMetadata.fromNode(node);
          if (!meta.isRawMode) {
            final visual = node.text.toPlainText();
            localRawOffset = mapVisualToRawOffset(visual, meta.rawMarkdown, pos.offset);
          }

          return globalRawOffset + localRawOffset;
        }
        return globalRawOffset;
      }

      if (node is TextNode) {
        final meta = MarkdownNodeMetadata.fromNode(node);
        globalRawOffset += meta.rawMarkdown.length;
      } else if (node.metadata['isImage'] == true) {
        final url = node.metadata['imageUrl'] ?? '';
        globalRawOffset += '![image]($url)'.length;
      }

      globalRawOffset += 2; // \n\n
    }

    return globalRawOffset;
  }

  (int, int) getSelectionOffsets() {
    final sel = editorState.composer.selection;
    if (sel == null) return (0, 0);
    return (getGlobalRawOffset(sel.base), getGlobalRawOffset(sel.extent));
  }

  String getContentBetween(int start, int end) {
    final raw = editorState.document
        .map((n) => MarkdownNodeMetadata.fromNode(n).rawMarkdown)
        .join('\n\n');
    if (start < 0) start = 0;
    if (end > raw.length) end = raw.length;
    if (start >= end) return '';
    return raw.substring(start, end);
  }

  void scrollTo(int rawOffset) {
    DocumentPosition? targetPos;
    int accumulated = 0;

    for (final node in editorState.document) {
      final meta = MarkdownNodeMetadata.fromNode(node);
      final nodeLen = meta.rawMarkdown.length;

      if (rawOffset >= accumulated && rawOffset <= accumulated + nodeLen) {
        final localOffset = rawOffset - accumulated;
        targetPos = DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: localOffset),
        );
        break;
      }

      accumulated += nodeLen + 2; // +2 for \n\n
    }

    if (targetPos != null) {
      editorState.composer.setSelectionWithReason(
        DocumentSelection.collapsed(position: targetPos),
      );
      // Scroll will follow via super_editor's scroll machinery
    }
  }

  void clearSelection() {
    editorState.composer.clearSelection();
  }
}
