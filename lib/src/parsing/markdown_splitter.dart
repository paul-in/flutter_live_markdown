import 'package:dart_markdown/dart_markdown.dart' as md;
import '../model/markdown_block.dart';

List<MarkdownBlock> splitMarkdownIntoBlocks(String raw) {
  if (raw.isEmpty) return [];

  final document = md.Markdown();
  final nodes = document.parse(raw);

  List<md.Element> flattenLists(List<md.Node> list) {
    final res = <md.Element>[];
    for (final n in list) {
      if (n is md.Element) {
        if (n.type == 'bulletList' || n.type == 'orderedList') {
          res.addAll(flattenLists(n.children ?? []));
        } else if (n.type == 'listItem') {
          res.add(n);
          if (n.children != null) {
            res.addAll(flattenLists(n.children!));
          }
        } else {
          res.add(n);
        }
      }
    }
    return res;
  }

  final elements = flattenLists(nodes);

  final blocks = <MarkdownBlock>[];
  int lastEnd = 0;

  for (int i = 0; i < elements.length; i++) {
    final node = elements[i];
    int nodeStart = node.start.offset;
    int nodeEnd = node.end.offset;

    if (nodeEnd <= lastEnd) continue;
    if (nodeStart < lastEnd) nodeStart = lastEnd;

    for (int j = i + 1; j < elements.length; j++) {
      final nextNode = elements[j];
      if (nextNode.start.offset > nodeStart && nextNode.start.offset < nodeEnd) {
        nodeEnd = nextNode.start.offset;
        break;
      }
    }

    final gap = raw.substring(lastEnd, nodeStart);
    int newlines = '\n'.allMatches(gap).length;

    int emptyBlocksCount;
    if (lastEnd == 0) {
      emptyBlocksCount = newlines;
    } else {
      emptyBlocksCount = (newlines - 2).clamp(0, 999999);
    }

    for (int i = 0; i < emptyBlocksCount; i++) {
      blocks.add(MarkdownBlock('', lastEnd, lastEnd));
    }

    blocks.add(MarkdownBlock(
      raw.substring(nodeStart, nodeEnd),
      nodeStart,
      nodeEnd,
    ));
    lastEnd = nodeEnd;
  }

  final endGap = raw.substring(lastEnd, raw.length);
  int endNewlines = '\n'.allMatches(endGap).length;
  int endEmptyBlocksCount;
  if (nodes.isEmpty) {
    endEmptyBlocksCount = endNewlines;
  } else {
    endEmptyBlocksCount = (endNewlines - 1).clamp(0, 999999);
  }

  for (int i = 0; i < endEmptyBlocksCount; i++) {
    blocks.add(MarkdownBlock('', lastEnd, lastEnd));
  }

  return blocks;
}
