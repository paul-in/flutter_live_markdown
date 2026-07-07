import 'package:dart_markdown/dart_markdown.dart' as md;

class InlineSpanMap {
  final List<({int rawStart, int rawEnd, int visualStart, int visualEnd})> spans;
  final List<({int start, int end})> regions;

  InlineSpanMap._({
    required this.spans,
    required this.regions,
  });

  factory InlineSpanMap.fromRaw(String raw) {
    if (raw.isEmpty) {
      return InlineSpanMap._(spans: [], regions: []);
    }

    final parser = md.Markdown();
    final nodes = parser.parse(raw);

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
        if (node.type == 'image') {
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

    for (final node in nodes) {
      walk(node);
    }

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
    for (final span in spans) {
      if (visualOffset >= span.visualStart && visualOffset < span.visualEnd) {
        return span.rawStart + (visualOffset - span.visualStart);
      }
    }
    if (spans.isEmpty) return visualOffset;
    if (visualOffset <= 0) return spans.first.rawStart;
    // In a gap between spans: map to next span's rawStart
    for (final span in spans) {
      if (visualOffset < span.visualStart) {
        return span.rawStart;
      }
    }
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
