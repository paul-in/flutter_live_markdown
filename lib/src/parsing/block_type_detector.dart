// Unused for now
import 'package:dart_markdown/dart_markdown.dart' as md;

enum MarkdownBlockType {
  paragraph,
  atxHeading,
  setextHeading,
  blockquote,
  fencedCodeBlock,
  indentedCodeBlock,
  bulletList,
  orderedList,
  listItem,
  thematicBreak,
  table,
}

final List<(RegExp, MarkdownBlockType)> _prefixMatchers = [
  (RegExp(r'^ {0,3}(`{3,}|~{3,})'), MarkdownBlockType.fencedCodeBlock),
];

MarkdownBlockType detectBlockTypeFromAST(String raw) {
  if (raw.trim().isEmpty) return MarkdownBlockType.paragraph;

  final firstLine = raw.split('\n').first;
  for (final (regex, type) in _prefixMatchers) {
    if (regex.hasMatch(firstLine)) return type;
  }

  final parser = md.Markdown();
  final nodes = parser.parse(raw);
  if (nodes.isEmpty) return MarkdownBlockType.paragraph;
  final first = nodes.first;
  if (first is! md.Element) return MarkdownBlockType.paragraph;
  return switch (first.type) {
    'atxHeading' => MarkdownBlockType.atxHeading,
    'setextHeading' => MarkdownBlockType.setextHeading,
    'blockquote' => MarkdownBlockType.blockquote,
    'fencedCodeBlock' => MarkdownBlockType.fencedCodeBlock,
    'indentedCodeBlock' => MarkdownBlockType.indentedCodeBlock,
    'bulletList' => MarkdownBlockType.bulletList,
    'orderedList' => MarkdownBlockType.orderedList,
    'listItem' => MarkdownBlockType.listItem,
    'thematicBreak' => MarkdownBlockType.thematicBreak,
    'table' => MarkdownBlockType.table,
    _ => MarkdownBlockType.paragraph,
  };
}

bool isMultilineBlock(MarkdownBlockType type) {
  return switch (type) {
    MarkdownBlockType.fencedCodeBlock ||
    MarkdownBlockType.indentedCodeBlock ||
    MarkdownBlockType.blockquote ||
    MarkdownBlockType.table => true,
    _ => false,
  };
}

String? detectContinuationPrefix(String raw) {
  final type = detectBlockTypeFromAST(raw);
  switch (type) {
    case MarkdownBlockType.blockquote:
      return '> ';
    case MarkdownBlockType.bulletList:
      final match = RegExp(r'^ {0,3}([*+\-])\s').firstMatch(raw);
      return '${match?.group(1) ?? '-'} ';
    case MarkdownBlockType.orderedList:
      final match = RegExp(r'^ {0,3}(\d+)\.\s').firstMatch(raw);
      if (match != null) {
        final num = int.parse(match.group(1)!);
        return '${num + 1}. ';
      }
      return '1. ';
    default:
      return null;
  }
}

bool isEmptyBlockquoteLine(String raw) {
  final type = detectBlockTypeFromAST(raw);
  if (type != MarkdownBlockType.blockquote) return false;
  final stripped = raw.split('\n').map((l) => l.replaceFirst(RegExp(r'^>\s?'), '').trim()).join();
  return stripped.isEmpty;
}

bool isEmptyListItem(String raw) {
  final type = detectBlockTypeFromAST(raw);
  if (type == MarkdownBlockType.bulletList) {
    return RegExp(r'^ {0,3}[*+\-]\s*$').hasMatch(raw.trim());
  }
  if (type == MarkdownBlockType.orderedList) {
    return RegExp(r'^ {0,3}\d+\.\s*$').hasMatch(raw.trim());
  }
  return false;
}
