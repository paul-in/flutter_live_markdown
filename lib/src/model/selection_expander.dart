import 'offset_mapper.dart';

// This allows for 

int expandStartEdge(String visual, String raw, int rawStart) {
  if (rawStart <= 0) return rawStart;
  final regions = markerRegions(visual, raw);
  int s = rawStart;
  bool changed = true;
  while (changed) {
    changed = false;
    for (final r in regions) {
      if (r.end == s) {
        s = r.start;
        changed = true;
      }
    }
  }
  return s.clamp(0, raw.length);
}

int expandEndEdge(String visual, String raw, int rawEnd) {
  if (rawEnd >= raw.length) return rawEnd;
  final regions = markerRegions(visual, raw);
  int e = rawEnd;
  bool changed = true;
  while (changed) {
    changed = false;
    for (final r in regions) {
      if (r.start == e) {
        e = r.end;
        changed = true;
      }
    }
  }
  return e.clamp(0, raw.length);
}

(int, int) expandSelectionToMarkers(
  String visual,
  String raw,
  int rawStart,
  int rawEnd,
) {
  if (rawStart == rawEnd) return (rawStart, rawEnd);
  final selMin = rawStart < rawEnd ? rawStart : rawEnd;
  final selMax = rawStart < rawEnd ? rawEnd : rawStart;
  final newMin = expandStartEdge(visual, raw, selMin);
  final newMax = expandEndEdge(visual, raw, selMax);
  if (rawStart <= rawEnd) {
    return (newMin, newMax);
  } else {
    return (newMax, newMin);
  }
}

