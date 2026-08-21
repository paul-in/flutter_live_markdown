import '../parsing/inline_ast_mapper.dart';

// Fundamental mappers to link raw and visual content. Offset could be marked as position
int mapVisualToRawOffset(String visual, String raw, int visualOffset) {
  return InlineSpanMap.fromRaw(raw).mapVisualToRaw(visualOffset);
}

int mapRawToVisualOffset(String visual, String raw, int rawOffset) {
  return InlineSpanMap.fromRaw(raw).mapRawToVisual(rawOffset);
}

// get regions where it is markers
List<({int start, int end})> markerRegions(String visual, String raw) {
  return InlineSpanMap.fromRaw(raw).markerRegions;
}

// Returns position of the cursor depending on if we want it in the interior or the exterior
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
