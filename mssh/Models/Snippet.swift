import Foundation
import SwiftData

extension Notification.Name {
    /// Broadcast by the iOS keyboard accessory bar (which can't present
    /// SwiftUI sheets directly). The active `TerminalSessionView` listens
    /// for this and shows the snippet picker.
    static let openSnippetPicker = Notification.Name("mssh.openSnippetPicker")
}

/// User-saved command snippet (e.g. "tail -f /var/log/syslog"). Triggered
/// from the terminal accessory bar and pushed to the active SSH session via
/// `SSHTerminalBridge.sendToSSH`.
@Model
final class Snippet {
    /// Stable identifier for cross-device sync.
    var syncID: String = UUID().uuidString

    var label: String = ""
    var command: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date? = nil
    var useCount: Int = 0

    init(label: String, command: String) {
        self.label = label
        self.command = command
        self.createdAt = Date()
        self.syncID = UUID().uuidString
    }

    var displayLabel: String {
        label.isEmpty ? String(localized: "Untitled") : label
    }

    static func filtered(_ snippets: [Snippet], query: String) -> [Snippet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snippets }
        return snippets.filter {
            $0.label.localizedStandardContains(query) || $0.command.localizedStandardContains(query)
        }
    }

    static func save(_ existing: Snippet?, label: String, command: String, in context: ModelContext) throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyCommand
        }
        let target = existing ?? Snippet(label: "", command: "")
        let previous = (target.label, target.command)
        target.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        target.command = command
        if existing == nil { context.insert(target) }
        do {
            try context.save()
        } catch {
            (target.label, target.command) = previous
            if existing == nil { context.delete(target) }
            throw error
        }
    }

    enum ValidationError: LocalizedError {
        case emptyCommand

        var errorDescription: String? { String(localized: "Enter a command before saving.") }
    }
}
