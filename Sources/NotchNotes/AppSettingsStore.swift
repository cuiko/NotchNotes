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

@MainActor
final class AppSettingsStore: ObservableObject {
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

    init() {
        let rawMode = UserDefaults.standard.string(forKey: Self.triggerModeKey)
        triggerMode = rawMode.flatMap(TriggerMode.init(rawValue:)) ?? .hover

        if UserDefaults.standard.object(forKey: Self.confirmBeforeDeleteKey) != nil {
            confirmBeforeDelete = UserDefaults.standard.bool(forKey: Self.confirmBeforeDeleteKey)
        } else {
            confirmBeforeDelete = true
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
