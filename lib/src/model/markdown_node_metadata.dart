import 'package:super_editor/super_editor.dart';

class MarkdownNodeMetadata {
  final String rawMarkdown;
  final bool isRawMode;

  const MarkdownNodeMetadata({
    required this.rawMarkdown,
    this.isRawMode = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'rawMarkdown': rawMarkdown,
      'isRawMode': isRawMode,
    };
  }

  MarkdownNodeMetadata copyWith({
    String? rawMarkdown,
    bool? isRawMode,
  }) {
    return MarkdownNodeMetadata(
      rawMarkdown: rawMarkdown ?? this.rawMarkdown,
      isRawMode: isRawMode ?? this.isRawMode,
    );
  }

  static MarkdownNodeMetadata fromNode(DocumentNode node) {
    final md = node.metadata;
    return MarkdownNodeMetadata(
      rawMarkdown: md['rawMarkdown'] as String? ?? '',
      isRawMode: md['isRawMode'] as bool? ?? false,
    );
  }
}
