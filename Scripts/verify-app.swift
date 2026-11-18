#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Usage: swift Scripts/verify-app.swift path/to/NotchNotes.app [screenshot.png]
let arguments = CommandLine.arguments
guard (2...3).contains(arguments.count) else {
    fputs("Usage: swift Scripts/verify-app.swift path/to/NotchNotes.app [screenshot.png]\n", stderr)
    exit(1)
}

let appURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let process = Process()
process.executableURL = appURL.appendingPathComponent("Contents/MacOS/NotchNotes")
let originalPointer = CGEvent(source: nil)?.location

func windows() -> [[String: Any]] {
    let allWindows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] ?? []
    return allWindows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == process.processIdentifier
    }
}

func bounds(of window: [String: Any]) -> CGRect? {
    guard let values = window[kCGWindowBounds as String] as? [String: CGFloat],
          let x = values["X"], let y = values["Y"],
          let width = values["Width"], let height = values["Height"] else { return nil }
    return CGRect(x: x, y: y, width: width, height: height)
}

func waitForWindow(where predicate: (CGRect) -> Bool) -> [String: Any]? {
    let deadline = Date().addingTimeInterval(10)
    while process.isRunning && Date() < deadline {
        if let window = windows().first(where: { bounds(of: $0).map(predicate) ?? false }) {
            return window
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return nil
}

func verify() throws {
    try process.run()
    defer {
        if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        if process.isRunning { process.terminate() }
    }

    guard let panel = waitForWindow(where: { $0.width > 60 }),
          let panelBounds = bounds(of: panel) else {
        throw NSError(domain: "NotchNotesVerification", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The app exited or did not display its notch panel."
        ])
    }
    CGWarpMouseCursorPosition(CGPoint(x: panelBounds.midX, y: panelBounds.midY))
    guard let drawer = waitForWindow(where: { $0.width > 100 && $0.height > 100 }),
          let windowID = drawer[kCGWindowNumber as String] as? Int else {
        throw NSError(domain: "NotchNotesVerification", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "The notes panel did not expand on hover."
        ])
    }

    // Wait for the reveal animation before capturing the rendered editor.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    if arguments.count == 3 {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(windowID), arguments[2]]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0 else {
            throw NSError(domain: "NotchNotesVerification", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not capture the notes panel."
            ])
        }
    }
    guard process.isRunning else {
        throw NSError(domain: "NotchNotesVerification", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "The app exited after expanding its notes panel."
        ])
    }
    print("Verified: app launches and expands its notes panel.")
}

do {
    try verify()
} catch {
    fputs("Verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
