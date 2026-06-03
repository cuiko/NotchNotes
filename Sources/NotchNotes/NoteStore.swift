import AppKit
import Combine
import Foundation
import SwiftUI

private let tabColorPalette: [String] = [
    "#FF6B6B", "#FF9F43", "#FECA57", "#48DBFB",
    "#1DD1A1", "#54A0FF", "#A29BFE", "#FD79A8",
    "#E17055", "#00CEC9",
]

private func randomTabColor() -> String {
    tabColorPalette.randomElement() ?? "#FF6B6B"
}

struct NoteTab: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
    var selectionLocation: Int?
    var selectionLength: Int?
    var colorHex: String

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        selectionLocation = 0
        selectionLength = 0
        colorHex = randomTabColor()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        selectionLocation = try container.decodeIfPresent(Int.self, forKey: .selectionLocation)
        selectionLength = try container.decodeIfPresent(Int.self, forKey: .selectionLength)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
            ?? randomTabColor()
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var tabs: [NoteTab]
    @Published private(set) var activeTabID: UUID

    /// Called after a tab is removed with the text of every remaining tab, so
    /// image assets the deleted note referenced can be garbage-collected when
    /// no other note still uses them.
    var imagePruner: (([String]) -> Void)?

    private static let legacyTextKey = "notchNotes.text"
    private static let tabsKey = "notchNotes.tabs.v1"
    private static let activeTabIDKey = "notchNotes.activeTabID"

    init() {
        let storedTabs = Self.loadStoredTabs()
        let initialTabs: [NoteTab]

        if storedTabs.isEmpty {
            let legacyText = UserDefaults.standard.string(forKey: Self.legacyTextKey) ?? ""
            initialTabs = [NoteTab(text: legacyText)]
        } else {
            initialTabs = storedTabs
        }

        tabs = initialTabs

        let activeIDString = UserDefaults.standard.string(forKey: Self.activeTabIDKey)
        let storedActiveID = activeIDString.flatMap(UUID.init(uuidString:))
        activeTabID = storedActiveID.flatMap { activeID in
            initialTabs.contains(where: { $0.id == activeID }) ? activeID : nil
        } ?? initialTabs[0].id

        save()
    }

    var text: String {
        tabs[activeIndex].text
    }

    func updateText(_ nextText: String) {
        tabs[activeIndex].text = nextText
        clampSelection(for: tabs[activeIndex].id)
        save()
    }

    func clear() {
        updateText("")
        updateSelection(for: activeTabID, range: NSRange(location: 0, length: 0))
    }

    func addTab() {
        let tab = NoteTab()
        tabs.append(tab)
        activeTabID = tab.id
        save()
    }

    func removeActiveTab() {
        removeTab(activeTabID)
    }

    func cleanFinishedTodos(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = Self.removingFinishedTodos(from: tabs[index].text)
        guard cleaned != tabs[index].text else { return }
        tabs[index].text = cleaned
        clampSelection(for: id)
        save()
    }

    func removeTab(_ id: UUID) {
        guard tabs.count > 1, let removedIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = tabs[removedIndex].id == activeTabID
        tabs.remove(at: removedIndex)
        if wasActive {
            let nextIndex = min(removedIndex, tabs.count - 1)
            activeTabID = tabs[nextIndex].id
        }
        save()
        imagePruner?(tabs.map { $0.text })
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        save()
    }

    func moveTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func updateSelection(for id: UUID, range: NSRange) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
        save()
    }

    func selectionRange(for id: UUID) -> NSRange {
        guard let tab = tabs.first(where: { $0.id == id }) else {
            return NSRange(location: 0, length: 0)
        }

        return clampedRange(
            NSRange(location: tab.selectionLocation ?? 0, length: tab.selectionLength ?? 0),
            text: tab.text
        )
    }

    private var activeIndex: Int {
        tabs.firstIndex { $0.id == activeTabID } ?? 0
    }

    private func clampSelection(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let range = NSRange(location: tabs[index].selectionLocation ?? 0, length: tabs[index].selectionLength ?? 0)
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
    }

    private func clampedRange(_ range: NSRange, text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: Self.tabsKey)
        }
        UserDefaults.standard.set(activeTabID.uuidString, forKey: Self.activeTabIDKey)
        UserDefaults.standard.set(text, forKey: Self.legacyTextKey)
    }

    private static let checkboxLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+•]|\d+\.)[ \t]+\[([ xX])\]"#
    )

    /// Removes checked todo items. A checked item is dropped together with its
    /// whole sub-tree, but only when that sub-tree contains no still-unchecked
    /// todo — a completed parent that still has an open child is kept so the
    /// child isn't orphaned.
    static func removingFinishedTodos(from text: String) -> String {
        let lines = (text as NSString).components(separatedBy: "\n")

        struct LineInfo { let indent: Int; let isTodo: Bool; let isChecked: Bool }
        func info(for line: String) -> LineInfo {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = checkboxLineRegex.firstMatch(in: line, range: range) {
                let mark = ns.substring(with: match.range(at: 3))
                return LineInfo(indent: match.range(at: 1).length, isTodo: true,
                                isChecked: mark.caseInsensitiveCompare("x") == .orderedSame)
            }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            return LineInfo(indent: indent, isTodo: false, isChecked: false)
        }
        let infos = lines.map(info)

        // Sub-tree of `i`: following lines more indented than it, with any
        // blank lines folded in so they leave with the item they trail.
        func subtreeEnd(of i: Int) -> Int {
            var j = i + 1
            while j < lines.count {
                if lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1
                    continue
                }
                if infos[j].indent > infos[i].indent { j += 1 } else { break }
            }
            return j
        }

        var result: [String] = []
        var i = 0
        while i < lines.count {
            let line = infos[i]
            if line.isTodo, line.isChecked {
                let end = subtreeEnd(of: i)
                let hasOpenDescendant = (i + 1 ..< end).contains { infos[$0].isTodo && !infos[$0].isChecked }
                if !hasOpenDescendant {
                    i = end
                    continue
                }
            }
            result.append(lines[i])
            i += 1
        }
        return result.joined(separator: "\n")
    }

    private static func loadStoredTabs() -> [NoteTab] {
        guard let data = UserDefaults.standard.data(forKey: tabsKey),
              let tabs = try? JSONDecoder().decode([NoteTab].self, from: data) else {
            return []
        }

        return tabs.isEmpty ? [] : tabs
    }
}
