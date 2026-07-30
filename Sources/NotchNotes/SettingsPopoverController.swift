import AppKit
import SwiftUI

@MainActor
final class SettingsPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SettingsPopoverController: NSObject, NSWindowDelegate {
    private let settingsStore: AppSettingsStore
    private let noteStore: NoteStore
    private var panel: SettingsPopoverPanel?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var suppressShowUntil: Date?
    private var pinnedTopY: CGFloat = 0
    private var revealOnMeasure: (() -> Void)?
    private let contentSize: NSSize

    init(settingsStore: AppSettingsStore, noteStore: NoteStore) {
        self.settingsStore = settingsStore
        self.noteStore = noteStore
        // Match the popover width to the drawer's minimum width so the settings
        // panel uses the horizontal space instead of being a tall column.
        let drawerWidth = NotchGeometry.layout(for: NotchGeometry.targetScreen()).expandedSize.width
        self.contentSize = NSSize(width: drawerWidth, height: 384)
        super.init()
    }

    /// Toggle the popover for the gear button: close when shown, open when
    /// hidden. Respects the brief suppress window so the same click that an
    /// outside-click monitor already used to close the panel doesn't reopen it.
    func toggle(relativeTo parentWindow: NSWindow?) {
        if panel != nil {
            close(animated: true)
            return
        }
        if let suppressShowUntil, Date() < suppressShowUntil {
            self.suppressShowUntil = nil
            return
        }
        show(relativeTo: parentWindow)
    }

    func show(relativeTo parentWindow: NSWindow?) {
        if let suppressShowUntil, Date() < suppressShowUntil {
            return
        }
        suppressShowUntil = nil

        if let panel {
            close(panel, animated: true)
            return
        }

        let panel = SettingsPopoverPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self

        let view = SettingsPopoverView(
            settingsStore: settingsStore,
            store: noteStore,
            panelSize: contentSize
        ) { [weak self] height in
            self?.applyContentHeight(height)
        }
        let host = FirstMouseHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: contentSize)
        host.wantsLayer = true
        // Clip the hosting layer to a rounded rect so all four corners stay
        // rounded even if the panel height differs from the content by a hair.
        host.layer?.cornerRadius = 14
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        host.layoutSubtreeIfNeeded()
        // Initial estimate; SwiftUI reports the exact content height back via
        // `applyContentHeight` once it lays out, which tightens the panel so
        // there's no empty space below the two columns.
        let fittingHeight = host.fittingSize.height
        let resolvedSize = NSSize(
            width: contentSize.width,
            height: fittingHeight > 0 ? fittingHeight : contentSize.height
        )
        host.autoresizingMask = [.width, .height]
        panel.setContentSize(resolvedSize)
        panel.contentView = host

        self.panel = panel
        let finalOrigin = origin(relativeTo: parentWindow, size: resolvedSize)
        // Pin the panel's top edge (just under the gear) so height corrections
        // grow/shrink downward instead of shifting the whole panel.
        pinnedTopY = finalOrigin.y + resolvedSize.height
        // No position slide — the panel sits at its final spot and the SwiftUI
        // scale (anchored top-right, at the gear) does the reveal so it grows
        // downward from the gear instead of drifting up from below.
        panel.setFrameOrigin(finalOrigin)
        panel.alphaValue = 0

