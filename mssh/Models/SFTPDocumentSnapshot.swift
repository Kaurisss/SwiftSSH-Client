import Foundation

protocol SFTPDocumentServicing: Sendable {
    func readDocument(path: String, maximumBytes: Int) async throws -> SFTPDocumentSnapshot
    func saveDocument(path: String, data: Data, replacing original: SFTPDocumentSnapshot) async throws -> SFTPDocumentSnapshot
}

struct SFTPDocumentSnapshot: Sendable, Equatable {
    let data: Data
    let canonicalPath: String
    let permissions: UInt32?
    let userID: UInt32?
    let groupID: UInt32?
    let modifiedAt: Date?
}

enum SFTPDocumentError: LocalizedError {
    case tooLarge
    case notRegularFile
    case changedDuringRead
    case conflict
    case unsafeReplacement
    case saveUnconfirmed
    case stagingCleanupFailed(String)
    case unsupportedPreview

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            String(localized: "This file is too large to open here. Download it instead.")
        case .notRegularFile:
            String(localized: "Only regular files can be opened here. Links and special files are not supported.")
        case .changedDuringRead:
            String(localized: "The file changed while it was being read. Open it again.")
        case .conflict:
            String(localized: "The remote file has changed. Your edits are kept. Export your draft or reload the remote file.")
        case .unsafeReplacement:
            String(localized: "This server does not support safe replacement of this file. Export your draft instead.")
        case .saveUnconfirmed:
            String(localized: "The save result could not be confirmed. Your edits are kept. Check the remote file before saving again.")
        case .stagingCleanupFailed(let path):
            String(localized: "The original file was kept, but a temporary file could not be removed: \(path)")
        case .unsupportedPreview:
            String(localized: "This file cannot be previewed. Download it instead.")
        }
    }
}
