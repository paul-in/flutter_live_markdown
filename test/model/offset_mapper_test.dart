import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_markdown/src/model/offset_mapper.dart';

void main() {
  group('mapVisualToRawOffset', () {
    test('plain text maps 1:1', () {
      const visual = 'hello';
      const raw = 'hello';
      expect(mapVisualToRawOffset(visual, raw, 0), 0);
      expect(mapVisualToRawOffset(visual, raw, 3), 3);
      expect(mapVisualToRawOffset(visual, raw, 5), 5);
    });

    test('bold markers: offset before formatted word is before markers', () {
      const visual = 'hello world';
      const raw = 'hello **world**';
      // visual[6] = 'w' is the first char of the formatted word
      // Position before 'w' → raw offset 6 (before '**')
      expect(mapVisualToRawOffset(visual, raw, 6), 6);
    });

    test('bold markers: offset at first char inside formatted word', () {
      const visual = 'hello world';
      const raw = 'hello **world**';
      // visual offset 7 = after 'w', which is inside formatted content
      // Should skip the opening markers
      expect(mapVisualToRawOffset(visual, raw, 7), 9);
    });

    test('italic markers: offset before formatted word is before marker', () {
      const visual = 'hello world';
      const raw = 'hello *world*';
      expect(mapVisualToRawOffset(visual, raw, 6), 6);
    });

    test('end of visual pushes past trailing markers', () {
      const visual = 'hello';
      const raw = '**hello**';
      // At end of visual, push past trailing markers
      expect(mapVisualToRawOffset(visual, raw, 5), 9);
    });
  });

  group('mapRawToVisualOffset', () {
    test('plain text maps 1:1', () {
      const visual = 'hello';
      const raw = 'hello';
      expect(mapRawToVisualOffset(visual, raw, 0), 0);
      expect(mapRawToVisualOffset(visual, raw, 3), 3);
      expect(mapRawToVisualOffset(visual, raw, 5), 5);
    });

    test('bold markers: offset at markers maps to before formatted word', () {
      const visual = 'hello world';
      const raw = 'hello **world**';
      // raw[6..7] = '**' → visual position before 'w'
      expect(mapRawToVisualOffset(visual, raw, 6), 6);
    });

    test('offset inside formatted word maps correctly', () {
      const visual = 'hello world';
      const raw = 'hello **world**';
      // raw[9] = 'o' (inside bold) → visual[7]
      expect(mapRawToVisualOffset(visual, raw, 9), 7);
    });

    test('offset at end maps past trailing markers', () {
      const visual = 'hello';
      const raw = '**hello**';
      expect(mapRawToVisualOffset(visual, raw, 9), 5);
    });
  });
}