        // Stay invisible until SwiftUI reports the exact content height and we
        // correct the frame; only then fade in, so the height snap never shows.
        // Fade in while sliding down a few points from the gear.
        revealOnMeasure = { [weak panel] in
            guard let panel else { return }
            let end = panel.frame.origin
            let start = NSPoint(x: end.x, y: end.y + 10)
            panel.setFrameOrigin(start)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(end)
            }
        }

        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()

        // Fallback in case the measurement callback never arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.fireReveal()
        }
    }

    /// Resize the panel to exactly fit the content height SwiftUI reports,
    /// keeping the top edge pinned so it stays anchored under the gear.
    private func applyContentHeight(_ height: CGFloat) {
        guard let panel, height > 1 else { return }
        if abs(panel.frame.height - height) >= 0.5 {
            let newFrame = NSRect(
                x: panel.frame.minX,
                y: pinnedTopY - height,
                width: panel.frame.width,
                height: height
            )
            panel.setFrame(newFrame, display: true)
            panel.invalidateShadow()
        }
        fireReveal()
    }

    /// Fade the panel in once (after the first height correction). Subsequent
    /// calls are no-ops.
    private func fireReveal() {
        guard let reveal = revealOnMeasure else { return }
        revealOnMeasure = nil
        reveal()
    }

    func close() {
        guard let panel else { return }
        close(panel, animated: true)
    }

    func close(animated: Bool) {
        guard let panel else { return }
        close(panel, animated: animated)
    }

    func contains(_ point: NSPoint) -> Bool {
        panel?.frame.insetBy(dx: -4, dy: -4).contains(point) ?? false
    }

    func windowWillClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close(animated: true, suppressImmediateReopen: true)
    }

    private func close(animated: Bool, suppressImmediateReopen: Bool) {
        guard let panel else { return }
        close(panel, animated: animated, suppressImmediateReopen: suppressImmediateReopen)
    }

    private func close(_ panel: SettingsPopoverPanel, animated: Bool, suppressImmediateReopen: Bool = false) {
        removeOutsideClickMonitor()
        revealOnMeasure = nil
        if suppressImmediateReopen {
            suppressShowUntil = Date(timeIntervalSinceNow: 0.25)
        }

        guard animated else {
            if self.panel === panel {
                self.panel = nil
            }
            panel.close()
            return
        }

        if self.panel === panel {
            self.panel = nil
        }

        // Pure in-place fade out — no position slide.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }

        panel.perform(#selector(NSWindow.close), with: nil, afterDelay: 0.13)
    }

    private func origin(relativeTo parentWindow: NSWindow?, size: NSSize) -> NSPoint {
        let parentFrame = parentWindow?.frame
            ?? NotchGeometry.targetScreen()?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let screenFrame = parentWindow?.screen?.frame
            ?? NotchGeometry.targetScreen()?.frame
            ?? NSScreen.main?.frame
            ?? parentFrame

        let preferredOrigin = NSPoint(
            x: parentFrame.maxX - size.width - 22,
            y: parentFrame.maxY - size.height - 88
        )

        return NSPoint(
            x: min(max(preferredOrigin.x, screenFrame.minX + 10), screenFrame.maxX - size.width - 10),
            y: min(max(preferredOrigin.y, screenFrame.minY + 10), screenFrame.maxY - size.height - 10)
        )
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard let panel = self.panel else { return event }
            if event.window !== panel, !self.contains(NSEvent.mouseLocation) {
                self.close(panel, animated: true, suppressImmediateReopen: true)
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.close(animated: true, suppressImmediateReopen: true)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }

        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }
}

