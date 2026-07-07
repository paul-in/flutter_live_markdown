import 'package:super_editor/super_editor.dart';

/// Strips blockquote markers (`> `) from each line of [raw].
/// Returns the stripped text and whether blockquote markers were found.
({String text, bool isBlockquote}) parseBlockquote(String raw) {
  if (!raw.trim().startsWith('>')) {
    return (text: raw, isBlockquote: false);
  }
  final stripped = raw.split('\n').map((l) {
    final match = RegExp(r'^>\s?').firstMatch(l);
    return match != null ? l.substring(match.end) : l;
  }).join('\n');
  return (text: stripped, isBlockquote: true);
}

/// Parses [raw] markdown and returns the block type attribution.
/// Returns null if the content is empty.
Attribution? detectBlockType(String raw) {
  if (raw.trim().isEmpty) return paragraphAttribution;
  final doc = deserializeMarkdownToDocument(raw);
  if (doc.isEmpty) return paragraphAttribution;
  return doc.first.getMetadataValue(NodeMetadata.blockType) as Attribution?;
}
