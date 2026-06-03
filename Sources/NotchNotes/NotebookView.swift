import AppKit
import MarkdownEngine
import SwiftUI

@MainActor
final class DrawerState: ObservableObject {
    @Published var isExpanded = false
    @Published var revealProgress: CGFloat = 0
    /// When pinned, the drawer stays open and ignores the hover-out auto-collapse.
    @Published var isPinned = false
}

struct NotebookView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var drawerState: DrawerState
    @ObservedObject var editorInteractionState: EditorInteractionState
    let layout: NotchLayout
    let onOpenSettings: () -> Void

    @State private var confirmation: ConfirmationRequest?

    var body: some View {
        ZStack(alignment: .top) {
            drawer
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .onChange(of: confirmation != nil) { _, presenting in
            editorInteractionState.setCursorSuppressed(presenting)
            if presenting {
                editorInteractionState.beginPresentingDialog()
            } else {
                editorInteractionState.endPresentingDialog()
            }
        }
    }

    private var drawer: some View {
        ZStack(alignment: .top) {
            expandedContent
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .opacity(expandedContentOpacity)

            compactIcon

            if let confirmation, drawerState.isExpanded {
                ConfirmationOverlay(
                    request: confirmation,
                    onConfirm: {
                        confirmation.onConfirm()
                        withAnimation(.easeOut(duration: 0.12)) { self.confirmation = nil }
                    },
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.12)) { self.confirmation = nil }
                    }
                )
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
        .mask(alignment: .top) {
            TopAttachedRoundedShape(radius: cornerRadius)
                .frame(width: revealWidth, height: revealHeight)
        }
        .overlay(alignment: .top) {
            TopAttachedRoundedShape(radius: cornerRadius)
                .stroke(.white.opacity(0.09), lineWidth: 1)
                .frame(width: revealWidth, height: revealHeight)
        }
        .contentShape(Rectangle())
        .allowsHitTesting(drawerState.isExpanded)
    }

    private var expandedContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    TabPagerControl(
                        store: store,
                        settingsStore: settingsStore,
                        editorInteractionState: editorInteractionState,
                        requestConfirmation: { confirmation = $0 }
                    )

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            if settingsStore.confirmBeforeDelete {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    confirmation = ConfirmationRequest(
                                        title: "Clear note?",
                                        message: "The content of this tab will be permanently erased.",
                                        confirmTitle: "Clear",
                                        onConfirm: { store.clear() }
                                    )
                                }
                            } else {
                                store.clear()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(DarkIconButtonStyle())
                        .help("Clear")

                        Button {
                            drawerState.isPinned.toggle()
                        } label: {
                            Image(systemName: drawerState.isPinned ? "pin.fill" : "pin")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(DarkIconButtonStyle())
                        .help(drawerState.isPinned ? "Unpin from top" : "Pin on top")

                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(DarkIconButtonStyle())
                        .help("Settings")
                    }
                }
                .frame(height: toolbarHeight, alignment: .center)
                .zIndex(1)

                MarkdownEditorPanel(
                    store: store,
                    imageStore: imageStore,
                    editorInteractionState: editorInteractionState,
                    size: editorSize
                )
                .frame(width: editorSize.width, height: editorSize.height)
                .background(Color(red: 0.06, green: 0.06, blue: 0.07))
            }
        }
        .padding(.top, toolbarTopPadding)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, contentBottomPadding)
        .onAppear {
            editorInteractionState.onSelectionChange = { [weak store] range in
                guard let store else { return }
                store.updateSelection(for: store.activeTabID, range: range)
            }
            editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
        }
        .onChange(of: store.activeTabID) { _, newTabID in
            editorInteractionState.restoreSelection(store.selectionRange(for: newTabID))
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
    }

    private var compactIcon: some View {
        Image(systemName: "note.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: layout.compactSize.width, height: layout.compactSize.height)
            .opacity(1 - drawerState.revealProgress)
    }

    private var revealWidth: CGFloat {
        interpolate(from: layout.compactSize.width, to: layout.expandedSize.width)
    }

    private var revealHeight: CGFloat {
        interpolate(from: layout.compactSize.height, to: layout.expandedSize.height)
    }

    private var cornerRadius: CGFloat {
        interpolate(from: 12, to: 18)
    }

    private var expandedContentOpacity: CGFloat {
        let progress = drawerState.revealProgress
        return min(max((progress - 0.42) / 0.34, 0), 1)
    }

    private var editorSize: CGSize {
        CGSize(
            width: layout.expandedSize.width - contentHorizontalPadding * 2,
            height: layout.expandedSize.height - toolbarTopPadding - contentBottomPadding - toolbarHeight - editorSpacing
        )
    }

    private var toolbarTopPadding: CGFloat {
        layout.compactSize.height + 6
    }

    private var contentHorizontalPadding: CGFloat {
        18
    }

    private var contentBottomPadding: CGFloat {
        18
    }

    private var toolbarHeight: CGFloat {
        28
    }

    private var editorSpacing: CGFloat {
        12
    }

    private func interpolate(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * drawerState.revealProgress
    }
}

