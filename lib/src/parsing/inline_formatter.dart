import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

void _log(String msg) => debugPrint('[LIVE_MD] $msg');

AttributedText applyInlineFormatting(String raw) {
  if (raw.isEmpty) return AttributedText();

  final clean = parseInlineMarkdown(raw);
  final cleanText = clean.toPlainText(includePlaceholders: false);
  _log('applyInlineFormatting: raw="${raw.substring(0, raw.length.clamp(0, 40))}" clean="$cleanText" spans=${clean.spans.markers.length}');

  final shifts = List.filled(cleanText.length, 0);
  int p = 0;
  int markersSoFar = 0;
  for (int r = 0; r < raw.length; r++) {
    if (p < cleanText.length && raw[r] == cleanText[p]) {
      shifts[p] = markersSoFar;
      p++;
    } else {
      markersSoFar++;
    }
  }

  final shifted = clean.spans.markers.map((m) {
    final shift = m.offset < shifts.length ? shifts[m.offset] : markersSoFar;
    return m.copyWith(offset: m.offset + shift);
  }).toList();

  _log('applyInlineFormatting: shifted ${shifted.length} markers');
  return AttributedText(raw, AttributedSpans(attributions: shifted));
}
