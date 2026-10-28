import Foundation
import XCTest
@testable import SwiftSSH

@MainActor
final class SFTPDocumentViewModelTests: XCTestCase {
    func testLoadDecodesTextAndStartsClean() async {
        let original = snapshot(Data([0xEF, 0xBB, 0xBF]) + Data("café\r\n中文\r\n".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        let model = model(service)

        await model.load()

        XCTAssertEqual(model.text, "café\n中文\n")
        XCTAssertEqual(model.document?.text, model.text)
        XCTAssertEqual(model.document?.lineEnding, "\r\n")
        XCTAssertEqual(model.snapshot, original)
        XCTAssertFalse(model.isDirty)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
        let reads = await service.reads
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads.first?.path, "/home/notes.txt")
        XCTAssertEqual(reads.first?.maximumBytes, SFTPTextDocument.maximumBytes)
    }

    func testEditingAndRestoringOriginalTextUpdatesDirtyState() async {
        let service = TestSFTPDocumentService(snapshot: snapshot(Data("original".utf8)))
        let model = model(service)
        await model.load()

        model.text = "draft"
        XCTAssertTrue(model.isDirty)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.document?.text, "original")

        model.text = "original"
        XCTAssertFalse(model.isDirty)
        XCTAssertFalse(model.canSave)
        let saved = await model.save()
        XCTAssertFalse(saved)
        let saves = await service.saves
        XCTAssertTrue(saves.isEmpty)
    }

    func testSavePreservesFormatAndUpdatesBaselineForNextSave() async {
        let original = snapshot(Data("old\r\ntext".utf8))
        let updated = snapshot(Data("new\r\ntext".utf8), modifiedAt: 2)
        let service = TestSFTPDocumentService(snapshot: original)
        await service.setSaveResult(.success(updated))
        let model = model(service)
        await model.load()
        model.text = "new\ntext"

        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(model.text, "new\ntext")
        XCTAssertEqual(model.document?.text, "new\ntext")
        XCTAssertEqual(model.snapshot, updated)
        XCTAssertFalse(model.isDirty)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.error)
        let firstSaves = await service.saves
        XCTAssertEqual(firstSaves.count, 1)
        XCTAssertEqual(firstSaves.first?.path, "/home/notes.txt")
        XCTAssertEqual(firstSaves.first?.data, Data("new\r\ntext".utf8))
        XCTAssertEqual(firstSaves.first?.original, original)