struct MarkdownEditorPanel: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    let size: CGSize

    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            MarkdownNoteEditor(
                store: store,
                imageStore: imageStore,
                editorInteractionState: editorInteractionState
            )
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            MarkdownShortcutToolbar(editorInteractionState: editorInteractionState)
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - toolbarHeight - separatorHeight, 120)
    }
}

struct MarkdownShortcutToolbar: View {
    let editorInteractionState: EditorInteractionState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MarkdownCommand.allCases) { command in
                Button {
                    editorInteractionState.applyMarkdownCommand(command)
                } label: {
                    MarkdownCommandLabel(command: command)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help(command.help)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }
}

struct MarkdownCommandLabel: View {
    let command: MarkdownCommand

    var body: some View {
        switch command {
        case .bold:
            Image(systemName: "bold")
        case .italic:
            Image(systemName: "italic")
        case .strikethrough:
            Image(systemName: "strikethrough")
        case .inlineCode:
            Text("`")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        case .link:
            Image(systemName: "link")
        case .quote:
            Image(systemName: "quote.opening")
        case .unorderedList:
            Image(systemName: "list.bullet")
        case .orderedList:
            Image(systemName: "list.number")
        case .todoList:
            Image(systemName: "checklist")
        }
    }
}

/// A pending in-panel confirmation. Rendered as an overlay inside the notch
/// drawer instead of a separate NSAlert window, so the pointer stays within the
/// panel and never triggers the hover-out collapse.
struct ConfirmationRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var onConfirm: () -> Void
}

private struct ConfirmationOverlay: View {
    let request: ConfirmationRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text(request.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(request.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ConfirmationButtonStyle(destructive: false))
                        .pointingHandCursor()
                    Button(request.confirmTitle, action: onConfirm)
                        .buttonStyle(ConfirmationButtonStyle(destructive: true))
                        .pointingHandCursor()
                }
            }
            .padding(18)
            .frame(width: 232)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.045, green: 0.045, blue: 0.052).opacity(0.98))
            )
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)
        }
        .hoverCursor(.arrow)
    }
}

private struct TabTooltipAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ConfirmationButtonStyle: ButtonStyle {
    let destructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = destructive
            ? Color(red: 0.86, green: 0.27, blue: 0.27)
            : Color.white.opacity(0.1)
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(destructive ? Color.white : Color.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .contentShape(Rectangle())
    }
}

