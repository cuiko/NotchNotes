import AppKit
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent) -> Void)?
    /// Given a mouse event, returns true when it was consumed for edge-resizing
    /// (so it should not reach the editor content).
    var resizeHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp {
            if resizeHandler?(event) == true { return }
            onMouseEvent?(event)
        }

        super.sendEvent(event)
    }
}

@MainActor
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class NotchPanelController: NSObject {
    private let store = NoteStore()
    private let settingsStore = AppSettingsStore()
    private let imageStore = LocalImageStore()
    private let drawerState = DrawerState()
    private let editorInteractionState = EditorInteractionState()
    private lazy var settingsPopoverController = SettingsPopoverController(settingsStore: settingsStore, noteStore: store, imageStore: imageStore)
    private let hotPanel: NotchPanel
    private let drawerPanel: NotchPanel
    private var hostingView: NSHostingView<NotebookView>?
    private var hotHostingView: NSHostingView<CompactNotchView>?
    private var mousePollingTimer: Timer?
    private var globalMouseDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var cachedLayout: NotchLayout?
    private var isExpanded = false
    private var activeMenuTrackingCount = 0
    private var collapseTask: DispatchWorkItem?

    // MARK: Edge-resize state
    private enum ResizeEdge { case left, right, bottom, bottomLeft, bottomRight }
    private var resizeEdge: ResizeEdge?
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartSize: NSSize = .zero
    private var didShowResizeCursor = false
    /// After a resize ends, suppress hover-out collapse until this time so the
    /// drawer doesn't vanish if the pointer ended up outside it.
    private var resizeGraceUntil: Date = .distantPast
    private static let resizeEdgeThreshold: CGFloat = 14
    private static let resizeGraceInterval: TimeInterval = 1.0
    private static let drawerWidthKey = "notchNotes.drawerWidth"
    private static let drawerHeightKey = "notchNotes.drawerHeight"

    override init() {
        hotPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        drawerPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        store.imagePruner = { [imageStore] remainingTexts in
            imageStore.pruneImages(referencedIn: remainingTexts)
        }
        settingsStore.onIndentChange = { [store, editorInteractionState] oldSpaces, oldCount, newSpaces, newCount in
            store.reindentAllTabs(
                fromUseSpaces: oldSpaces, fromCount: oldCount,
                toUseSpaces: newSpaces, toCount: newCount
            )
            // Re-lay out so the migrated active-tab text renders immediately.
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
        // Apply the persisted code-block theme, then switch on future changes.
        MarkdownNoteEditor.sharedCodeHighlighter.setTheme(settingsStore.codeTheme)
        settingsStore.onCodeThemeChange = { theme in
            MarkdownNoteEditor.sharedCodeHighlighter.setTheme(theme)
        }
        loadPersistedDrawerSize()
        configurePanel(hotPanel)
        configurePanel(drawerPanel)
        drawerPanel.resizeHandler = { [weak self] event in
            self?.handleDrawerResize(event) ?? false
        }
        rebuildContent()
        startMousePolling()
        observeScreenChanges()
        observePanelMouseEvents()
        observeGlobalSelectionMouseEvents()
        observeMenuTracking()
    }

    func showDocked() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        isExpanded = false
        drawerState.isExpanded = false
        drawerState.revealProgress = 0
        hotPanel.setFrame(hotFrame(for: layout), display: true)
        hotPanel.orderFrontRegardless()
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        drawerPanel.orderOut(nil)
    }

    func expand(animated: Bool) {
        guard !isExpanded else { return }
        let layout = currentLayout()
        cancelCollapse()
        isExpanded = true
        rebuildContent(layout: layout)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        NSApp.activate(ignoringOtherApps: true)
        drawerPanel.makeKeyAndOrderFront(nil)
        hotPanel.orderOut(nil)
        setDrawerExpanded(true, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self else { return }
            guard self.isExpanded else { return }
            self.editorInteractionState.restoreSelection(
                self.store.selectionRange(for: self.store.activeTabID),
                searchingIn: self.hostingView
            )
            self.editorInteractionState.requestLayoutRefresh(searchingIn: self.hostingView)
            self.editorInteractionState.requestFocus(searchingIn: self.hostingView)
        }
    }

    func collapse(animated: Bool) {
        guard isExpanded else { return }
        if let range = editorInteractionState.currentSelectionRange() {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        settingsPopoverController.close(animated: false)
        isExpanded = false
        setDrawerExpanded(false, animated: animated)
        let delay: TimeInterval = animated ? 0.18 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !self.isExpanded else { return }
            let layout = self.currentLayout()
            self.drawerPanel.orderOut(nil)
            self.hotPanel.setFrame(self.hotFrame(for: layout), display: true)
            self.hotPanel.orderFrontRegardless()
        }
    }

    private func configurePanel(_ panel: NotchPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
    }

    private func rebuildContent(layout: NotchLayout? = nil) {
        let layout = layout ?? currentLayout()
        cachedLayout = layout
        let hotView = CompactNotchView(layout: layout)
        let view = NotebookView(
            store: store,
            settingsStore: settingsStore,
            imageStore: imageStore,
            drawerState: drawerState,
            editorInteractionState: editorInteractionState,
            layout: layout,
            onOpenSettings: { [weak self] in self?.openSettingsPopover() }
        )

        if let hotHostingView {
            hotHostingView.rootView = hotView
        } else {
            let host = FirstMouseHostingView(rootView: hotView)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            hotPanel.contentView = host
            hotHostingView = host
        }

        if let hostingView {
            hostingView.rootView = view
            return
        }

        let host = FirstMouseHostingView(rootView: view)
        // Fill the panel and track its size so growing the window (edge-resize)
        // doesn't leave the content pinned to the bottom, gapping at the top.
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        drawerPanel.contentView = host
        hostingView = host
    }

    private func setDrawerExpanded(_ expanded: Bool, animated: Bool) {
        guard animated else {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
            return
        }

        let animation: Animation = expanded
            ? .spring(response: 0.28, dampingFraction: 0.86)
            : .easeOut(duration: 0.16)

        withAnimation(animation) {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
        }
    }

    private func startMousePolling() {
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(mousePollingTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        mousePollingTimer = timer
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observePanelMouseEvents() {
        hotPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            guard event.type == .leftMouseDown else { return }
            self.expand(animated: true)
        }

        drawerPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            self.editorInteractionState.handleMouseEvent(event, searchingIn: self.hostingView)
        }
    }

    private func observeGlobalSelectionMouseEvents() {
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseDragged()
            }
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseUp()
            }
        }
    }

    private func observeMenuTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        let layout = currentLayout()
        cancelCollapse()
        rebuildContent(layout: layout)
        hotPanel.setFrame(hotFrame(for: layout), display: true)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
    }

    @objc private func mousePollingTick(_ timer: Timer) {
        let location = NSEvent.mouseLocation
        updateResizeCursor(globalPoint: location)
        handleMouseLocation(location)
    }

    @objc private func menuTrackingDidBegin(_ notification: Notification) {
        activeMenuTrackingCount += 1
        cancelCollapse()
    }

    @objc private func menuTrackingDidEnd(_ notification: Notification) {
        activeMenuTrackingCount = max(0, activeMenuTrackingCount - 1)
        guard activeMenuTrackingCount == 0, isExpanded else { return }
        handleMouseLocation(NSEvent.mouseLocation)
    }

    private func handleMouseLocation(_ point: NSPoint) {
        if isExpanded {
            if resizeEdge != nil || Date() < resizeGraceUntil {
                cancelCollapse()
                return
            }

            if drawerState.isPinned {
                cancelCollapse()
                return
            }

            if activeMenuTrackingCount > 0 {
                cancelCollapse()
                return
            }

            if editorInteractionState.isDraggingSelection {
                cancelCollapse()
                return
            }

            if editorInteractionState.shouldKeepDrawerExpanded {
                cancelCollapse()
                return
            }

            if isPointInExpandedStayRegion(point) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            return
        }

        if settingsStore.triggerMode == .hover, activationFrame().contains(point) {
            expand(animated: true)
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        guard activeMenuTrackingCount == 0 else { return }
        guard Date() >= resizeGraceUntil else { return }
        guard !drawerState.isPinned else { return }
        guard !editorInteractionState.shouldKeepDrawerExpanded else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseTask = nil
            guard self.activeMenuTrackingCount == 0 else { return }
            guard !self.drawerState.isPinned else { return }
            guard !self.editorInteractionState.isDraggingSelection else { return }
            guard !self.editorInteractionState.shouldKeepDrawerExpanded else { return }
            guard !self.isPointInExpandedStayRegion(NSEvent.mouseLocation) else { return }
            self.collapse(animated: true)
        }

        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func activationFrame() -> NSRect {
        let layout = currentLayout()
        let frame = hotPanel.frame
        guard frame.width > 0, frame.height > 0 else {
            return hotFrame(for: layout)
        }

        return frame
    }

    private func isPointInExpandedStayRegion(_ point: NSPoint) -> Bool {
        let margin: CGFloat = 10
        return drawerPanel.frame.insetBy(dx: -margin, dy: -margin).contains(point)
            || activationFrame().contains(point)
            || settingsPopoverController.contains(point)
    }

    private func openSettingsPopover() {
        cancelCollapse()
        settingsPopoverController.toggle(relativeTo: drawerPanel)
    }

    private func currentLayout() -> NotchLayout {
        NotchGeometry.layout(for: targetScreen())
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func hotFrame(for layout: NotchLayout) -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return frame(for: layout.compactSize, topY: screenFrame.maxY + layout.compactTopOffset, in: screenFrame)
    }

    private func drawerFrame(for layout: NotchLayout) -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topY = screenFrame.maxY + layout.expandedTopOffset
        return frame(for: effectiveExpandedSize(for: layout), topY: topY, in: screenFrame)
    }

    /// The drawer's current size: the user's dragged override clamped to the
    /// layout's [default … max] bounds, or the default when unset.
    private func effectiveExpandedSize(for layout: NotchLayout) -> NSSize {
        guard let override = drawerState.expandedSizeOverride else { return layout.expandedSize }
        return NSSize(
            width: min(max(override.width, layout.expandedSize.width), layout.maxExpandedSize.width),
            height: min(max(override.height, layout.expandedSize.height), layout.maxExpandedSize.height)
        )
    }

    // MARK: - Edge resizing

    /// Intercepts drawer-panel mouse events near its left/right/bottom edges to
    /// resize it. Horizontal drags are symmetric (the drawer stays centered);
    /// the bottom grows downward. Returns true when the event is consumed.
    private func handleDrawerResize(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard isExpanded, let edge = resizeEdge(at: event) else { return false }
            resizeEdge = edge
            resizeStartMouse = NSEvent.mouseLocation
            resizeStartSize = effectiveExpandedSize(for: currentLayout())
            return true
        case .leftMouseDragged:
            guard let edge = resizeEdge else { return false }
            applyResize(edge: edge, mouse: NSEvent.mouseLocation)
            return true
        case .leftMouseUp:
            guard resizeEdge != nil else { return false }
            resizeEdge = nil
            resizeGraceUntil = Date().addingTimeInterval(Self.resizeGraceInterval)
            persistDrawerSize()
            return true
        default:
            return false
        }
    }

    private func resizeEdge(at event: NSEvent) -> ResizeEdge? {
        resizeEdge(atLocalPoint: event.locationInWindow, in: drawerPanel.frame.size)
    }

    /// `point` is in the drawer panel's coordinate space (origin bottom-left).
    private func resizeEdge(atLocalPoint point: NSPoint, in size: NSSize) -> ResizeEdge? {
        guard size.width > 0, size.height > 0 else { return nil }
        guard point.x >= 0, point.x <= size.width, point.y >= 0, point.y <= size.height else { return nil }
        let threshold = Self.resizeEdgeThreshold
        let nearLeft = point.x <= threshold
        let nearRight = point.x >= size.width - threshold
        let nearBottom = point.y <= threshold // window origin is bottom-left

        switch (nearBottom, nearLeft, nearRight) {
        case (true, true, _): return .bottomLeft
        case (true, _, true): return .bottomRight
        case (true, _, _): return .bottom
        case (false, true, _): return .left
        case (false, _, true): return .right
        default: return nil
        }
    }

    /// The double-arrow cursor for an edge; corners use diagonal cursors when
    /// available.
    private func resizeCursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .bottom: return .resizeUpDown
        case .bottomLeft: return Self.diagonalCursor("_windowResizeNorthEastSouthWestCursor") ?? .resizeUpDown
        case .bottomRight: return Self.diagonalCursor("_windowResizeNorthWestSouthEastCursor") ?? .resizeUpDown
        }
    }

    private static func diagonalCursor(_ selectorName: String) -> NSCursor? {
        let selector = NSSelectorFromString(selectorName)
        guard NSCursor.responds(to: selector) else { return nil }
        return NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor
    }

    /// Shows a resize cursor while the pointer hovers a draggable edge (and the
    /// drawer isn't currently being resized).
    private func updateResizeCursor(globalPoint: NSPoint) {
        guard isExpanded, resizeEdge == nil else { return }
        let frame = drawerPanel.frame
        let local = NSPoint(x: globalPoint.x - frame.minX, y: globalPoint.y - frame.minY)
        if let edge = resizeEdge(atLocalPoint: local, in: frame.size) {
            resizeCursor(for: edge).set()
            didShowResizeCursor = true
        } else if didShowResizeCursor {
            NSCursor.arrow.set()
            didShowResizeCursor = false
        }
    }

    private func applyResize(edge: ResizeEdge, mouse: NSPoint) {
        let dx = mouse.x - resizeStartMouse.x
        let dy = mouse.y - resizeStartMouse.y

        var width = resizeStartSize.width
        var height = resizeStartSize.height

        switch edge {
        case .right, .bottomRight:
            width = resizeStartSize.width + dx * 2 // symmetric about the center
        case .left, .bottomLeft:
            width = resizeStartSize.width - dx * 2
        case .bottom:
            break
        }
        switch edge {
        case .bottom, .bottomLeft, .bottomRight:
            height = resizeStartSize.height - dy // dragging down (dy < 0) grows height
        case .left, .right:
            break
        }

        let layout = currentLayout()
        width = min(max(width, layout.expandedSize.width), layout.maxExpandedSize.width)
        height = min(max(height, layout.expandedSize.height), layout.maxExpandedSize.height)

        drawerState.expandedSizeOverride = NSSize(width: width, height: height)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        // Flush the SwiftUI content's layout in the same cycle so it reflows
        // with the new frame instead of lagging a frame (which briefly leaves a
        // gap at the top-attached edge).
        drawerPanel.contentView?.layoutSubtreeIfNeeded()
        drawerPanel.displayIfNeeded()
    }

    private func persistDrawerSize() {
        guard let size = drawerState.expandedSizeOverride else { return }
        UserDefaults.standard.set(Double(size.width), forKey: Self.drawerWidthKey)
        UserDefaults.standard.set(Double(size.height), forKey: Self.drawerHeightKey)
    }

    private func loadPersistedDrawerSize() {
        let width = UserDefaults.standard.double(forKey: Self.drawerWidthKey)
        let height = UserDefaults.standard.double(forKey: Self.drawerHeightKey)
        guard width > 0, height > 0 else { return }
        drawerState.expandedSizeOverride = NSSize(width: width, height: height)
    }

    private func frame(for size: NSSize, topY: CGFloat, in screenFrame: NSRect) -> NSRect {
        let x = screenFrame.midX - size.width / 2
        let y = topY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
