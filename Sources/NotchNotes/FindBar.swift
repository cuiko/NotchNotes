import AppKit
import SwiftUI

/// Notification names bridging the app's find bar to the engine's highlight
/// renderer (`NativeTextViewCoordinator+Find`).
enum FindBus {
    static let scrollToRange = Notification.Name("notchNotes.find.scrollToRange")
    static let clear = Notification.Name("notchNotes.find.clear")
}

/// Drives the find bar: computes case-insensitive matches in the active note
/// and posts them to the engine, which paints the highlights and scrolls the
/// current match into view.
@MainActor
final class FindState: ObservableObject {
    @Published var isActive = false
    @Published var query = ""
    @Published var caseSensitive = false
    @Published private(set) var matchCount = 0
    @Published private(set) var currentIndex = 0

    private var matches: [NSRange] = []

    func open() {
        isActive = true
    }

    func close() {
        isActive = false
        query = ""
        matches = []
        matchCount = 0
        currentIndex = 0
        postClear()
    }

    /// Recompute matches for `query` in `text` and highlight them.
    func search(_ query: String, in text: String) {
        self.query = query
        let ns = text as NSString
        guard !query.isEmpty, ns.length > 0 else {
            matches = []
            matchCount = 0
            currentIndex = 0
            postClear()
            return
        }

        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var found: [NSRange] = []
        var start = 0
        while start < ns.length {
            let range = ns.range(
                of: query,
                options: options,
                range: NSRange(location: start, length: ns.length - start)
            )
            if range.location == NSNotFound { break }
            found.append(range)
            start = range.location + max(1, range.length)
        }

        matches = found
        matchCount = found.count
        guard matchCount > 0 else {
            currentIndex = 0
            postClear()
            return
        }
        currentIndex = min(currentIndex, matchCount - 1)
        postScroll()
    }

    func next() {
        guard matchCount > 0 else { return }
        currentIndex = (currentIndex + 1) % matchCount
        postScroll()
    }

    func previous() {
        guard matchCount > 0 else { return }
        currentIndex = (currentIndex - 1 + matchCount) % matchCount
        postScroll()
    }

    private func postScroll() {
        guard currentIndex < matches.count else { return }
        NotificationCenter.default.post(
            name: FindBus.scrollToRange,
            object: nil,
            userInfo: [
                "range": matches[currentIndex],
                "currentIndex": currentIndex,
                "allRanges": matches
            ]
        )
    }

    private func postClear() {
        NotificationCenter.default.post(name: FindBus.clear, object: nil)
    }
}

struct FindBarView: View {
    @ObservedObject var findState: FindState
    @ObservedObject var store: NoteStore
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            TextField("Find", text: $findState.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .focused($fieldFocused)
                .frame(minWidth: 90)
                .onSubmit { findState.next() }
                .onChange(of: findState.query) { _, q in
                    findState.search(q, in: store.text)
                }

            Text(countLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize()

            caseButton

            Divider().frame(height: 16).overlay(.white.opacity(0.12))

            iconButton("chevron.up", help: "Previous") { findState.previous() }
                .disabled(findState.matchCount == 0)
            iconButton("chevron.down", help: "Next (⏎)") { findState.next() }
                .disabled(findState.matchCount == 0)
            iconButton("xmark", help: "Close (esc)") { findState.close() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        .onAppear {
            fieldFocused = true
            if !findState.query.isEmpty {
                findState.search(findState.query, in: store.text)
            }
        }
        .onChange(of: store.text) { _, text in
            if findState.isActive { findState.search(findState.query, in: text) }
        }
        .onChange(of: store.activeTabID) { _, _ in
            if findState.isActive { findState.search(findState.query, in: store.text) }
        }
    }

    private var countLabel: String {
        if findState.query.isEmpty { return "" }
        if findState.matchCount == 0 { return "0" }
        return "\(findState.currentIndex + 1)/\(findState.matchCount)"
    }

    private var caseButton: some View {
        Button {
            findState.caseSensitive.toggle()
            findState.search(findState.query, in: store.text)
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(findState.caseSensitive ? .white : .white.opacity(0.5))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(findState.caseSensitive ? 0.18 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .findPointerCursor()
        .help("Case sensitive")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .findPointerCursor()
        .help(help)
    }
}

private extension View {
    func findPointerCursor() -> some View {
        modifier(FindPointerCursorModifier())
    }
}

private struct FindPointerCursorModifier: ViewModifier {
    @State private var active = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, !active {
                    NSCursor.pointingHand.push()
                    active = true
                } else if !hovering, active {
                    NSCursor.pop()
                    active = false
                }
            }
            .onDisappear {
                if active { NSCursor.pop(); active = false }
            }
    }
}
