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
    /// Character offsets of list items collapsed in this tab, so folds survive
    /// tab switches and relaunches.
    var collapsedListOffsets: [Int]?

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        selectionLocation = 0
        selectionLength = 0
        colorHex = randomTabColor()
        collapsedListOffsets = nil
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
        collapsedListOffsets = try container.decodeIfPresent([Int].self, forKey: .collapsedListOffsets)
    }
}

/// An isolated set of tabs. Switching the active profile swaps the whole tab
/// set; images are shared across all profiles.
struct NoteProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var tabs: [NoteTab]
    var activeTabID: UUID

    init(id: UUID = UUID(), name: String, tabs: [NoteTab], activeTabID: UUID) {
        self.id = id
        self.name = name
        self.tabs = tabs.isEmpty ? [NoteTab()] : tabs
        self.activeTabID = self.tabs.contains(where: { $0.id == activeTabID }) ? activeTabID : self.tabs[0].id
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
    @Published private(set) var profiles: [NoteProfile]
    @Published private(set) var currentProfileID: UUID

    /// Called after a tab or profile is removed with the text of every remaining
    /// tab across all profiles, so image assets are garbage-collected only when
    /// no note anywhere still uses them.
    var imagePruner: (([String]) -> Void)?

    private static let legacyTextKey = "notchNotes.text"
    private static let tabsKey = "notchNotes.tabs.v1"
    private static let activeTabIDKey = "notchNotes.activeTabID"
    private static let profilesKey = "notchNotes.profiles.v1"
    private static let activeProfileIDKey = "notchNotes.activeProfileID"
    private static let defaultProfileName = "Default"

    init() {
        let loaded = Self.loadProfiles()
        profiles = loaded.profiles
        currentProfileID = loaded.activeID
        save()
    }

    // MARK: - Current profile access

    private var currentProfileIndex: Int {
        profiles.firstIndex { $0.id == currentProfileID } ?? 0
    }

    /// Tabs of the active profile.
    var tabs: [NoteTab] {
        profiles[currentProfileIndex].tabs
    }

    var activeTabID: UUID {
        profiles[currentProfileIndex].activeTabID
    }

    var text: String {
        let profile = profiles[currentProfileIndex]
        return profile.tabs[activeIndex(in: profile)].text
    }

    private func activeIndex(in profile: NoteProfile) -> Int {
        profile.tabs.firstIndex { $0.id == profile.activeTabID } ?? 0
    }

    // MARK: - Profiles

    /// Creates a new empty profile and switches to it.
    func addProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tab = NoteTab()
        let profile = NoteProfile(
            name: trimmed.isEmpty ? "Profile \(profiles.count + 1)" : trimmed,
            tabs: [tab],
            activeTabID: tab.id
        )
        profiles.append(profile)
        currentProfileID = profile.id
        save()
    }

    func renameProfile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        save()
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        if currentProfileID == id {
            currentProfileID = profiles[min(index, profiles.count - 1)].id
        }
        save()
        imagePruner?(allTabTexts())
    }

    func selectProfile(_ id: UUID) {
        guard id != currentProfileID, profiles.contains(where: { $0.id == id }) else { return }
        currentProfileID = id
        save()
    }

    var currentProfileName: String {
        profiles[currentProfileIndex].name
    }

    /// Creates a NEW profile from imported note texts and switches to it. Never
    /// modifies or overwrites any existing profile.
    @discardableResult
    func importProfile(name: String, tabTexts: [String]) -> UUID {
        let tabs: [NoteTab] = tabTexts.isEmpty
            ? [NoteTab()]
            : tabTexts.map { NoteTab(text: Self.normalizingBulletMarkers(in: $0)) }
        let profile = NoteProfile(
            name: uniqueProfileName(from: name),
            tabs: tabs,
            activeTabID: tabs[0].id
        )
        profiles.append(profile)
        currentProfileID = profile.id
        save()
        return profile.id
    }

    private func uniqueProfileName(from name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = Set(profiles.map { $0.name })
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func allTabTexts() -> [String] {
        profiles.flatMap { $0.tabs.map { $0.text } }
    }

    // MARK: - List fold state (per tab, keyed by the tab's UUID string)

    func collapsedListOffsets(forTabID idString: String) -> Set<Int> {
        guard let id = UUID(uuidString: idString) else { return [] }
        for profile in profiles {
            if let tab = profile.tabs.first(where: { $0.id == id }) {
                return Set(tab.collapsedListOffsets ?? [])
            }
        }
        return []
    }

    func setCollapsedListOffsets(_ offsets: Set<Int>, forTabID idString: String) {
        guard let id = UUID(uuidString: idString) else { return }
        let ci = currentProfileIndex
        guard let index = profiles[ci].tabs.firstIndex(where: { $0.id == id }) else { return }
        let stored = offsets.isEmpty ? nil : offsets.sorted()
        guard profiles[ci].tabs[index].collapsedListOffsets != stored else { return }
        profiles[ci].tabs[index].collapsedListOffsets = stored
        save()
    }

    // MARK: - Tabs (operate on the current profile)

    func updateText(_ nextText: String) {
        // Note: bullet-marker normalization runs only on load, never here —
        // rewriting text mid-edit resets the caret to the document end.
        let ci = currentProfileIndex
        let ai = activeIndex(in: profiles[ci])
        profiles[ci].tabs[ai].text = nextText
        clampSelection(for: profiles[ci].tabs[ai].id)
        save()
    }

    /// Rewrites leading `-`/`*`/`+` bullet markers to `•` so unordered lists
    /// render as dots regardless of how they were entered (typed, pasted,
    /// toolbar). The replacement is one character for one, so caret offsets are
    /// preserved. Lines inside fenced code blocks are left untouched.
    static func normalizingBulletMarkers(in text: String) -> String {
        guard text.contains("-") else { return text }

        var inFence = false
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                return line
            }
            guard !inFence else { return line }

            var chars = Array(line)
            var i = 0
            while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
            guard i < chars.count, chars[i] == "-" else { return line }
            // Must be a single `-` followed by whitespace (a real bullet, not a
            // horizontal rule like `---`).
            guard i + 1 < chars.count, chars[i + 1] == " " || chars[i + 1] == "\t" else { return line }

            chars[i] = "•"
            changed = true
            return String(chars)
        }
        return changed ? lines.joined(separator: "\n") : text
    }

    func clear() {
        updateText("")
        updateSelection(for: activeTabID, range: NSRange(location: 0, length: 0))
    }

    func addTab() {
        let tab = NoteTab()
        let ci = currentProfileIndex
        profiles[ci].tabs.append(tab)
        profiles[ci].activeTabID = tab.id
        save()
    }

    func removeActiveTab() {
        removeTab(activeTabID)
    }

    /// Rewrites the leading indentation of every line of every tab across all
    /// profiles to match a new indent style — used when the Settings indent
    /// option changes so old notes stop mixing tabs and spaces.
    func reindentAllTabs(fromUseSpaces: Bool, fromCount: Int, toUseSpaces: Bool, toCount: Int) {
        var changed = false
        for pIndex in profiles.indices {
            for tIndex in profiles[pIndex].tabs.indices {
                let converted = Self.reindenting(
                    profiles[pIndex].tabs[tIndex].text,
                    fromUseSpaces: fromUseSpaces, fromCount: fromCount,
                    toUseSpaces: toUseSpaces, toCount: toCount
                )
                guard converted != profiles[pIndex].tabs[tIndex].text else { continue }
                profiles[pIndex].tabs[tIndex].text = converted
                changed = true
            }
        }
        if changed {
            clampSelection(for: activeTabID)
            save()
        }
    }

    /// Converts each line's leading whitespace from one indent style to another.
    ///
    /// The whole leading run is scored as a fractional indent level — each tab is
    /// one level and each space is `1 / oldWidth` of a level — then rounded to
    /// the nearest whole level and re-emitted with the new unit. Rounding to a
    /// whole level (rather than keeping leftover spaces) keeps indentation tidy
    /// and makes the two directions symmetric, so tab↔spaces round-trips cleanly.
    /// It also counts every tab and space regardless of order, so a mixed
    /// "spaces then tab" run never drops characters.
    static func reindenting(
        _ text: String,
        fromUseSpaces: Bool, fromCount: Int,
        toUseSpaces: Bool, toCount: Int
    ) -> String {
        let oldWidth = Double(max(1, fromCount))
        let newUnit = toUseSpaces ? String(repeating: " ", count: max(1, toCount)) : "\t"

        let lines = text.components(separatedBy: "\n")
        let converted = lines.map { line -> String in
            let leadingCount = line.prefix { $0 == " " || $0 == "\t" }.count
            guard leadingCount > 0 else { return line }
            let whitespace = line.prefix(leadingCount)
            let rest = String(line.dropFirst(leadingCount))

            let tabs = whitespace.filter { $0 == "\t" }.count
            let spaces = whitespace.filter { $0 == " " }.count
            let levelValue = Double(tabs) + Double(spaces) / oldWidth
            let levels = Int(levelValue.rounded())

            return String(repeating: newUnit, count: levels) + rest
        }
        return converted.joined(separator: "\n")
    }

    func cleanFinishedTodos(for id: UUID) {
        let ci = currentProfileIndex
        guard let index = profiles[ci].tabs.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = Self.removingFinishedTodos(from: profiles[ci].tabs[index].text)
        guard cleaned != profiles[ci].tabs[index].text else { return }
        profiles[ci].tabs[index].text = cleaned
        clampSelection(for: id)
        save()
    }

    func removeTab(_ id: UUID) {
        let ci = currentProfileIndex
        guard profiles[ci].tabs.count > 1,
              let removedIndex = profiles[ci].tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = profiles[ci].tabs[removedIndex].id == profiles[ci].activeTabID
        profiles[ci].tabs.remove(at: removedIndex)
        if wasActive {
            let nextIndex = min(removedIndex, profiles[ci].tabs.count - 1)
            profiles[ci].activeTabID = profiles[ci].tabs[nextIndex].id
        }
        save()
        imagePruner?(allTabTexts())
    }

    func selectTab(_ id: UUID) {
        let ci = currentProfileIndex
        guard profiles[ci].tabs.contains(where: { $0.id == id }) else { return }
        profiles[ci].activeTabID = id
        save()
    }

    func moveTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles[currentProfileIndex].tabs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func updateSelection(for id: UUID, range: NSRange) {
        let ci = currentProfileIndex
        guard let index = profiles[ci].tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = clampedRange(range, text: profiles[ci].tabs[index].text)
        profiles[ci].tabs[index].selectionLocation = clamped.location
        profiles[ci].tabs[index].selectionLength = clamped.length
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

    private func clampSelection(for id: UUID) {
        let ci = currentProfileIndex
        guard let index = profiles[ci].tabs.firstIndex(where: { $0.id == id }) else { return }
        let range = NSRange(location: profiles[ci].tabs[index].selectionLocation ?? 0, length: profiles[ci].tabs[index].selectionLength ?? 0)
        let clamped = clampedRange(range, text: profiles[ci].tabs[index].text)
        profiles[ci].tabs[index].selectionLocation = clamped.location
        profiles[ci].tabs[index].selectionLength = clamped.length
    }

    private func clampedRange(_ range: NSRange, text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
        UserDefaults.standard.set(currentProfileID.uuidString, forKey: Self.activeProfileIDKey)
        // Keep the legacy single-note key updated with the active note so an
        // older build (or external reader) still sees current content.
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

    private static func loadProfiles() -> (profiles: [NoteProfile], activeID: UUID) {
        let defaults = UserDefaults.standard

        // Current format: an array of profiles.
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([NoteProfile].self, from: data),
           !decoded.isEmpty {
            let normalized = decoded.map(normalizeProfile)
            let activeID = defaults.string(forKey: activeProfileIDKey)
                .flatMap(UUID.init(uuidString:))
                .flatMap { id in normalized.contains(where: { $0.id == id }) ? id : nil }
                ?? normalized[0].id
            return (normalized, activeID)
        }

        // Migrate from the pre-profile format (tabs.v1 + activeTabID, or the
        // legacy single-note text) into one "Default" profile.
        let storedTabs = loadStoredTabs()
        let tabs = storedTabs.isEmpty
            ? [NoteTab(text: defaults.string(forKey: legacyTextKey) ?? "")]
            : storedTabs
        let activeTabID = defaults.string(forKey: activeTabIDKey)
            .flatMap(UUID.init(uuidString:))
            .flatMap { id in tabs.contains(where: { $0.id == id }) ? id : nil }
            ?? tabs[0].id
        let profile = normalizeProfile(
            NoteProfile(name: defaultProfileName, tabs: tabs, activeTabID: activeTabID)
        )
        return ([profile], profile.id)
    }

    /// Runs bullet-marker normalization on a profile's tabs and repairs any
    /// invalid active-tab reference.
    private static func normalizeProfile(_ profile: NoteProfile) -> NoteProfile {
        var profile = profile
        profile.tabs = profile.tabs.map { tab in
            var tab = tab
            tab.text = normalizingBulletMarkers(in: tab.text)
            return tab
        }
        if profile.tabs.isEmpty { profile.tabs = [NoteTab()] }
        if !profile.tabs.contains(where: { $0.id == profile.activeTabID }) {
            profile.activeTabID = profile.tabs[0].id
        }
        return profile
    }
}
