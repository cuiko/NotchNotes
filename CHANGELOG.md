# Changelog

All notable changes this fork makes on top of the original NotchNotes are
documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This fork builds on [oil-oil/NotchNotes](https://github.com/oil-oil/NotchNotes).
Its [releases](https://github.com/oil-oil/NotchNotes/releases) (v0.1.x) provide
the baseline — the notch panel, live Markdown editing, image paste, local note
persistence, and the settings popover — which the versions below extend.

## v0.2.6

### Added
- **Collapsible lists** — a list item with a nested subtree shows a small
  disclosure chevron (on the caret's line, and always while collapsed); click
  it to fold the item and hide its children. Folding only changes the display
  and never edits the note text.
- **Import & export** — *Settings → Export* saves the current profile's notes
  and the images they reference as a portable zip (`notes/*.md` +
  `images/*.png`); *Import* reads such a zip into a brand-new profile without
  touching existing ones.

### Changed
- **Settings redesigned as a two-column panel** — the popover matches the
  drawer's width, sizes its height to its content, and clicking the gear again
  closes it.

### Fixed
- **Drawer reveal animation** — opening and closing the drawer scales from the
  notch again instead of fading.

## v0.2.5

### Added
- **Resizable drawer** — drag the drawer's left/right edges (or bottom corners)
  to change its width symmetrically about the center, and the bottom edge to
  make it taller; a resize cursor shows on the edges. The chosen size is
  remembered across sessions.
- **Profiles** — isolate tabs into independent profiles. Manage them under
  *Settings → Profiles* (add / rename / switch / delete, with a delete
  confirmation); when more than one exists, a profile switcher appears in the
  drawer's top bar. Existing notes migrate into a "Default" profile, and images
  stay shared across all profiles.

## v0.2.4

### Added
- **Code block copy button** — hovering a fenced code block shows a copy
  button at its top-right that puts the block's code on the pasteboard.
- **Code block syntax highlighting** — fenced code blocks are highlighted via
  HighlighterSwift (highlight.js). A *Code Block → Theme* picker in Settings
  chooses between One Dark, GitHub Dark, Monokai, and Dracula.
- **Image edit & zoom buttons** — hovering a rendered image shows an *edit*
  button that reveals its `![[…]]` source and a *zoom* button that opens a
  full-screen, centered preview over a dim backdrop (click or Esc to close).
- **Indentation setting** — choose Tab or Spaces (2 or 4) under *Settings →
  Indentation*. Switching converts existing document indentation to match.
- **Context-aware Select All** — `⌘A` inside a code block selects the block's
  code, inside a blockquote selects the quote, and inside a list selects the
  current item; pressing it again selects the whole document.

### Changed
- **Unordered lists render as bullets (•)** — the toolbar, typing, and existing
  `-` lists all show dots; typing `- ` no longer adds a leading indent.
- **Oversized inline images scale to fit** the drawer; view them at full size
  via the zoom button.

### Fixed
- **Right-click Heading and Lists** now apply to every selected line instead of
  only the first.
- **Code block selection** highlight is aligned per line while drag-selecting.
- **Tall image embeds** no longer render mispositioned far below their line.
- **Image source flash** — the `![[…]]` source no longer flashes when switching
  tabs.
- **Bullet revert** — deleting an auto-converted bullet's content turns `•`
  back into `-`.

## v0.2.3

### Fixed
- **Multi-line inline styling** — applying bold, italic, strikethrough, or
  inline code to a selection spanning several lines now wraps each line
  individually instead of only the block's head and tail (which produced markup
  that spanned line breaks and didn't render). Blank lines are skipped. Applies
  to both the toolbar and the right-click *Format* menu.
- **Multi-line headings and lists** — the right-click *Heading* and *Lists*
  actions now prefix every selected line instead of collapsing the selection
  into just the first line. Numbered lists renumber each line sequentially.

## v0.2.2

### Added
- **Launch at login** — a Settings toggle (under *General*) registers the app
  as a macOS login item.
- **Quit** — a Quit button in Settings, so the menu-bar-only app can be quit
  without finding its status-bar menu.

## v0.2.1

### Added
- **Code block box** — fenced code blocks render on a visibly lighter
  background, separated from neighboring content, with the fence's language
  (```` ```js ````) shown as a label at the top-left.
- **Tab context menu** — right-click a tab for **Delete** and **Clear
  Completed** (removes finished to-dos, keeping a done parent that still has an
  open child).
- **Scrollable tab strip** — with many tabs the strip scrolls horizontally
  instead of overflowing.
- **Tab hover titles** — hovering a tab dot shows that tab's first line of text.
- **Pin on top** — a pin button keeps the drawer open and ignores the hover-out
  auto-collapse.
- **Reclaim images on delete** — deleting a tab removes the image assets it
  referenced, unless another tab still uses them.
- **Hover-to-delete image embeds** — hovering a rendered image shows a trash
  button that removes the embed (the stored asset is kept).
- **Paste URL over selection** — pasting a bare URL while text is selected wraps
  it as a Markdown link, `[selection](url)`.
- **Smart line start** — `Cmd-Left` / `Home` jumps to the content start after a
  list, to-do, or blockquote marker; a second press goes to the true line start.
  `Shift` extends the selection to the same target.

### Changed
- **Delete confirmation** renders as an in-panel card instead of a separate
  alert window, so it no longer collapses the panel out from under the dialog.
- **Confirm-delete setting** toggles by clicking its label, with a custom switch.
- Reduced blockquote callout padding and tightened the toolbar icon spacing.

### Removed
- The minus (remove-tab) toolbar button, replaced by the tab context menu.

### Fixed
- **Blockquote vertical centering** — quote text is centered in the callout box
  and stays consistent while typing, after a line break, and on the first line.
- **Italic rendering** — italic now slants even with the SF system font.
- Toolbar commands scroll the caret back into view in a long note.
- Selection stays visible over code blocks and checkboxes.
- An image embed's preview sits below its source even when the source wraps.

## v0.2.0

### Added
- **Per-tab accent color** — every note tab gets a persisted random color that
  also tints the editor caret, text selection, checkboxes, and inline code.
- **Drag to reorder tabs** — drag a tab dot to reorder; the order is persisted.
- **Delete confirmation** — clearing a note or removing a tab asks for
  confirmation; toggle it in Settings.
- **Strikethrough** — `~~text~~` renders with a strike line and combines
  correctly with bold/italic.
- **Inline code** — `` `code` `` uses the tab accent color at body font size
  with a subtle highlight box.
- **Blockquote callout** — `> ...` renders GitHub-style with a left accent bar
  and a faint background, continuous across consecutive lines.
- **Horizontal rule** — `---` renders as a thin full-width drawn line instead of
  a row of dashes; the raw text is revealed only while the caret is on the line.
- **Block indentation** — select multiple lines and press `Tab` / `Shift-Tab` to
  indent / outdent them together.
- **Smart Backspace** — Backspace on an empty list item outdents it (or removes
  the marker) instead of leaving a stray indent.

### Changed
- **Settings popover polish** — larger fonts, a right-aligned switch, and
  consistent row heights.
- **Nested list alignment** — a nested item's marker/checkbox aligns under the
  parent item's text.
- **Consistent checkbox spacing** — the gap between the checkbox and its text
  stays the same whether checked, unchecked, or empty.

### Fixed
- **Reliable checkbox toggle**, with a pointing-hand cursor over checkboxes.

## v0.1.1

From the upstream project —
[release notes](https://github.com/oil-oil/NotchNotes/releases/tag/v0.1.1).

### Changed
- Update the bundle identifier to `io.github.oiloil.NotchNotes`.

### Fixed
- Re-sign the full `.app` bundle after writing `Info.plist` and resources,
  fixing a structurally invalid signature on the downloaded app; the packaged
  app is now verified with `codesign` during packaging.

## v0.1.0

Initial public build, from the upstream project —
[release notes](https://github.com/oil-oil/NotchNotes/releases/tag/v0.1.0).

### Added
- Native macOS notch note panel built with SwiftUI and AppKit.
- Hover or click trigger modes.
- Live Markdown editing with common formatting shortcuts.
- Image paste support and local note persistence.
- Settings popover with refined dismissal behavior.
