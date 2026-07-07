import 'package:attributed_text/attributed_text.dart';

(int, int) expandSelectionToMarkers(
  String raw,
  int rawStart,
  int rawEnd,
  AttributedSpans formattedSpans,
) {
  int newStart = rawStart;
  int newEnd = rawEnd;

  final spanBoundaries = <int>{};
  for (final marker in formattedSpans.markers) {
    spanBoundaries.add(marker.offset);
  }

  for (final boundary in spanBoundaries) {
    if (newStart == boundary) {
      newStart = boundary - _scanMarkerBackward(raw, boundary);
    }
    if (newEnd == boundary) {
      newEnd = boundary + _scanMarkerForward(raw, boundary);
    }
  }

  return (newStart.clamp(0, raw.length), newEnd.clamp(0, raw.length));
}

int _scanMarkerBackward(String raw, int pos) {
  int len = 0;
  int i = pos - 1;
  while (i >= 0 && _isMarkerChar(raw[i])) {
    len++;
    i--;
  }
  if (len > 2) len = 2;
  return len;
}

int _scanMarkerForward(String raw, int pos) {
  int len = 0;
  int i = pos;
  while (i < raw.length && _isMarkerChar(raw[i])) {
    len++;
    i++;
  }
  if (len > 2) len = 2;
  return len;
}

bool _isMarkerChar(String c) {
  return c == '*' || c == '_' || c == '`' || c == '~';
}
