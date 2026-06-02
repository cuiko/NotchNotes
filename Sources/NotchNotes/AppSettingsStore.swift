import Combine
import Foundation

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
    }
}
