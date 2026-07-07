import 'package:super_editor/super_editor.dart';

class MarkdownNodeMetadata {
  final String rawMarkdown;
  final bool isRawMode;
  final bool isBlockquote;

  const MarkdownNodeMetadata({
    required this.rawMarkdown,
    this.isRawMode = false,
    this.isBlockquote = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'rawMarkdown': rawMarkdown,
      'isRawMode': isRawMode,
      'isBlockquote': isBlockquote,
    };
  }

  MarkdownNodeMetadata copyWith({
    String? rawMarkdown,
    bool? isRawMode,
    bool? isBlockquote,
  }) {
    return MarkdownNodeMetadata(
      rawMarkdown: rawMarkdown ?? this.rawMarkdown,
      isRawMode: isRawMode ?? this.isRawMode,
      isBlockquote: isBlockquote ?? this.isBlockquote,
    );
  }

  static MarkdownNodeMetadata fromNode(DocumentNode node) {
    final md = node.metadata;
    return MarkdownNodeMetadata(
      rawMarkdown: md['rawMarkdown'] as String? ?? '',
      isRawMode: md['isRawMode'] as bool? ?? false,
      isBlockquote: md['isBlockquote'] as bool? ?? false,
    );
  }
}
