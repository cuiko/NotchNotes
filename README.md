# NotchNotes

![NotchNotes preview](docs/assets/readme-hero.png)

NotchNotes is a small native macOS note app that lives at the top edge of your MacBook screen. Move the cursor to the notch area and it unfolds into a dark Markdown notebook for quick tasks, links, screenshots, and tiny reminders.

## What's new in this fork

This fork adds the following on top of the original project:

### Tabs & UI
- **Per-tab accent color** — every note tab gets a persisted random color that also tints the editor caret, text selection, checkboxes, and inline code.
- **Drag to reorder tabs** — drag a tab dot to reorder; the dragged dot follows the cursor while the others make room, and the order is persisted.
- **Delete confirmation** — clearing a note or removing a tab asks for confirmation; toggle it in Settings.
- **Settings polish** — larger fonts, a right-aligned switch, and consistent row heights in the settings popover.

### Markdown rendering
- **Strikethrough** — `~~text~~` renders with a strike line and combines correctly with bold/italic.
- **Italic fix** — italic now renders even with the SF system font (oblique-slant fallback).
- **Inline code** — `` `code` `` uses the tab accent color at body font size with a subtle highlight box.
- **Blockquote callout** — `> ...` renders GitHub-style with a left accent bar and a faint background (continuous across consecutive lines, vertically centered).
- **Horizontal rule** — `---` renders as a thin full-width drawn line instead of a row of dashes; the raw text is revealed only while the caret is on the line.

### Lists & to-dos
- **Nesting alignment** — a nested item's marker/checkbox aligns under the parent item's text.
- **Consistent checkbox spacing** — the gap between the checkbox and its text stays the same whether checked, unchecked, or empty.
- **Reliable checkbox toggle** + a pointing-hand cursor over checkboxes.
- **Smart Backspace** — Backspace on an empty list item outdents it (or removes the marker) instead of leaving a stray indent.
- **Block indentation** — select multiple lines and press Tab / Shift-Tab to indent / outdent them together.

## Download

- [Download the latest release](https://github.com/oil-oil/NotchNotes/releases/latest)
- [Open the homepage](https://oil-oil.github.io/NotchNotes/)

After downloading, unzip the app, move it to Applications, then right-click and choose Open on the first launch.

## Stack

- Swift + AppKit for the floating panels, window levels, screen targeting, and cursor-triggered behavior.
- SwiftUI for the notebook interface.
- UserDefaults for lightweight local note storage.
- MarkdownEngine for live Markdown editing and embedded images.

## Run

```bash
swift run NotchNotes
```

After launch, move the cursor to the top-center notch area. The compact notch container expands into the notebook panel.

## Package

```bash
./Scripts/package-app.sh
open NotchNotes.app
```

## Distribution

The current downloadable ZIP is intended for testing. For public distribution outside the Mac App Store, sign the app with a Developer ID Application certificate and submit it for Apple notarization.
