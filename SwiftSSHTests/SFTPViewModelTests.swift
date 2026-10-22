import Foundation
import SwiftUI
import XCTest
@testable import SwiftSSH

@MainActor
final class SFTPViewModelTests: XCTestCase {
    func testFilteringAndSortingKeepFoldersFirstAndUseNaturalNames() async {
        let service = TestSFTPService()
        await service.setDirectory("/home", items: [
            item("file10.txt", size: 10), item(".env", size: 1),
            item("file2.txt", size: 20), item("projects", directory: true)
        ])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        XCTAssertEqual(model.visibleFiles.map(\.name), ["projects", "file2.txt", "file10.txt"])

        model.showsHiddenFiles = true
        XCTAssertEqual(model.visibleFiles.count, 4)
        model.searchText = "  FILE  "
        XCTAssertEqual(model.visibleFiles.map(\.name), ["file2.txt", "file10.txt"])
        model.searchText = ""
        model.sortOrder = .size
        XCTAssertEqual(model.visibleFiles.map(\.name), ["projects", "file2.txt", "file10.txt", ".env"])
        model.sortOrder = .modified
        XCTAssertEqual(model.visibleFiles.first?.name, "projects")
    }

    func testFailedNavigationKeepsFilesPathSearchAndHistoryUntilRetrySucceeds() async {
        let service = TestSFTPService()
        let original = item("original.txt")
        await service.setDirectory("/home", items: [original])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        XCTAssertTrue(model.pathHistory.isEmpty)
        model.searchText = "original"

        await model.navigate(to: "/denied")
        XCTAssertEqual(model.currentPath, "/home")
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.searchText, "original")
        XCTAssertTrue(model.pathHistory.isEmpty)
        XCTAssertNotNil(model.directoryError)

