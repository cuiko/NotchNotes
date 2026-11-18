# HighlighterSwift (vendored)

Source: [smittytone/HighlighterSwift](https://github.com/smittytone/HighlighterSwift), version 3.0.3, revision `81f2ab8f65eeec0b18e1a03f1dac369a159d0368`.

The upstream package manifest, sources, resources, tests, and license are retained here.

Local change: `Highlighter.init()` first resolves `Highlighter_Highlighter.bundle` from the host application's resources, falling back to `Bundle.module` for normal SwiftPM builds. The native SwiftPM accessor used in earlier releases looks in the `.app` root or the original build directory, so it cannot find resources packaged under `Contents/Resources`. Keeping resources there preserves strict macOS code signing.