struct SettingsPopoverView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var store: NoteStore
    let panelSize: CGSize
    var onMeasuredHeight: ((CGFloat) -> Void)? = nil
    @State private var pendingDeleteProfile: NoteProfile?

    var body: some View {
        ZStack {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    profilesSection
                    generalSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    triggerSection
                    indentationSection
                    codeBlockSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)

            if let pending = pendingDeleteProfile {
                deleteProfileConfirmation(pending)
            }
        }
        .frame(width: panelSize.width)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.045, green: 0.045, blue: 0.052).opacity(0.98))
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onMeasuredHeight?(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        onMeasuredHeight?(newHeight)
                    }
            }
        )
        .onAppear {
            settingsStore.refreshLaunchAtLoginStatus()
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))

            HStack(spacing: 8) {
                ForEach(TriggerMode.allCases) { mode in
                    Button {
                        settingsStore.triggerMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                            Text(mode.title)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                    }
                    .buttonStyle(PopoverTriggerButtonStyle(isSelected: settingsStore.triggerMode == mode))
                }
            }
        }
    }

    private var indentationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Indentation")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))

            HStack(spacing: 8) {
                indentButton(title: "Tab", icon: "arrow.right.to.line", selected: !settingsStore.indentUsesSpaces) {
                    settingsStore.indentUsesSpaces = false
                }
                indentButton(title: "Spaces", icon: "space", selected: settingsStore.indentUsesSpaces) {
                    settingsStore.indentUsesSpaces = true
                }
            }

            HStack(spacing: 10) {
                Text("Spaces per tab")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ForEach([2, 4], id: \.self) { count in
                        indentCountSegment(count, selected: settingsStore.indentSpaceCount == count) {
                            settingsStore.indentSpaceCount = count
                        }
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.055))
            )
            .opacity(settingsStore.indentUsesSpaces ? 1 : 0.35)
            .disabled(!settingsStore.indentUsesSpaces)
        }
    }

    private var codeBlockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Block")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))

            HStack(spacing: 10) {
                Text("Theme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 0)

                Menu {
                    ForEach(AppSettingsStore.codeThemes) { theme in
                        Button {
                            settingsStore.codeTheme = theme.id
                        } label: {
                            if settingsStore.codeTheme == theme.id {
                                Label(theme.name, systemImage: "checkmark")
                            } else {
                                Text(theme.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentCodeThemeName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.055))
            )
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))

            toggleRow("Ask before deleting", isOn: $settingsStore.confirmBeforeDelete)
            toggleRow("Launch at login", isOn: $settingsStore.launchAtLogin)

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Quit NotchNotes")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.055))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }

    private func deleteProfileConfirmation(_ profile: NoteProfile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.55))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { pendingDeleteProfile = nil } }

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Delete profile?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("“\(profile.name)” and its notes will be permanently deleted.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("Cancel") {
                        withAnimation(.easeOut(duration: 0.12)) { pendingDeleteProfile = nil }
                    }
                    .buttonStyle(ConfirmationButtonStyle(destructive: false))
                    .pointingHandCursor()
                    Button("Delete") {
                        store.deleteProfile(profile.id)
                        withAnimation(.easeOut(duration: 0.12)) { pendingDeleteProfile = nil }
                    }
                    .buttonStyle(ConfirmationButtonStyle(destructive: true))
                    .pointingHandCursor()
                }
            }
            .padding(18)
            .frame(width: 210)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.058))
            )
        }
        .transition(.opacity)
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))

            VStack(spacing: 6) {
                ForEach(store.profiles) { profile in
                    profileRow(profile)
                }
            }

            Button {
                store.addProfile(name: "")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Profile")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.055))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }

    private func profileRow(_ profile: NoteProfile) -> some View {
        let isCurrent = profile.id == store.currentProfileID
        return HStack(spacing: 8) {
            Button {
                store.selectProfile(profile.id)
            } label: {
                Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.9 : 0.4))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            TextField("Name", text: nameBinding(profile))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Button {
                withAnimation(.easeOut(duration: 0.12)) { pendingDeleteProfile = profile }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(store.profiles.count <= 1 ? 0.2 : 0.5))
            }
            .buttonStyle(.plain)
            .disabled(store.profiles.count <= 1)
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(isCurrent ? 0.10 : 0.055))
        )
    }

    private func nameBinding(_ profile: NoteProfile) -> Binding<String> {
        Binding(
            get: { store.profiles.first { $0.id == profile.id }?.name ?? profile.name },
            set: { store.renameProfile(profile.id, to: $0) }
        )
    }

    private func indentButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(PopoverTriggerButtonStyle(isSelected: selected))
    }

    private var currentCodeThemeName: String {
        AppSettingsStore.codeThemes.first { $0.id == settingsStore.codeTheme }?.name ?? settingsStore.codeTheme
    }

    private func indentCountSegment(_ count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(selected ? 0.95 : 0.5))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(selected ? 0.16 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture { isOn.wrappedValue.toggle() }

            Spacer(minLength: 0)

            MiniSwitch(isOn: isOn)
                .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.055))
        )
    }
}

/// A small custom switch. Replaces the native `Toggle` so the pointing-hand
/// cursor stays stable — NSSwitch asserts its own arrow cursor during a press,
/// which a SwiftUI cursor modifier can't override until the next mouse move.
struct MiniSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(isOn ? 0.72 : 0.16))
            .frame(width: 38, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .animation(.easeInOut(duration: 0.16), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
    }
}

struct PopoverTriggerButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(foregroundOpacity(configuration: configuration)))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(backgroundOpacity(configuration: configuration)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .pointingHandCursor()
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundOpacity(configuration: Configuration) -> CGFloat {
        if configuration.isPressed {
            return isSelected ? 0.18 : 0.11
        }
        return isSelected ? 0.13 : 0.055
    }

    private func foregroundOpacity(configuration: Configuration) -> CGFloat {
        if configuration.isPressed {
            return 0.74
        }
        return isSelected ? 0.94 : 0.62
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandOnHoverModifier())
    }
}

private struct PointingHandOnHoverModifier: ViewModifier {
    // Re-assert the cursor on every move inside the region (rather than a
    // push/pop stack, which gets corrupted when adjacent hover regions trade
    // enter/exit events out of order and leaves a stale cursor).
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}
