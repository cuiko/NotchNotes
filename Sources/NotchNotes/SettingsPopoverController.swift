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
    private var panel: SettingsPopoverPanel?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var suppressShowUntil: Date?
    private let contentSize = NSSize(width: 238, height: 248)

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        super.init()
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

        let view = SettingsPopoverView(settingsStore: settingsStore)
        let host = FirstMouseHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: contentSize)
        host.wantsLayer = true
        panel.contentView = host

        self.panel = panel
        let finalOrigin = origin(relativeTo: parentWindow)
        panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 8))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }
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
        if suppressImmediateReopen {
            suppressShowUntil = Date(timeIntervalSinceNow: 0.25)
        }
        let finalOrigin = NSPoint(x: panel.frame.minX, y: panel.frame.minY + 8)

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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(finalOrigin)
        }

        panel.perform(#selector(NSWindow.close), with: nil, afterDelay: 0.13)
    }

    private func origin(relativeTo parentWindow: NSWindow?) -> NSPoint {
        let parentFrame = parentWindow?.frame
            ?? NotchGeometry.targetScreen()?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let screenFrame = parentWindow?.screen?.frame
            ?? NotchGeometry.targetScreen()?.frame
            ?? NSScreen.main?.frame
            ?? parentFrame

        let preferredOrigin = NSPoint(
            x: parentFrame.maxX - contentSize.width - 22,
            y: parentFrame.maxY - contentSize.height - 68
        )

        return NSPoint(
            x: min(max(preferredOrigin.x, screenFrame.minX + 10), screenFrame.maxX - contentSize.width - 10),
            y: min(max(preferredOrigin.y, screenFrame.minY + 10), screenFrame.maxY - contentSize.height - 10)
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
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

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

            VStack(alignment: .leading, spacing: 8) {
                Text("General")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))

                HStack(spacing: 10) {
                    Text("Ask before deleting")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize()
                        .contentShape(Rectangle())
                        .onTapGesture { settingsStore.confirmBeforeDelete.toggle() }

                    Spacer(minLength: 0)

                    MiniSwitch(isOn: $settingsStore.confirmBeforeDelete)
                        .pointingHandCursor()
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.055))
                )

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
        .padding(14)
        .frame(width: 238, height: 248)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.045, green: 0.045, blue: 0.052).opacity(0.98))
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)
        .scaleEffect(appeared ? 1 : 0.965, anchor: .topTrailing)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: appeared)
        .onAppear {
            appeared = true
        }
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
