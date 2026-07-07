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

  group('adjustCursorAtMarkerBoundary', () {
    test('pushes past opening markers at start of bold', () {
      final visual = 'bold';
      final raw = '**bold**';
      // raw 0 = start of opening **
      expect(adjustCursorAtMarkerBoundary(visual, raw, 0), 2);
    });

    test('stays at closing marker boundary', () {
      final visual = 'bold';
      final raw = '**bold**';
      // raw 6 = start of closing **
      expect(adjustCursorAtMarkerBoundary(visual, raw, 6), 6);
    });

    test('pushes past opening markers in mid-paragraph', () {
      final visual = 'du texte bold et suite';
      final raw = 'du texte **bold** et suite';
      // raw 9 = start of opening ** (after "du texte ")
      expect(adjustCursorAtMarkerBoundary(visual, raw, 9), 11);
    });

    test('stays at closing marker boundary in mid-paragraph', () {
      final visual = 'du texte bold et suite';
      final raw = 'du texte **bold** et suite';
      // raw 15 = start of closing **
      expect(adjustCursorAtMarkerBoundary(visual, raw, 15), 15);
    });

    test('no adjustment for position not at marker boundary', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 3), 3);
      expect(adjustCursorAtMarkerBoundary(visual, raw, 4), 4);
    });

    test('no adjustment for plain text without markers', () {
      final visual = 'hello';
      final raw = 'hello';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 0), 0);
      expect(adjustCursorAtMarkerBoundary(visual, raw, 3), 3);
      expect(adjustCursorAtMarkerBoundary(visual, raw, 5), 5);
    });

    test('pushes past opening markers for consecutive bold runs', () {
      // **a** **b**
      // raw = "**a** **b**", visual = "a b"
      final visual = 'a b';
      final raw = '**a** **b**';
      // raw 0 = start of first opening **
      expect(adjustCursorAtMarkerBoundary(visual, raw, 0), 2);
      // raw 3 = start of first closing ** (after content 'a')
      expect(adjustCursorAtMarkerBoundary(visual, raw, 3), 3);
      // raw 6 = start of second opening **
      expect(adjustCursorAtMarkerBoundary(visual, raw, 6), 8);
      // raw 9 = start of second closing **
      expect(adjustCursorAtMarkerBoundary(visual, raw, 9), 9);
    });

    test('insideMarkers: false stays before opening markers', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 0, insideMarkers: false), 0);
    });

    test('insideMarkers: false pushes past closing markers', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 6, insideMarkers: false), 8);
    });

    test('insideMarkers: false mid-paragraph opening stays', () {
      final visual = 'du texte bold et suite';
      final raw = 'du texte **bold** et suite';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 9, insideMarkers: false), 9);
    });

    test('insideMarkers: false mid-paragraph closing pushes past', () {
      final visual = 'du texte bold et suite';
      final raw = 'du texte **bold** et suite';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 15, insideMarkers: false), 17);
    });

    test('insideMarkers: default true matches existing behavior', () {
      final visual = 'bold';
      final raw = '**bold**';
      expect(adjustCursorAtMarkerBoundary(visual, raw, 0), 2);
      expect(adjustCursorAtMarkerBoundary(visual, raw, 6), 6);
    });
  });

  group('link with title - AST-based markerRegions', () {
    test('standalone link with title: closing region includes full syntax (no split at space)', () {
      final visual = 'Atelocynus';
      final raw = '[Atelocynus](https://fr.wikipedia.org/wiki/Atelocynus "Atelocynus")';
      final regions = markerRegions(visual, raw);
      expect(regions.length, 2);
      expect(regions[0], (start: 0, end: 1)); // '['
      // closing region should cover everything after the text (including space + title)
      expect(regions[1].end, raw.length); // includes entire closing syntax
      // Verify the raw in this region contains the title
      final rawText = raw.substring(regions[1].start, regions[1].end);
      expect(rawText, contains('"Atelocynus"'));
      expect(rawText, contains(')'));
    });

    test('expansion includes full link with title', () {
      final visual = 'Atelocynus';
      final raw = '[Atelocynus](https://fr.wikipedia.org/wiki/Atelocynus "Atelocynus")';
      // rawStart=1 (inside [), rawEnd=11 (at ])
      final (start, end) = expandSelectionToMarkers(visual, raw, 1, raw.indexOf(']'));
      expect(start, 0); // includes [
      expect(end, raw.length); // includes full closing syntax
    });

    test('mid-paragraph link with title: closing region not split at space', () {
      final visual = 'du texte Atelocynus et suite';
      final raw = 'du texte [Atelocynus](https://fr.wikipedia.org/wiki/Atelocynus "Atelocynus") et suite';
      final regions = markerRegions(visual, raw);
      // There should be exactly 2 marker regions (opening [ and closing ...])
      // if the space before title is handled correctly
      expect(regions.length, 2);
      // first region: the '['
      expect(regions[0], (start: 9, end: 10)); // '['
      // second region: everything after text until " et suite"
      // Must include the space before title — proof: region contains "Atelocynus"
      final closingRaw = raw.substring(regions[1].start, regions[1].end);
      expect(closingRaw, contains('"Atelocynus"'));
      expect(closingRaw, contains(')'));
      // The closing region should end before " et suite"
      expect(raw.substring(regions[1].end), startsWith(' et suite'));
    });

    test('mapping and expansion are correct for link with title in paragraph', () {
      final visual = 'du texte Atelocynus et suite';
      final raw = 'du texte [Atelocynus](https://fr.wikipedia.org/wiki/Atelocynus "Atelocynus") et suite';
      // mapVisualToRawOffset maps to the raw boundary (before '[', not inside)
      final rawPosBefore = mapVisualToRawOffset(visual, raw, 9);
      expect(raw[rawPosBefore], '[');
      // adjustCursorAtMarkerBoundary with insideMarkers=true pushes past opening '['
      final adjusted = adjustCursorAtMarkerBoundary(visual, raw, rawPosBefore, insideMarkers: true);
      expect(raw[adjusted], 'A');
      // expand entire 'Atelocynus' from content boundaries
      final openingBracket = raw.indexOf('[');
      final closingParen = raw.lastIndexOf(')');
      // rawStart just after '[' (content boundary), rawEnd just before ']' (content boundary)
      final (start, end) = expandSelectionToMarkers(
        visual, raw,
        openingBracket + 1, // before 'A'
        closingParen,       // after everything
      );
      expect(start, openingBracket);  // includes [
      expect(end, closingParen + 1); // past ), i.e. includes )
      // The expanded text should include the title
      final expandedRaw = raw.substring(start, end);
      expect(expandedRaw, contains('"Atelocynus"'));
    });
  });

  group('image placeholder with AST', () {
    test('standalone image: no marker regions', () {
      final visual = '\uFFFC';
      final raw = '![alt](url.png)';
      expect(markerRegions(visual, raw), isEmpty);
    });

    test('image before text: only gap before image is marker region', () {
      final visual = '\uFFFCmore';
      final raw = '![img](p.png)more';
      final regions = markerRegions(visual, raw);
      // Nothing before image, image is a content span, then "more" is content
      // No markers needed for clean text boundaries
      expect(regions, isEmpty);
    });
  });
}
