import 'package:super_editor/super_editor.dart';

import '../model/inline_formatting_event.dart';
import '../model/markdown_node_metadata.dart';
import '../parsing/markdown_utils.dart';
import '../parsing/inline_formatter.dart';
import 'refresh_inline_formatting.dart';

// Listens every change in text and adjust inline/block styling instantly when typing 
class RawFormattingReaction extends EditReaction {
  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final doc = editorContext.find(Editor.documentKey) as Document;
    final requests = <EditRequest>[];

    for (final ev in changeList) {
      if (ev is! DocumentEdit) continue;
      final change = ev.change;

      // Skip our own refresh events to avoid loops
      if (change is InlineFormattingRefreshEvent) continue;
      if (change is! NodeChangeEvent) continue;

      final node = doc.getNodeById(change.nodeId);
      if (node is! TextNode) continue;
      if (node.metadata['isRawMode'] != true) continue;

      final raw = node.text.toPlainText();
      final formatted = applyInlineFormatting(raw);

      // Re-detect block type (#, >, etc.) — preserve blockquote attribution
      final parsed = parseBlockquote(raw);
      final blockType = parsed.isBlockquote
          ? blockquoteAttribution
          : detectBlockType(parsed.text);

      // Skip only if spans AND blockType already match
      if (formatted == node.text && blockType == node.metadata[NodeMetadata.blockType]) continue;

      final meta = MarkdownNodeMetadata.fromNode(node);
      final newMeta = meta.copyWith(rawMarkdown: raw, isRawMode: true).toMap();
      if (blockType != null) {
        newMeta[NodeMetadata.blockType] = blockType;
      }

      requests.add(RefreshInlineFormattingRequest(
        nodeId: node.id,
        newNode: ParagraphNode(
          id: node.id,
          text: formatted,
          metadata: newMeta,
        ),
      ));
    }

    if (requests.isNotEmpty) {
      requestDispatcher.execute(requests);
    }
  }
}
