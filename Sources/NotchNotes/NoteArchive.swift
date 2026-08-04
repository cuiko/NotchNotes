import Foundation

/// Exports the current profile's tabs to a portable `.zip` (Markdown notes +
/// referenced images) and imports such a zip back into a brand-new profile.
///
/// Zip layout:
/// ```
/// <archive>.zip
/// ├── notes/   NN-<title>.md   (one file per tab, raw Markdown)
/// └── images/  <UUID>.png      (assets referenced by ![[name|UUID]] embeds)
/// ```
enum NoteArchive {
    struct ImportResult {
        let name: String
        let tabTexts: [String]
    }

    // MARK: - Export

    static func export(profileName: String, tabs: [NoteTab], imageStore: LocalImageStore, to destination: URL) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("NotchNotesExport-\(UUID().uuidString)", isDirectory: true)
        let staging = temp.appendingPathComponent("NotchNotes", isDirectory: true)
        let notesDir = staging.appendingPathComponent("notes", isDirectory: true)
        let imagesDir = staging.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        var usedNames = Set<String>()
        for (index, tab) in tabs.enumerated() {
            let filename = noteFilename(for: tab.text, index: index, used: &usedNames)
            try tab.text.write(to: notesDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }

        for ref in referencedImages(in: tabs.map(\.text)) {
            guard let source = imageStore.exportImageURL(forID: ref.id) else { continue }
            try? fm.copyItem(at: source, to: imagesDir.appendingPathComponent("\(ref.id).png"))
        }

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        // Strip extended attributes so the zip doesn't carry AppleDouble `._`
        // sidecar files, then archive notes/ + images/ at the zip root. `zip`
        // (unlike `ditto`) doesn't emit those sidecars.
        try? runProcess("/usr/bin/xattr", ["-rc", staging.path])
        try runProcess("/usr/bin/zip", ["-r", "-X", "-q", destination.path, "notes", "images"], workingDirectory: staging)
    }

    // MARK: - Import

    static func importArchive(at url: URL, imageStore: LocalImageStore) throws -> ImportResult {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("NotchNotesImport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        try runProcess("/usr/bin/ditto", ["-x", "-k", url.path, temp.path])

        // Search recursively so the layout is robust regardless of how the zip
        // was produced (with or without a wrapping folder).
        let all = ((fm.enumerator(at: temp, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [])
            // Ignore macOS AppleDouble/resource-fork cruft some zips carry.
            .filter { !$0.path.contains("__MACOSX") && !$0.lastPathComponent.hasPrefix("._") }
        let mdFiles = all
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let pngFiles = all.filter { $0.pathExtension.lowercased() == "png" }

        let tabTexts = mdFiles.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard !tabTexts.isEmpty else {
            throw NoteArchiveError.noNotesFound
        }

        let displayNames = Dictionary(
            referencedImages(in: tabTexts).map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        for png in pngFiles {
            let id = png.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: png) else { continue }
            imageStore.importImage(id: id, displayName: displayNames[id] ?? id, pngData: data)
        }

        return ImportResult(name: url.deletingPathExtension().lastPathComponent, tabTexts: tabTexts)
    }

    // MARK: - Helpers

    private static let embedRegex = try! NSRegularExpression(pattern: #"!\[\[([^\]]*)\]\]"#)

    /// Extracts `(id, displayName)` for every `![[name|UUID]]` embed. Embeds
    /// without a `|UUID` part (there's no stored asset to move) are skipped.
    private static func referencedImages(in texts: [String]) -> [(id: String, displayName: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for text in texts {
            let ns = text as NSString
            for match in embedRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: match.range(at: 1))
                let parts = inner.components(separatedBy: "|")
                guard parts.count >= 2 else { continue }
                let id = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                result.append((id, name.isEmpty ? id : name))
            }
        }
        return result
    }

    private static func noteFilename(for text: String, index: Int, used: inout Set<String>) -> String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        var title = firstLine.trimmingCharacters(in: .whitespaces)
        // Drop leading Markdown markers (heading/list/quote/checkbox) then any
        // filesystem-unfriendly characters.
        title = title.replacingOccurrences(of: #"^[#>\-\*•\d\.\[\]xX\s]+"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"[/\\:*?\"<>|]"#, with: "-", options: .regularExpression)
        if title.count > 40 { title = String(title.prefix(40)).trimmingCharacters(in: .whitespaces) }
        if title.isEmpty { title = "note" }

        let base = String(format: "%02d-%@", index + 1, title)
        var name = "\(base).md"
        var suffix = 1
        while used.contains(name) {
            name = "\(base)-\(suffix).md"
            suffix += 1
        }
        used.insert(name)
        return name
    }

    private static func runProcess(_ executable: String, _ arguments: [String], workingDirectory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NoteArchiveError.ditto(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum NoteArchiveError: LocalizedError {
    case noNotesFound
    case ditto(String)

    var errorDescription: String? {
        switch self {
        case .noNotesFound:
            return "No Markdown notes were found in that archive."
        case .ditto(let message):
            return message.isEmpty ? "Archiving failed." : message
        }
    }
}
