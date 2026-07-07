import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_markdown/src/parsing/markdown_splitter.dart';
import 'package:flutter_live_markdown/src/model/markdown_block.dart';

void main() {
  group('splitMarkdownIntoBlocks', () {
    test('empty string returns empty list', () {
      expect(splitMarkdownIntoBlocks(''), isEmpty);
    });

    test('single paragraph returns one block', () {
      final blocks = splitMarkdownIntoBlocks('Hello world');
      expect(blocks.length, 1);
      expect(blocks[0].text, 'Hello world');
    });

    test('heading returns one block', () {
      final blocks = splitMarkdownIntoBlocks('# Title');
      expect(blocks.length, 1);
      expect(blocks[0].text, '# Title');
    });

    test('two paragraphs separated by blank line', () {
      final blocks = splitMarkdownIntoBlocks('First paragraph\n\nSecond paragraph');
      expect(blocks.length, 2);
      expect(blocks[0].text, 'First paragraph');
      expect(blocks[1].text, 'Second paragraph');
    });

    test('headers produce correct block text', () {
      final blocks = splitMarkdownIntoBlocks('# H1\n\n## H2\n\n### H3');
      expect(blocks.length, 3);
      expect(blocks[0].text, '# H1');
      expect(blocks[1].text, '## H2');
      expect(blocks[2].text, '### H3');
    });

    test('bold and italic markers preserved in block text', () {
      final blocks = splitMarkdownIntoBlocks('This is **bold** and *italic*');
      expect(blocks.length, 1);
      expect(blocks[0].text, 'This is **bold** and *italic*');
    });

    test('inline code preserved', () {
      final blocks = splitMarkdownIntoBlocks('Use `code` inline');
      expect(blocks.length, 1);
      expect(blocks[0].text, 'Use `code` inline');
    });

    test('horizontal rule', () {
      final blocks = splitMarkdownIntoBlocks('Before\n\n---\n\nAfter');
      expect(blocks.length, 3); // paragraph, hr, paragraph
      expect(blocks[1].text, '---');
    });

    test('blockquote', () {
      final blocks = splitMarkdownIntoBlocks('> A blockquote');
      expect(blocks.length, 1);
      expect(blocks[0].text, '> A blockquote');
    });

    test('blockquote with multiple lines', () {
      final blocks = splitMarkdownIntoBlocks('> Line 1\n> Line 2');
      expect(blocks.length, 1);
      expect(blocks[0].text, '> Line 1\n> Line 2');
    });

    test('image syntax preserved', () {
      final blocks = splitMarkdownIntoBlocks('![alt](https://example.com/img.png)');
      expect(blocks.length, 1);
      expect(blocks[0].text, '![alt](https://example.com/img.png)');
    });

    test('link syntax preserved', () {
      final blocks = splitMarkdownIntoBlocks('[link](https://example.com)');
      expect(blocks.length, 1);
      expect(blocks[0].text, '[link](https://example.com)');
    });

    test('positions are correct', () {
      const raw = '# Title\n\nParagraph';
      final blocks = splitMarkdownIntoBlocks(raw);
      expect(blocks.length, 2);
      expect(raw.substring(blocks[0].startOffset, blocks[0].endOffset), '# Title');
      expect(raw.substring(blocks[1].startOffset, blocks[1].endOffset), 'Paragraph');
    });
  });
}
