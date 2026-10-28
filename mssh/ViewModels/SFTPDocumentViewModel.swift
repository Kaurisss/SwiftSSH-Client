import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class SFTPDocumentViewModel {
    let item: SFTPFileItem
    var text = ""
    private(set) var snapshot: SFTPDocumentSnapshot?
    private(set) var document: SFTPTextDocument?
    private(set) var previewURL: URL?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var saveNeedsVerification = false
    var error: String?
    private let service: any SFTPDocumentServicing
    @ObservationIgnored private var temporaryDirectory: URL?

    var isDirty: Bool { document.map { text != $0.text } ?? false }
    var canSave: Bool { isDirty && !isLoading && !isSaving && !saveNeedsVerification }
    var isPreview: Bool {
        guard let type = UTType(filenameExtension: (item.name as NSString).pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    init(item: SFTPFileItem, service: any SFTPDocumentServicing) {
        self.item = item
        self.service = service
    }

    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let maximumBytes = isPreview ? 20 * 1024 * 1024 : SFTPTextDocument.maximumBytes
            let result = try await service.readDocument(path: item.path, maximumBytes: maximumBytes)
            try Task.checkCancellation()
            if isPreview {
                previewURL = try writeTemporary(data: result.data)
            } else {
                let decoded = try SFTPTextDocument(data: result.data)
                document = decoded
                text = decoded.text
            }
            snapshot = result
            saveNeedsVerification = false
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func save() async -> Bool {
        guard canSave, let document, let snapshot else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let data = try document.encode(text)
            let result = try await service.saveDocument(path: item.path, data: data, replacing: snapshot)
            self.snapshot = result
            self.document = try SFTPTextDocument(data: result.data)
            return true
        } catch {
            if case SFTPDocumentError.saveUnconfirmed = error { saveNeedsVerification = true }
            self.error = error.localizedDescription
            return false
        }
    }

    func exportDraft() throws -> URL {
        guard let document else { throw SFTPDocumentError.unsupportedPreview }
        return try writeTemporary(data: document.encode(text))
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    private func writeTemporary(data: Data) throws -> URL {
        guard SFTPFileItem.isValidName(item.name) else { throw SFTPDocumentError.unsupportedPreview }
        let directory = temporaryDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSSH-document-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        temporaryDirectory = directory
        let url = directory.appendingPathComponent(item.name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
