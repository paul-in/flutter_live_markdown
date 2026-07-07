Stylesheet customStylesheet(Stylesheet base) {
  return base.copyWith(
    inlineTextStyler: (attributions, existingStyle) {
      var style = defaultInlineTextStyler(attributions, existingStyle);
      if (attributions.any((a) => a == codeAttribution)) {
        style = style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey.withValues(alpha: 0.15),
        );
      }
      return style;
    },
  );
}
