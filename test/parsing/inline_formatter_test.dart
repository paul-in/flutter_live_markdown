import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_markdown/src/parsing/inline_formatter.dart';

void main() {
  group('applyInlineFormatting', () {
    test('empty string returns empty text', () {
      final result = applyInlineFormatting('');
      expect(result.toPlainText(), '');
    });

    test('plain text is unchanged', () {
      final result = applyInlineFormatting('Hello world');
      expect(result.toPlainText(), 'Hello world');
    });

    test('bold markers are preserved in raw text', () {
      final result = applyInlineFormatting('Hello **world**');
      // Raw text should contain the markers
      expect(result.toPlainText(), 'Hello **world**');
    });

    test('italic markers are preserved', () {
      final result = applyInlineFormatting('Hello *world*');
      expect(result.toPlainText(), 'Hello *world*');
    });

    test('code backticks are preserved', () {
      final result = applyInlineFormatting('Use `code` here');
      expect(result.toPlainText(), 'Use `code` here');
    });

    test('link syntax is preserved', () {
      final result = applyInlineFormatting('[a link](https://example.com)');
      expect(result.toPlainText(), '[a link](https://example.com)');
    });

    test('multiple inline elements', () {
      final result = applyInlineFormatting('**bold** and *italic* and `code`');
      expect(result.toPlainText(), '**bold** and *italic* and `code`');
    });

    test('AttributedSpans has bold attribution for bold text', () {
      final result = applyInlineFormatting('Hello **world**');
      final plain = result.toPlainText();
      // The plain text should have markers
      expect(plain, 'Hello **world**');

      // The spans should include a bold attribution
      final spans = result.spans;
      expect(spans, isNotNull);
      // There should be at least one marker spanning "world"
      // (the markers are between hello** and ** — the attribution covers world)
      expect(spans.markers.where((m) => m.attribution.id == 'bold'), isNotEmpty);
    });
  });
}
