# Changelog
## 0.2.3-dev.1 - 2026-08-24
- Fix extraction generating double line breaks between consecutive raw lists
- Let the reconciler handle copy/pasting to fix spacing and duplication bugs
- Fix cursor jumping to next block after a soft-break
- Prevent IME crash on double soft-break
- Fix soft-breaks visually collapsing when block is not focused
- Update example app to match new selection typing

## 0.2.2-dev.1 - 2026-08-22
- Do not call onChange() hook on replaceContent()
- Nullify selection on focus loss
- Return empty MarkdownBlock when content is empty instead of an empty array

## 0.2.1-dev.1 - 2026-08-22
- Add hasSelection getter to API

## 0.2.0-dev.1 - 2026-08-22
- Add setReadOnly + readOnly getter param to API
- Add requestFocus method to API
- Remove unused setShowKeyboard method

## 0.1.0-dev.2 - 2026-08-22
### Fixed
- When using getContentBetween extracted text was outdated.
- Use GlobalKey on Editor to avoid desync

## 0.1.0-dev.1 - 2026-08-21
- Initial release. Live Markdown editor with raw/formatted block toggling.
