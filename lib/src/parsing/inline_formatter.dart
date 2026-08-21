import 'package:super_editor/super_editor.dart';

// shift the styling from the visual that is given by parseInlineMarkdown to take in account the markers and display them.
AttributedText applyInlineFormatting(String raw) {
  if (raw.isEmpty) return AttributedText();

  final clean = parseInlineMarkdown(raw);
  final cleanText = clean.toPlainText(includePlaceholders: false);

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

  return AttributedText(raw, AttributedSpans(attributions: shifted));
}