        model.text = "old\ntext"
        XCTAssertTrue(model.isDirty)
        model.text = "new\ntext"
        XCTAssertFalse(model.isDirty)
        model.text = "next\ntext"
        await service.setSaveResult(.success(snapshot(Data("next\r\ntext".utf8), modifiedAt: 3)))
        let savedAgain = await model.save()
        XCTAssertTrue(savedAgain)
        let saves = await service.saves
        XCTAssertEqual(saves.count, 2)
        XCTAssertEqual(saves.last?.original, updated)
        XCTAssertEqual(saves.last?.data, Data("next\r\ntext".utf8))
    }

    func testFailedSaveKeepsDraftAndOriginalSnapshot() async {
        let original = snapshot(Data("original".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        await service.setSaveResult(.failure(CocoaError(.fileWriteNoPermission)))
        let model = model(service)
        await model.load()
        model.text = "draft"

        let saved = await model.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(model.text, "draft")
        XCTAssertEqual(model.document?.text, "original")
        XCTAssertEqual(model.snapshot, original)
        XCTAssertTrue(model.isDirty)
        XCTAssertTrue(model.canSave)
        XCTAssertFalse(model.isSaving)
        XCTAssertNotNil(model.error)
        let saves = await service.saves
        XCTAssertEqual(saves.count, 1)
    }

    func testConflictKeepsEditsAndReportsConflict() async {
        let original = snapshot(Data("original".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        await service.setSaveResult(.failure(SFTPDocumentError.conflict))
        let model = model(service)
        await model.load()
        model.text = "my edits"

        let saved = await model.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(model.text, "my edits")
        XCTAssertEqual(model.document?.text, "original")
        XCTAssertEqual(model.snapshot, original)
        XCTAssertTrue(model.isDirty)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.error, SFTPDocumentError.conflict.localizedDescription)
    }

    func testUnconfirmedSaveBlocksFurtherSavesUntilSuccessfulReload() async {
        let original = snapshot(Data("original".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        await service.setSaveResult(.failure(SFTPDocumentError.saveUnconfirmed))
        let model = model(service)
        await model.load()
        model.text = "draft"

        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.text, "draft")
        XCTAssertEqual(model.document?.text, "original")
        XCTAssertEqual(model.snapshot, original)
        XCTAssertTrue(model.isDirty)
        XCTAssertTrue(model.saveNeedsVerification)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.error, SFTPDocumentError.saveUnconfirmed.localizedDescription)

        model.text = "continued draft"
        let retried = await model.save()
        XCTAssertFalse(retried)
        await service.setReadResult(.failure(CocoaError(.fileReadNoPermission)))
        await model.load()
        XCTAssertEqual(model.text, "continued draft")
        XCTAssertTrue(model.saveNeedsVerification)
        XCTAssertFalse(model.canSave)
        let retriedAfterFailure = await model.save()
        XCTAssertFalse(retriedAfterFailure)
        let saves = await service.saves
        XCTAssertEqual(saves.count, 1)

        let remote = snapshot(Data("verified remote".utf8), modifiedAt: 2)
        await service.setReadResult(.success(remote))
        await model.load()
        XCTAssertEqual(model.text, "verified remote")
        XCTAssertEqual(model.snapshot, remote)
        XCTAssertFalse(model.saveNeedsVerification)
        XCTAssertFalse(model.isDirty)
        XCTAssertNil(model.error)
        model.text = "new draft"
        XCTAssertTrue(model.canSave)
        await service.setSaveResult(.success(snapshot(Data("new draft".utf8), modifiedAt: 3)))
        let savedAfterReload = await model.save()
        XCTAssertTrue(savedAfterReload)
        let finalSaves = await service.saves
        XCTAssertEqual(finalSaves.count, 2)
        XCTAssertEqual(finalSaves.last?.original, remote)
    }

    func testFailedReloadKeepsDraftAndBaseline() async {
        let original = snapshot(Data("original".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        let model = model(service)
        await model.load()
        model.text = "unsaved draft"

        await service.setReadResult(.failure(CocoaError(.fileReadNoPermission)))
        await model.load()

        XCTAssertEqual(model.text, "unsaved draft")
        XCTAssertEqual(model.document?.text, "original")
        XCTAssertEqual(model.snapshot, original)
        XCTAssertTrue(model.isDirty)
        XCTAssertTrue(model.canSave)
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.error)
    }

    func testEncodingFailureDoesNotCallSavingService() async {
        let original = snapshot(Data("original".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        let model = model(service)
        await model.load()
        model.text = "draft\0text"

        let saved = await model.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(model.text, "draft\0text")
        XCTAssertEqual(model.document?.text, "original")
        XCTAssertEqual(model.snapshot, original)
        XCTAssertTrue(model.isDirty)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.error, SFTPTextDocumentError.binaryContent.localizedDescription)
        let saves = await service.saves
        XCTAssertTrue(saves.isEmpty)
    }

    func testInitialOpenErrorLeavesNoDocument() async {
        let service = TestSFTPDocumentService(snapshot: snapshot(Data()))
        await service.setReadResult(.failure(CocoaError(.fileReadNoPermission)))
        let model = model(service)

        await model.load()

        XCTAssertNil(model.document)
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.text.isEmpty)
        XCTAssertFalse(model.isDirty)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.error)
        let saved = await model.save()
        XCTAssertFalse(saved)
        let saves = await service.saves
        XCTAssertTrue(saves.isEmpty)
    }

    func testPreviewUsesSeparateBoundedCacheAndRemovesItOnRelease() async throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let service = TestSFTPDocumentService(snapshot: snapshot(bytes))
        var preview: SFTPDocumentViewModel? = SFTPDocumentViewModel(
            item: SFTPFileItem(name: "preview.png", path: "/home/preview.png", isDirectory: false,
                               size: nil, modifiedDate: nil, permissions: nil), service: service)
        await preview?.load()
        let url = try XCTUnwrap(preview?.previewURL)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNil(preview?.document)
        XCTAssertEqual(preview?.canSave, false)
        let reads = await service.reads
        XCTAssertEqual(reads.first?.maximumBytes, 20 * 1024 * 1024)
        preview = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportKeepsDraftFormatWithoutWritingRemoteFile() async throws {
        let original = snapshot(Data([0xEF, 0xBB, 0xBF]) + Data("old\r\n".utf8))
        let service = TestSFTPDocumentService(snapshot: original)
        let model = model(service)
        await model.load()
        model.text = "draft\n"
        let url = try model.exportDraft()
        XCTAssertEqual(try Data(contentsOf: url), Data([0xEF, 0xBB, 0xBF]) + Data("draft\r\n".utf8))
        XCTAssertTrue(model.isDirty)
        let saves = await service.saves
        XCTAssertTrue(saves.isEmpty)
    }

    private func model(_ service: TestSFTPDocumentService) -> SFTPDocumentViewModel {
        SFTPDocumentViewModel(
            item: SFTPFileItem(name: "notes.txt", path: "/home/notes.txt", isDirectory: false,
                               size: nil, modifiedDate: nil, permissions: nil),
            service: service
        )
    }

    private func snapshot(_ data: Data, modifiedAt: TimeInterval = 1) -> SFTPDocumentSnapshot {
        SFTPDocumentSnapshot(data: data, canonicalPath: "/home/notes.txt", permissions: 0o100644,
                             userID: 1000, groupID: 1000,
                             modifiedAt: Date(timeIntervalSince1970: modifiedAt))
    }
}

private actor TestSFTPDocumentService: SFTPDocumentServicing {
    private var readResult: Result<SFTPDocumentSnapshot, Error>
    private var saveResult: Result<SFTPDocumentSnapshot, Error> = .failure(CocoaError(.fileWriteUnknown))
    private(set) var reads: [(path: String, maximumBytes: Int)] = []
    private(set) var saves: [(path: String, data: Data, original: SFTPDocumentSnapshot)] = []

    init(snapshot: SFTPDocumentSnapshot) {
        readResult = .success(snapshot)
    }

    func setReadResult(_ result: Result<SFTPDocumentSnapshot, Error>) { readResult = result }
    func setSaveResult(_ result: Result<SFTPDocumentSnapshot, Error>) { saveResult = result }

    func readDocument(path: String, maximumBytes: Int) async throws -> SFTPDocumentSnapshot {
        reads.append((path, maximumBytes))
        return try readResult.get()
    }

    func saveDocument(path: String, data: Data, replacing original: SFTPDocumentSnapshot) async throws -> SFTPDocumentSnapshot {
        saves.append((path, data, original))
        return try saveResult.get()
    }
}