struct TabPagerControl: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let editorInteractionState: EditorInteractionState
    let requestConfirmation: (ConfirmationRequest) -> Void
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var hoveredTabID: UUID?

    private let dotCellWidth: CGFloat = 26
    private let dotSpacing: CGFloat = 6
    private var dotStride: CGFloat { dotCellWidth + dotSpacing }
    private let maxDotsStripWidth: CGFloat = 260

    /// The dot strip hugs its content until it would exceed `maxDotsStripWidth`,
    /// after which it stays fixed and scrolls horizontally.
    private var dotsStripWidth: CGFloat {
        let count = CGFloat(store.tabs.count)
        let content = count * dotCellWidth + max(0, count - 1) * dotSpacing
        return min(content, maxDotsStripWidth)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: dotSpacing) {
                ForEach(store.tabs) { tab in
                    let isSelected = tab.id == store.activeTabID
                    let isDragging = draggingID == tab.id
                    let tabColor = Color(hex: tab.colorHex) ?? .white
                    Capsule()
                        .fill(isSelected ? tabColor.opacity(0.9) : tabColor.opacity(0.38))
                        .frame(width: isSelected ? 20 : 6, height: 6)
                        .frame(width: dotCellWidth, height: 24)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(isDragging ? 0.065 : 0))
                                .padding(.horizontal, isSelected ? -4 : 3)
                                .padding(.vertical, isSelected ? 3 : 5)
                        )
                        .scaleEffect(isDragging ? 1.2 : 1.0)
                        .offset(x: isDragging ? dragOffset : 0)
                        .zIndex(isDragging ? 1 : 0)
                        .animation(tabSwitchAnimation, value: isSelected)
                        .transaction { txn in
                            if isDragging { txn.animation = nil }
                        }
                        .help("Switch tab")
                        .pointingHandCursor()
                        .onTapGesture {
                            rememberCurrentSelection()
                            withAnimation(tabSwitchAnimation) {
                                store.selectTab(tab.id)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in handleDrag(tab, translation: value.translation.width) }
                                .onEnded { _ in endDrag() }
                        )
                        .contextMenu {
                            Button("Clear Completed") {
                                cleanFinishedItems(tab.id)
                            }
                            Button("Delete", role: .destructive) {
                                requestDeleteTab(tab.id)
                            }
                            .disabled(store.tabs.count <= 1)
                        }
                        .onHover { hovering in
                            if hovering {
                                hoveredTabID = tab.id
                            } else if hoveredTabID == tab.id {
                                hoveredTabID = nil
                            }
                        }
                        .anchorPreference(key: TabTooltipAnchorKey.self, value: .bounds) {
                            [tab.id: $0]
                        }
                }
              }
              .frame(height: 28, alignment: .center)
            }
            .frame(width: dotsStripWidth, height: 28)

            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.addTab()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .help("New tab")
        }
        .frame(height: 28, alignment: .center)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .overlayPreferenceValue(TabTooltipAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if draggingID == nil,
                   let id = hoveredTabID,
                   let anchor = anchors[id],
                   let tab = store.tabs.first(where: { $0.id == id }) {
                    let rect = proxy[anchor]
                    tabTooltip(tabTitle(tab))
                        .position(x: rect.midX, y: rect.maxY + 14)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func tabTooltip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.045, green: 0.045, blue: 0.052).opacity(0.98))
            )
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
    }

    private func tabTitle(_ tab: NoteTab) -> String {
        let firstLine = tab.text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Empty note" : String(trimmed.prefix(40))
    }

    private var tabSwitchAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.82)
    }

    private func requestDeleteTab(_ id: UUID) {
        guard store.tabs.count > 1 else { return }
        if settingsStore.confirmBeforeDelete {
            requestConfirmation(
                ConfirmationRequest(
                    title: "Delete tab?",
                    message: "The content of this tab will be permanently deleted.",
                    confirmTitle: "Delete",
                    onConfirm: { deleteTab(id) }
                )
            )
        } else {
            deleteTab(id)
        }
    }

    private func deleteTab(_ id: UUID) {
        rememberCurrentSelection()
        withAnimation(tabSwitchAnimation) {
            store.removeTab(id)
        }
    }

    private func cleanFinishedItems(_ id: UUID) {
        if settingsStore.confirmBeforeDelete {
            requestConfirmation(
                ConfirmationRequest(
                    title: "Clear completed?",
                    message: "Completed to-dos in this tab will be removed.",
                    confirmTitle: "Clear",
                    onConfirm: { performCleanFinished(id) }
                )
            )
        } else {
            performCleanFinished(id)
        }
    }

    private func performCleanFinished(_ id: UUID) {
        if id == store.activeTabID {
            rememberCurrentSelection()
        }
        store.cleanFinishedTodos(for: id)
        if id == store.activeTabID {
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }

    private func handleDrag(_ tab: NoteTab, translation: CGFloat) {
        if draggingID != tab.id {
            draggingID = tab.id
            rememberCurrentSelection()
        }
        guard let from = store.tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        let minOffset = -CGFloat(from) * dotStride
        let maxOffset = CGFloat(store.tabs.count - 1 - from) * dotStride
        dragOffset = min(max(translation, minOffset), maxOffset)

        let target = from + Int((dragOffset / dotStride).rounded())
        if target != from, target >= 0, target < store.tabs.count {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.moveTab(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
            }
            dragOffset -= CGFloat(target - from) * dotStride
        }
    }

    private func endDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            dragOffset = 0
            draggingID = nil
        }
    }
}

struct CompactNotchView: View {
    let layout: NotchLayout

    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: layout.compactSize.width, height: layout.compactSize.height)
            .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
            .clipShape(TopAttachedRoundedShape(radius: 12))
            .overlay(
                TopAttachedRoundedShape(radius: 12)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
            .pointingHandCursor()
    }
}

