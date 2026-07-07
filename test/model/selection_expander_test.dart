import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_markdown/src/model/offset_mapper.dart';
import 'package:flutter_live_markdown/src/model/selection_expander.dart';

void main() {
  group('markerRegions', () {
    test('returns empty for plain text without markers', () {
      expect(markerRegions('hello', 'hello'), isEmpty);
    });

    test('detects bold markers', () {
      expect(markerRegions('bold', '**bold**'), [
        (start: 0, end: 2),
        (start: 6, end: 8),
      ]);
    });

    test('detects italic markers', () {
      expect(markerRegions('italic', '*italic*'), [
        (start: 0, end: 1),
        (start: 7, end: 8),
      ]);
    });

    test('detects code backtick markers', () {
      expect(markerRegions('suis', '`suis`'), [
        (start: 0, end: 1),
        (start: 5, end: 6),
      ]);
    });

    test('detects strikethrough markers', () {
      expect(markerRegions('strike', '~~strike~~'), [
        (start: 0, end: 2),
        (start: 8, end: 10),
      ]);
    });

    test('detects link markers with asymmetric syntax', () {
      // raw = "[lien](texte)" = 13 chars
      // visual = "lien" = 4 chars
      expect(markerRegions('lien', '[lien](texte)'), [
        (start: 0, end: 1),
        (start: 5, end: 13),
      ]);
    });

    test('detects markers around word in sentence', () {
      expect(
        markerRegions('je suis developpeur', 'je `suis` developpeur'),
        [
          (start: 3, end: 4),
          (start: 8, end: 9),
        ],
      );
    });

    test('returns empty for image placeholder (\\uFFFC)', () {
      expect(markerRegions('\uFFFC', '![alt](url.png)'), isEmpty);
    });

    test('handles consecutive markers (bold only)', () {
      // raw = "**bold+ital**", visual = "bold+ital"
      // raw: *(0) *(1) b(2) o(3) l(4) d(5) +(6) i(7) t(8) a(9) l(10) *(11) *(12)
      // length: 13
      expect(markerRegions('bold+ital', '**bold+ital**'), [
        (start: 0, end: 2),
        (start: 11, end: 13),
      ]);
    });
  });

  group('expandStartEdge', () {
    test('expands at opening marker boundary', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(expandStartEdge(visual, raw, 2), 0);
    });

    test('does not expand inside content', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(expandStartEdge(visual, raw, 3), 3);
    });

    test('expands to swallow adjacent marker regions', () {
      final visual = 'italic';
      final raw = '[_italic_](url)';
      expect(expandStartEdge(visual, raw, 2), 0);
    });
  });

  group('expandEndEdge', () {
    test('expands at closing marker boundary', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(expandEndEdge(visual, raw, 6), 8);
    });

    test('does not expand inside content', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(expandEndEdge(visual, raw, 5), 5);
    });

    test('expands to swallow adjacent closing markers (link)', () {
      final visual = 'lien';
      final raw = '[lien](texte)';
      expect(expandEndEdge(visual, raw, 5), 13);
    });
  });

  group('expandSelectionToMarkers', () {
    test('expands full content in bold', () {
      final visual = 'bold';
      final raw = '**bold**';
      final (start, end) = expandSelectionToMarkers(visual, raw, 2, 6);
      expect(start, 0);
      expect(end, 8);
    });

    test('expands only closing markers for partial selection in link', () {
      final visual = 'lien';
      final raw = '[lien](texte)';
      final (start, end) = expandSelectionToMarkers(visual, raw, 2, 5);
      expect(start, 2);
      expect(end, 13);
    });

    test('expands both sides for backtick code', () {
      final visual = 'suis';
      final raw = '`suis`';
      final (start, end) = expandSelectionToMarkers(visual, raw, 1, 5);
      expect(start, 0);
      expect(end, 6);
    });

    test('expands both sides for inline code in sentence', () {
      final visual = 'je suis developpeur';
      final raw = 'je `suis` developpeur';
      final (start, end) = expandSelectionToMarkers(visual, raw, 4, 8);
      expect(start, 3);
      expect(end, 9);
    });

    test('expands both sides for full link', () {
      final visual = 'lien';
      final raw = '[lien](texte)';
      final (start, end) = expandSelectionToMarkers(visual, raw, 1, 5);
      expect(start, 0);
      expect(end, 13);
    });

    test('returns same range for collapsed selection', () {
      final visual = 'bold';
      final raw = '**bold**';
      final (start, end) = expandSelectionToMarkers(visual, raw, 4, 4);
      expect(start, 4);
      expect(end, 4);
    });

    test('preserves orientation when selection is reversed', () {
      final visual = 'bold';
      final raw = '**bold**';
      // rawStart=5 (at 'd'), rawEnd=2 (at 'b')
      // selMin=2 expands to 0, selMax=5 not at boundary
      // rawStart>rawEnd → return (selMax=5, selMin=0)
      final (start, end) = expandSelectionToMarkers(visual, raw, 5, 2);
      expect(start, 5);
      expect(end, 0);
    });

    test('preserves orientation with reversed selection at boundaries', () {
      final visual = 'bold';
      final raw = '**bold**';
      // Full reversed: base=6 (closing marker), extent=2 (opening content edge)
      // selMin=2 expands to 0, selMax=6 expands to 8
      // rawStart>rawEnd → return (8, 0)
      final (start, end) = expandSelectionToMarkers(visual, raw, 6, 2);
      expect(start, 8);
      expect(end, 0);
    });
  });

  group('expandEdge', () {
    test('expands left when right after opening marker', () {
      final visual = 'bold';
      final raw = '**bold**';
      final expanded = expandEdge(visual, raw, 2);
      expect(expanded, 0);
    });

    test('expands right when at closing marker start', () {
      final visual = 'bold';
      final raw = '**bold**';
      final expanded = expandEdge(visual, raw, 6);
      expect(expanded, 8);
    });

    test('expands left for offset after opening marker (link)', () {
      final visual = 'lien';
      final raw = '[lien](texte)';
      // offset=1 (right after '[')
      // left expands to 0, right doesn't change
      final expanded = expandEdge(visual, raw, 1);
      expect(expanded, 0);
    });

    test('expands right for offset at closing marker start (link)', () {
      final visual = 'lien';
      final raw = '[lien](texte)';
      // offset=5 (at ']', start of closing marker region)
      // left doesn't change, right expands to 13
      final expanded = expandEdge(visual, raw, 5);
      expect(expanded, 13);
    });

    test('does not expand offset inside content', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(expandEdge(visual, raw, 3), 3);
      expect(expandEdge(visual, raw, 4), 4);
    });

    test('no expansion for image placeholder', () {
      final visual = '\uFFFC';
      final raw = '![alt](url.png)';
      expect(expandEdge(visual, raw, 0), 0);
      expect(expandEdge(visual, raw, 16), 16);
    });
  });
}
