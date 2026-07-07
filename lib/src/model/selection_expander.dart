import 'package:attributed_text/attributed_text.dart';

(int, int) expandSelectionToMarkers(
  String raw,
  int rawStart,
  int rawEnd,
  AttributedSpans formattedSpans,
) {
  int newStart = rawStart;
  int newEnd = rawEnd;

  for (final marker in formattedSpans.markers) {
    final boundary = marker.offset;
    final markerLen = _markerLength(marker.attribution);
    if (markerLen == 0) continue;

    // Start boundary: opening markers are at [boundary - markerLen, boundary)
    if (newStart >= boundary - markerLen && newStart <= boundary) {
      newStart = boundary - markerLen;
    }
    // End boundary: closing markers are at [boundary - markerLen, boundary)
    // (span includes the closing marker in raw-text coordinates)
    if (newEnd >= boundary - markerLen && newEnd <= boundary) {
      newEnd = boundary;
    }
  }

  return (newStart.clamp(0, raw.length), newEnd.clamp(0, raw.length));
}

int _markerLength(Attribution attr) {
  if (attr is NamedAttribution) {
    switch (attr.name) {
      case 'bold':
      case 'strikethrough':
        return 2;
      case 'italics':
      case 'code':
        return 1;
    }
  }
  return 0;
}