        await service.setDirectory("/denied", items: [])
        await model.retryDirectory()
        XCTAssertEqual(model.currentPath, "/denied")
        XCTAssertEqual(model.pathHistory, ["/home"])
        XCTAssertTrue(model.searchText.isEmpty)
        XCTAssertTrue(model.files.isEmpty)
        XCTAssertNil(model.directoryError)
    }

    func testFailedBackCanBeRetriedWithoutAddingAnotherHistoryEntry() async {
        let service = TestSFTPService()
        await service.setDirectory("/home", items: [])
        await service.setDirectory("/other", items: [])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        await model.navigate(to: "/other")
        await service.removeDirectory("/home")
        await model.goBack()
        XCTAssertEqual(model.currentPath, "/other")
        XCTAssertEqual(model.pathHistory, ["/home"])
        await service.setDirectory("/home", items: [])
        await model.retryDirectory()
        XCTAssertEqual(model.currentPath, "/home")
        XCTAssertTrue(model.pathHistory.isEmpty)
    }

    func testInitialFailureHasRetryAndDoesNotEnableMutations() async {
        let service = TestSFTPService()
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        XCTAssertFalse(model.hasLoadedInitialDirectory)
        XCTAssertFalse(model.isBusy)
        XCTAssertNotNil(model.directoryError)
        model.newFolderName = "folder"
        await model.createDirectory()
        let callsBeforeRetry = await service.mutations
        XCTAssertTrue(callsBeforeRetry.isEmpty)
        await service.setDirectory("/home", items: [])
        await model.retryDirectory()
        XCTAssertTrue(model.hasLoadedInitialDirectory)
        XCTAssertNil(model.directoryError)
    }

    func testInvalidAndExistingNamesNeverReachRemoteWrites() async {
        let service = TestSFTPService()
        await service.setDirectory("/home", items: [item(".env")])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        for name in ["", ".", "..", "../escape", "nested/folder", "bad\0name", ".env"] {
            model.newFolderName = name
            await model.createDirectory()
            XCTAssertNotNil(model.error, name)
            model.error = nil
        }
        await model.upload(url: URL(fileURLWithPath: "/tmp/.env"))
        XCTAssertNotNil(model.error)
        let calls = await service.mutations
        XCTAssertTrue(calls.isEmpty)
        model.newFolderName = " 新目录 "
        await model.createDirectory()
        let created = await service.mutations
        XCTAssertEqual(created, ["mkdir:/home/新目录"])
        XCTAssertEqual(model.newFolderName, "")
    }

    func testDownloadIsExportableAndDoesNotOverwriteExistingLocalFiles() async throws {
        let service = TestSFTPService()
        let model = SFTPViewModel(service: service)
        let name = "SFTP-test-\(UUID().uuidString).txt"
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let existing = documents.appendingPathComponent(name)
        try Data("keep".utf8).write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }
        let remote = item(name)
        await model.download(item: remote)
        let first = try XCTUnwrap(model.downloadedFile?.url)
        XCTAssertEqual(first.lastPathComponent, name)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "remote data")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep")

        // Sheet dismissal clears its binding before invoking onDismiss.
        model.downloadedFile = nil
        model.discardDownload()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        await model.download(item: remote)
        let second = try XCTUnwrap(model.downloadedFile?.url)
        defer { model.discardDownload() }
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(model.isTransferring)
    }

    func testFailedTransferClearsBusyStateAndRetainsErrorAfterRefresh() async {
        let service = TestSFTPService()
        await service.setDirectory("/home", items: [])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        await service.failTransfers()
        await model.upload(url: URL(fileURLWithPath: "/tmp/valid.txt"))
        XCTAssertFalse(model.isBusy)
        XCTAssertNotNil(model.error)
        await model.download(item: item("valid.txt"))
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.downloadedFile)
        XCTAssertNotNil(model.error)
    }

    func testConcurrentNavigationCannotMixOneDirectoryPathWithAnotherListing() async {
        let service = TestSFTPService()
        await service.setDirectory("/home", items: [])
        await service.setDirectory("/slow", items: [item("slow.txt", path: "/slow")])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        let started = expectation(description: "Listing suspended")
        await service.suspendNextListing(started: started)
        let request = Task { await model.navigate(to: "/slow") }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(model.isLoading)
        await model.navigate(to: "/ignored")
        await model.createDirectory()
        await service.resumeListing()
        await request.value
        XCTAssertEqual(model.currentPath, "/slow")
        XCTAssertEqual(model.files.map(\.path), ["/slow/slow.txt"])
        XCTAssertEqual(model.pathHistory, ["/home"])
    }

    func testModifiedSortIsNewestFirstWithDeterministicNameTies() {
        let older = item("older", modified: Date(timeIntervalSince1970: 1))
        let newer = item("newer", modified: Date(timeIntervalSince1970: 2))
        let unknown = item("unknown")
        XCTAssertEqual([unknown, older, newer].sorted(by: SFTPFileItem.SortOrder.modified.precedes),
                       [newer, older, unknown])
        XCTAssertEqual([item("z"), item("a", size: 0)].sorted(by: SFTPFileItem.SortOrder.size.precedes).map(\.name),
                       ["a", "z"])
    }

    func testFileBrowserRendersAtNarrowWidthAndLargeText() async throws {
        let service = TestSFTPService()
        await service.setDirectory("/home", items: [
            item("project-with-a-long-name", directory: true),
            item("production-configuration-backup-2026-10-23.json", size: 4096,
                 modified: Date(timeIntervalSince1970: 1792689687)),
            item(".env", size: 128)
        ])
        let model = SFTPViewModel(service: service)
        await model.loadInitialDirectory()
        for (name, size, scheme) in [("Files-Narrow-Light", DynamicTypeSize.large, ColorScheme.light),
                                     ("Files-Large-Text-Dark", .accessibility3, .dark)] {
            let root = SFTPBrowserView(viewModel: model)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
                .environment(\.dynamicTypeSize, size)
                .preferredColorScheme(scheme)
            try await snapshot(root, named: name)
            XCTAssertFalse(model.isBusy)
            XCTAssertEqual(model.visibleFiles.count, 2)
        }
    }

    private func item(_ name: String, directory: Bool = false, size: UInt64? = nil,
                      modified: Date? = nil, path: String = "/home") -> SFTPFileItem {
        SFTPFileItem(name: name, path: path + "/" + name, isDirectory: directory,
                     size: size, modifiedDate: modified, permissions: nil)
    }
}

private actor TestSFTPService: SFTPServicing {
    private var directories: [String: [SFTPFileItem]] = [:]
    private(set) var mutations: [String] = []
    private var transfersFail = false
    private var listingStarted: XCTestExpectation?
    private var listingContinuation: CheckedContinuation<Void, Never>?

    func setDirectory(_ path: String, items: [SFTPFileItem]) { directories[path] = items }
    func removeDirectory(_ path: String) { directories[path] = nil }
    func failTransfers() { transfersFail = true }
    func suspendNextListing(started: XCTestExpectation) { listingStarted = started }
    func resumeListing() { listingContinuation?.resume(); listingContinuation = nil }

    func getHomePath() async throws -> String { "/home" }
    func listDirectory(path: String) async throws -> [SFTPFileItem] {
        if let started = listingStarted {
            listingStarted = nil
            await withCheckedContinuation { continuation in
                listingContinuation = continuation
                started.fulfill()
            }
        }
        guard let items = directories[path] else { throw CocoaError(.fileReadNoPermission) }
        return items
    }
    func downloadFile(remotePath: String, localURL: URL) async throws {
        if transfersFail { throw CocoaError(.fileReadNoPermission) }
        try Data("remote data".utf8).write(to: localURL)
    }
    func uploadFile(localURL: URL, remotePath: String) async throws {
        if transfersFail { throw CocoaError(.fileWriteNoPermission) }
        mutations.append("upload:" + remotePath)
    }
    func deleteFile(path: String) async throws { mutations.append("delete:" + path) }
    func deleteDirectory(path: String) async throws { mutations.append("rmdir:" + path) }
    func createDirectory(path: String) async throws { mutations.append("mkdir:" + path) }
}
