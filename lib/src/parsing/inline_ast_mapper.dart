import 'package:dart_markdown/dart_markdown.dart' as md;


// Get marker and regions positions inside a raw text
class InlineSpanMap {
  final List<({int start, int end})> regions; // area where it is markers
  final List<({int rawStart, int rawEnd, int visualStart, int visualEnd})> spans; // raw content

  InlineSpanMap._({
    required this.spans,
    required this.regions,
  });

  factory InlineSpanMap.fromRaw(String raw) {
    if (raw.isEmpty) {
      return InlineSpanMap._(spans: [], regions: []);
    }

    // Decompose into markdown ast
    final parser = md.Markdown();
    final nodes = parser.parse(raw);

    // init
    final spans = <({int rawStart, int rawEnd, int visualStart, int visualEnd})>[];
    int visualOffset = 0;

    void walk(md.Node node) {
      if (node is md.Text) {
        final textLen = node.text.length;
        spans.add((
          rawStart: node.start.offset,
          rawEnd: node.end.offset,
          visualStart: visualOffset,
          visualEnd: visualOffset + textLen,
        ));
        visualOffset += textLen;
      } else if (node is md.Element) {
        if (node.type == 'image') { // handle LATEX similarly ?
          spans.add((
            rawStart: node.start.offset,
            rawEnd: node.end.offset,
            visualStart: visualOffset,
            visualEnd: visualOffset + 1,
          ));
          visualOffset += 1;
        } else {
          for (final child in node.children) {
            walk(child);
          }
        }
      }
    }

    // get index of all spans
    for (final node in nodes) {
      walk(node);
    }

    // infer markers region positions
    final regions = <({int start, int end})>[];
    if (spans.isNotEmpty) {
      if (spans.first.rawStart > 0) {
        regions.add((start: 0, end: spans.first.rawStart));
      }
      for (int i = 1; i < spans.length; i++) {
        final gapStart = spans[i - 1].rawEnd;
        final gapEnd = spans[i].rawStart;
        if (gapEnd > gapStart) {
          regions.add((start: gapStart, end: gapEnd));
        }
      }
      if (raw.length > spans.last.rawEnd) {
        regions.add((start: spans.last.rawEnd, end: raw.length));
      }
    } else if (raw.isNotEmpty) {
      regions.add((start: 0, end: raw.length));
    }

    return InlineSpanMap._(spans: spans, regions: regions);
  }

  List<({int start, int end})> get markerRegions => regions;

  int mapVisualToRaw(int visualOffset) {
    // Check if visualOffset is strictly INSIDE a content span.
    // A visual offset at a span boundary (equals visualStart) is treated
    // as a gap position and handled below, so the adjuster can decide
    // which side of the marker gap the cursor should land.
    for (final span in spans) {
      if (visualOffset > span.visualStart && visualOffset < span.visualEnd) {
        return span.rawStart + (visualOffset - span.visualStart);
      }
    }
    if (spans.isEmpty) return visualOffset;
    // Before first span → map to rawStart (before opening markers)
    if (visualOffset <= spans.first.visualStart) return spans.first.rawStart;
    // Between spans → map to rawEnd of preceding span (before marker gap)
    for (int i = 1; i < spans.length; i++) {
      if (visualOffset <= spans[i].visualStart) {
        return spans[i - 1].rawEnd;
      }
    }
    // After last span → map to rawEnd (after content)
    return spans.last.rawEnd;
  }

  int mapRawToVisual(int rawOffset) {
    for (final span in spans) {
      if (rawOffset >= span.rawStart && rawOffset < span.rawEnd) {
        return span.visualStart + (rawOffset - span.rawStart);
      }
    }
    if (spans.isEmpty) return rawOffset;
    if (rawOffset <= spans.first.rawStart) return 0;
    // In a gap between spans: map to previous span's visualEnd
    for (int i = spans.length - 1; i >= 0; i--) {
      if (rawOffset >= spans[i].rawEnd) {
        return spans[i].visualEnd;
      }
    }
    return spans.last.visualEnd;
  }
}
