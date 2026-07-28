import Combine
import Foundation
import ServiceManagement

enum TriggerMode: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover:
            return "Hover"
        case .click:
            return "Click"
        }
    }

    var systemImage: String {
        switch self {
        case .hover:
            return "cursorarrow.motionlines"
        case .click:
            return "cursorarrow.click.2"
        }
    }
}

/// A selectable highlight.js theme for fenced code blocks.
struct CodeTheme: Identifiable, Hashable {
    /// highlight.js theme name (the CSS filename without extension).
    let id: String
    /// Display name shown in Settings.
    let name: String
}

@MainActor
final class AppSettingsStore: ObservableObject {
    /// Curated dark themes bundled with HighlighterSwift. All ship in the app's
    /// `Highlighter_Highlighter.bundle`.
    static let codeThemes: [CodeTheme] = [
        CodeTheme(id: "atom-one-dark", name: "One Dark"),
        CodeTheme(id: "github-dark", name: "GitHub Dark"),
        CodeTheme(id: "monokai", name: "Monokai"),
        CodeTheme(id: "dracula", name: "Dracula"),
    ]

    static let defaultCodeTheme = "atom-one-dark"

    /// highlight.js theme applied to fenced code blocks.
    @Published var codeTheme: String {
        didSet {
            guard codeTheme != oldValue else { return }
            UserDefaults.standard.set(codeTheme, forKey: Self.codeThemeKey)
            onCodeThemeChange?(codeTheme)
        }
    }

    /// Fires after the code-block theme changes so the highlighter can switch.
    var onCodeThemeChange: ((String) -> Void)?

    @Published var triggerMode: TriggerMode {
        didSet {
            UserDefaults.standard.set(triggerMode.rawValue, forKey: Self.triggerModeKey)
        }
    }

    @Published var confirmBeforeDelete: Bool {
        didSet {
            UserDefaults.standard.set(confirmBeforeDelete, forKey: Self.confirmBeforeDeleteKey)
        }
    }

    /// Mirrors the macOS login-item registration. Toggling registers or
    /// unregisters the app via SMAppService; the system is the source of truth.
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLoginItem, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                }
            } catch {
                // Couldn't change it — snap the toggle back to the real state.
                isSyncingLoginItem = true
                launchAtLogin = SMAppService.mainApp.status == .enabled
                isSyncingLoginItem = false
            }
        }
    }

    /// When true, the Tab key and list nesting insert `indentSpaceCount` spaces
    /// instead of a tab character.
    @Published var indentUsesSpaces: Bool {
        didSet {
            guard indentUsesSpaces != oldValue else { return }
            UserDefaults.standard.set(indentUsesSpaces, forKey: Self.indentUsesSpacesKey)
            onIndentChange?(oldValue, indentSpaceCount, indentUsesSpaces, indentSpaceCount)
        }
    }

    /// Spaces inserted per indent level when `indentUsesSpaces` is true. Fixed
    /// to the two common conventions: 2 or 4.
    @Published var indentSpaceCount: Int {
        didSet {
            guard indentSpaceCount != oldValue else { return }
            UserDefaults.standard.set(indentSpaceCount, forKey: Self.indentSpaceCountKey)
            // Only the spaces-mode document is affected by a count change.
            if indentUsesSpaces {
                onIndentChange?(true, oldValue, true, indentSpaceCount)
            }
        }
    }

    /// Fires after the indent style changes with
    /// `(oldUseSpaces, oldCount, newUseSpaces, newCount)` so existing document
    /// indentation can be migrated to match.
    var onIndentChange: ((Bool, Int, Bool, Int) -> Void)?

    private var isSyncingLoginItem = false

    /// Re-reads the system login-item state into the toggle without registering
    /// or unregistering — used when reopening Settings so an external change
    /// (e.g. via System Settings) is reflected.
    func refreshLaunchAtLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        guard enabled != launchAtLogin else { return }
        isSyncingLoginItem = true
        launchAtLogin = enabled
        isSyncingLoginItem = false
    }

    private static let triggerModeKey = "notchNotes.triggerMode"
    private static let confirmBeforeDeleteKey = "notchNotes.confirmBeforeDelete"
    private static let indentUsesSpacesKey = "notchNotes.indentUsesSpaces"
    private static let indentSpaceCountKey = "notchNotes.indentSpaceCount"
    static let codeThemeKey = "notchNotes.codeTheme"

    init() {
        let rawMode = UserDefaults.standard.string(forKey: Self.triggerModeKey)
        triggerMode = rawMode.flatMap(TriggerMode.init(rawValue:)) ?? .hover

        if UserDefaults.standard.object(forKey: Self.confirmBeforeDeleteKey) != nil {
            confirmBeforeDelete = UserDefaults.standard.bool(forKey: Self.confirmBeforeDeleteKey)
        } else {
            confirmBeforeDelete = true
        }

        indentUsesSpaces = UserDefaults.standard.bool(forKey: Self.indentUsesSpacesKey)
        let storedCount = UserDefaults.standard.object(forKey: Self.indentSpaceCountKey) as? Int
        indentSpaceCount = (storedCount == 2) ? 2 : 4

        let storedTheme = UserDefaults.standard.string(forKey: Self.codeThemeKey)
        codeTheme = Self.codeThemes.contains(where: { $0.id == storedTheme })
            ? storedTheme!
            : Self.defaultCodeTheme

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