struct MarkdownNoteEditor: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    @State private var isWikiLinkActive = false
    @State private var pendingInlineReplacement: InlineReplacementRequest?

    var body: some View {
        NativeTextViewWrapper(
            text: Binding(
                get: { store.text },
                set: { store.updateText($0) }
            ),
            isWikiLinkActive: $isWikiLinkActive,
            pendingInlineReplacement: $pendingInlineReplacement,
            configuration: configuration,
            fontName: "SF Pro",
            fontSize: 15,
            documentId: store.activeTabID.uuidString,
            isEditable: true,
            onPasteImage: savePastedImage
        )
        .background {
            EditorFocusBinder(state: editorInteractionState)
        }
    }

    private func savePastedImage(_ pasteboard: NSPasteboard) -> String? {
        imageStore.saveImage(from: pasteboard)
    }

    private var accentColor: NSColor {
        let hex = store.tabs.first(where: { $0.id == store.activeTabID })?.colorHex
        return hex.flatMap { NSColor(hex: $0) } ?? NSColor(white: 0.92, alpha: 1)
    }

    private var configuration: MarkdownEditorConfiguration {
        let accent = accentColor
        let theme = MarkdownEditorTheme(
            bodyText: NSColor(white: 0.92, alpha: 1),
            mutedText: NSColor(white: 0.58, alpha: 1),
            disabledText: NSColor(white: 0.38, alpha: 1),
            headingMarker: NSColor(white: 0.44, alpha: 1),
            link: NSColor.systemBlue,
            incompleteLink: NSColor.systemBlue.withAlphaComponent(0.75),
            findMatchHighlight: NSColor.systemYellow.withAlphaComponent(0.55),
            findCurrentMatchHighlight: NSColor.systemYellow,
            latexLightModeText: .white,
            latexDarkModeText: .white,
            strikethroughColor: NSColor(white: 0.62, alpha: 1),
            caretColor: accent,
            selectionColor: accent.withAlphaComponent(0.30),
            controlAccent: accent
        )

        let services = MarkdownEditorServices(images: imageStore)

        return MarkdownEditorConfiguration(
            theme: theme,
            services: services,
            lists: ListStyle(indentPerLevel: 40, extraLineHeight: 1),
            imageEmbed: ImageEmbedStyle(fallbackMaxWidth: 440, paragraphSpacing: 6, imageGap: 6),
            checkbox: CheckboxStyle(minimumExtraSpacing: 8),
            overscroll: OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0),
            dragSelection: DragSelectionPolicy(movementThreshold: 8, edgeTriggerDistance: 8, scrollStepPerTick: 4, ticksPerSecond: 30),
            scrollers: .vertical,
            textInsets: TextInsets(horizontal: 12, vertical: 12)
        )
    }
}

struct TopAttachedRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

struct DarkIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 13, weight: .semibold),
            normalOpacity: 0.055,
            hoverOpacity: 0.085,
            pressedOpacity: 0.12,
            strokeOpacity: 0.06,
            foregroundOpacity: 0.76,
            pressedForegroundOpacity: 0.55
        )
    }
}

struct TabIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .bold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.48
        )
    }
}

struct TabDotButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: isSelected ? 0.045 : 0,
            hoverOpacity: isSelected ? 0.075 : 0.055,
            pressedOpacity: isSelected ? 0.10 : 0.08,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.58
        )
    }
}

struct MarkdownToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.66,
            hoverForegroundOpacity: 0.84,
            pressedForegroundOpacity: 0.54
        )
    }
}

private struct RoundedHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let font: Font?
    let normalOpacity: CGFloat
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat
    let strokeOpacity: CGFloat
    let foregroundOpacity: CGFloat
    let hoverForegroundOpacity: CGFloat
    let pressedForegroundOpacity: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(
        configuration: ButtonStyle.Configuration,
        font: Font?,
        normalOpacity: CGFloat,
        hoverOpacity: CGFloat,
        pressedOpacity: CGFloat,
        strokeOpacity: CGFloat,
        foregroundOpacity: CGFloat,
        hoverForegroundOpacity: CGFloat? = nil,
        pressedForegroundOpacity: CGFloat
    ) {
        self.configuration = configuration
        self.font = font
        self.normalOpacity = normalOpacity
        self.hoverOpacity = hoverOpacity
        self.pressedOpacity = pressedOpacity
        self.strokeOpacity = strokeOpacity
        self.foregroundOpacity = foregroundOpacity
        self.hoverForegroundOpacity = hoverForegroundOpacity ?? foregroundOpacity
        self.pressedForegroundOpacity = pressedForegroundOpacity
    }

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white.opacity(currentForegroundOpacity))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(currentBackgroundOpacity))
            )
            .animation(.easeOut(duration: 0.10), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .pointingHandCursor(isEnabled: isEnabled)
    }

    private var currentBackgroundOpacity: CGFloat {
        guard isEnabled else { return 0 }
        if configuration.isPressed {
            return pressedOpacity
        }
        return isHovering ? hoverOpacity : normalOpacity
    }

    private var currentForegroundOpacity: CGFloat {
        guard isEnabled else { return 0.22 }
        if configuration.isPressed {
            return pressedForegroundOpacity
        }
        return isHovering ? hoverForegroundOpacity : foregroundOpacity
    }
}

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }

    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
    }
}

private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, !isActive {
                    cursor.push()
                    isActive = true
                } else if !hovering, isActive {
                    NSCursor.pop()
                    isActive = false
                }
            }
            .onDisappear {
                if isActive {
                    NSCursor.pop()
                    isActive = false
                }
            }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isCursorActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, isEnabled, !isCursorActive {
                    NSCursor.pointingHand.push()
                    isCursorActive = true
                } else if (!hovering || !isEnabled), isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onDisappear {
                if isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
    }
}
