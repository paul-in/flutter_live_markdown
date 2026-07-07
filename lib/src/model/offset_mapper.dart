import '../parsing/inline_ast_mapper.dart';

int mapVisualToRawOffset(String visual, String raw, int visualOffset) {
  return InlineSpanMap.fromRaw(raw).mapVisualToRaw(visualOffset);
}

List<({int start, int end})> markerRegions(String visual, String raw) {
  return InlineSpanMap.fromRaw(raw).markerRegions;
}

int adjustCursorAtMarkerBoundary(
  String visual,
  String raw,
  int rawOffset, {
  bool insideMarkers = true,
}) {
  final regions = markerRegions(visual, raw);
  for (int i = 0; i < regions.length; i++) {
    if (regions[i].start == rawOffset) {
      final isOpening = i.isEven;
      if (insideMarkers && isOpening) {
        return regions[i].end;
      }
      if (!insideMarkers && !isOpening) {
        return regions[i].end;
      }
      break;
    }
  }
  return rawOffset;
}

int mapRawToVisualOffset(String visual, String raw, int rawOffset) {
  return InlineSpanMap.fromRaw(raw).mapRawToVisual(rawOffset);
}
