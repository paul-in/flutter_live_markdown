import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:flutter_live_markdown/src/model/markdown_node_metadata.dart';

void main() {
  group('MarkdownNodeMetadata', () {
    test('default constructor creates non-raw mode', () {
      final meta = MarkdownNodeMetadata(rawMarkdown: 'test');
      expect(meta.rawMarkdown, 'test');
      expect(meta.isRawMode, false);
      expect(meta.isBlockquote, false);
    });

    test('toMap serializes all fields', () {
      final meta = MarkdownNodeMetadata(
        rawMarkdown: '**bold**',
        isRawMode: true,
        isBlockquote: true,
      );
      final map = meta.toMap();
      expect(map['rawMarkdown'], '**bold**');
      expect(map['isRawMode'], true);
      expect(map['isBlockquote'], true);
    });

    test('copyWith updates specified fields', () {
      final meta = MarkdownNodeMetadata(rawMarkdown: 'hello');
      final updated = meta.copyWith(isRawMode: true);
      expect(updated.rawMarkdown, 'hello');
      expect(updated.isRawMode, true);
      expect(updated.isBlockquote, false);
    });

    test('fromNode reads from metadata map', () {
      final node = ParagraphNode(
        id: 'test',
        text: AttributedText(''),
        metadata: {
          'rawMarkdown': '**bold**',
          'isRawMode': true,
          'isBlockquote': false,
        },
      );
      final meta = MarkdownNodeMetadata.fromNode(node);
      expect(meta.rawMarkdown, '**bold**');
      expect(meta.isRawMode, true);
      expect(meta.isBlockquote, false);
    });

    test('fromNode handles missing fields gracefully', () {
      final node = ParagraphNode(
        id: 'test',
        text: AttributedText(''),
        metadata: {},
      );
      final meta = MarkdownNodeMetadata.fromNode(node);
      expect(meta.rawMarkdown, '');
      expect(meta.isRawMode, false);
      expect(meta.isBlockquote, false);
    });
  });
}
