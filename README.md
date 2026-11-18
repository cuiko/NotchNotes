# NotchNotes

![NotchNotes preview](docs/assets/readme-hero.png)

NotchNotes is a small native macOS note app that lives at the top edge of your MacBook screen. Move the cursor to the notch area and it unfolds into a dark Markdown notebook for quick tasks, links, screenshots, and tiny reminders.

## What's new in this fork

See [CHANGELOG](CHANGELOG.md).

## Download

- [Download the latest release](https://github.com/cuiko/NotchNotes/releases/latest)
- [Open the homepage](https://cuiko.github.io/NotchNotes/)

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

To package without installing into Applications, use `INSTALL_APP=0 ./Scripts/package-app.sh`.

Verify a packaged build on a macOS desktop:

```bash
swift Scripts/verify-app.swift NotchNotes.app
```

The check launches a separate app process, hovers over its notch panel, verifies
that the notebook expands, and closes that process. For release validation, run
it on an extracted ZIP with the original build directory unavailable so missing
resources cannot be masked by development files.

## Distribution

The current downloadable ZIP is intended for testing. For public distribution outside the Mac App Store, sign the app with a Developer ID Application certificate and submit it for Apple notarization.
