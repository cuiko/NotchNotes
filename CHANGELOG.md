# Changelog

All notable changes this fork makes on top of the original NotchNotes are
documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [v0.3.0] - 2026-06-03

### Added
- **Tab context menu** — right-click a tab to delete it. This replaces the old
  minus button and leaves room to grow per-tab actions later.
- **Tab hover titles** — hovering a tab dot shows that tab's first line of text.
- **In-panel delete confirmation** — clearing a note or deleting a tab now
  confirms with a card rendered inside the notch drawer instead of a separate
  alert window, so moving the pointer to the buttons no longer collapses the
  panel out from under the dialog.
- **Smart line start** — `Cmd-Left` / `Home` jumps to the content start after a
  list, to-do, or blockquote marker; a second press goes to the true line
  start. `Shift` extends the selection to the same target.

### Fixed
- **Blockquote vertical centering** — quote text is centered in the callout box,
  and the box height stays consistent while typing, after a line break, and when
  the quote is the first line of the document.
- **Italic rendering** — italic now slants even with the SF system font, via an
  oblique-slant font fallback.

## [v0.2.0] - 2026-06-02

### Tabs & UI
- **Per-tab accent color** — every note tab gets a persisted random color that
  also tints the editor caret, text selection, checkboxes, and inline code.
- **Drag to reorder tabs** — drag a tab dot to reorder; the dragged dot follows
  the cursor while the others make room, and the order is persisted.
- **Delete confirmation** — clearing a note or removing a tab asks for
  confirmation; toggle it in Settings.
- **Settings polish** — larger fonts, a right-aligned switch, and consistent row
  heights in the settings popover.

### Markdown rendering
- **Strikethrough** — `~~text~~` renders with a strike line and combines
  correctly with bold/italic.
- **Inline code** — `` `code` `` uses the tab accent color at body font size
  with a subtle highlight box.
- **Blockquote callout** — `> ...` renders GitHub-style with a left accent bar
  and a faint background, continuous across consecutive lines.
- **Horizontal rule** — `---` renders as a thin full-width drawn line instead of
  a row of dashes; the raw text is revealed only while the caret is on the line.

### Lists & to-dos
- **Nesting alignment** — a nested item's marker/checkbox aligns under the parent
  item's text.
- **Consistent checkbox spacing** — the gap between the checkbox and its text
  stays the same whether checked, unchecked, or empty.
- **Reliable checkbox toggle** with a pointing-hand cursor over checkboxes.
- **Smart Backspace** — Backspace on an empty list item outdents it (or removes
  the marker) instead of leaving a stray indent.
- **Block indentation** — select multiple lines and press `Tab` / `Shift-Tab` to
  indent / outdent them together.
