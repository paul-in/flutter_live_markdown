# Flutter Live Markdown

A Live Markdown Editor inspired by Obsidian, with a toggle between raw and formatted text at the block level. Flutter Live Markdown was initially built for the long-term learning app [Mycelium](https://github.com/mycel-project/mycelium).

This package is an extension built on top of the [Super Editor](https://github.com/Flutter-Bounty-Hunters/super_editor) package.

I couldn't find a live rendering system for Markdown that allows for editing, similar to what CodeMirror Markdown does. It is built on top of Super Editor because it manages the block logic, allowing multiple styles (headings, blockquotes, bold, images, ...) to cohabit without having to reparse the entire document on each change, while precisely handling cursor position and selection. Thus, super_editor serves as the graphical and interactive engine of this package.

It also uses the [dart_markdown](https://github.com/hanlogy/dart_markdown) package because, for the live block formatted/raw changes, we need to get the precise offset of each element to correctly map the cursor.

AI was used to help build this package, though the design, architecture, and core decisions were made by a human (me).

Contributions/improvements are very welcome!

## API/Config:

LiveMarkdownEditor: 

**deferToPointerUp** - If true (default), when selecting, waits for the click release (pointer up) before switching blocks to raw mode.
**cursorInsideMarkers** - If true (default), places the cursor inside the formatting markers (e.g., `**|text**`) instead of outside (e.g., `|**text**`).

LiveMarkdownController: 

**text** - Gets the raw text of the editor
**selectionStart** - Absolute raw-markdown offset of the selection start
**selectionEnd** - Absolute raw-markdown offset of the selection extent
**canUndo** - Whether undo is available
**canRedo** - Whether redo is available

**undo()** - Undo the last transaction
**redo()** - Redo the last transaction
**getContentBetween(int start, int end)** - Raw markdown text between two absolute offsets
**scrollTo(int globalOffset)** - Scrolls the editor to try to bring the position at [globalOffset] into view
**blur()** - Removes focus from the editor
**clearSelection()** - Clears the current selection (collapses to a single point at the cursor)
**replaceContent(String markdown, {int? cursor})** - Replaces the content with `markdown`
**clearHistory()** - Clears the undo/redo history. (Calls replaceContent with active text)
**setShowKeyboard()** - Controls whether the software keyboard should be shown. (WIP)

**onChange** - Triggered when the markdown text content changes.
**onSelectionChange** - Triggered when the cursor moves or the text selection range changes.
**onFocusChange(bool hasFocus)** - Triggered when the editor gains or loses focus. The hasFocus parameter is true if the editor just gained focus (is now active).
**onHistoryChange** - Triggered when the undo/redo stack is updated (useful for updating the enabled/disabled state of undo/redo buttons in a toolbar).

## Known Bugs/Limitations (or improvements to come!)

- Undo/redo can be quite unstable.
- Nested elements are poorly rendered. That's because super_editor works with a flattened node tree.
- "---", tables and images can also be unstable for now.
