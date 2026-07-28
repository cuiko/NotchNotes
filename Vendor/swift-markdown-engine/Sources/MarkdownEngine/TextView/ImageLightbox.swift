//
//  ImageLightbox.swift
//  MarkdownEngine
//
//  Full-screen preview for a rendered image embed. Presents the image centered
//  over a black modal backdrop at its natural size, scaled down to fit the
//  screen when it would otherwise overflow. Dismissed by a click or Escape.
//

import AppKit

/// Borderless full-screen window hosting the image preview. Becomes key so it
/// can catch Escape, and dismisses on any click.
final class ImageLightboxWindow: NSWindow {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            dismissSelf()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dismissSelf()
    }

    private func dismissSelf() {
        onDismiss?()
        orderOut(nil)
        close()
    }
}

enum ImageLightbox {
    /// Held strongly while visible so ARC doesn't tear the window down early.
    private static var window: ImageLightboxWindow?

    static func present(_ image: NSImage, on screen: NSScreen?) {
        dismiss()
        guard let screen = screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame

        let window = ImageLightboxWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.onDismiss = { ImageLightbox.window = nil }

        let container = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        container.autoresizingMask = [.width, .height]

        // Natural size, scaled down (never up) to fit the screen with a margin.
        let margin: CGFloat = 40
        let maxWidth = max(1, screenFrame.width - margin * 2)
        let maxHeight = max(1, screenFrame.height - margin * 2)
        let natural = image.size
        let fitScale = min(1, min(maxWidth / natural.width, maxHeight / natural.height))
        let displaySize = NSSize(width: natural.width * fitScale, height: natural.height * fitScale)

        let imageView = NSImageView(frame: NSRect(
            x: (screenFrame.width - displaySize.width) / 2,
            y: (screenFrame.height - displaySize.height) / 2,
            width: displaySize.width,
            height: displaySize.height
        ))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        container.addSubview(imageView)

        window.contentView = container
        Self.window = window

        window.setFrame(screenFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func dismiss() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
