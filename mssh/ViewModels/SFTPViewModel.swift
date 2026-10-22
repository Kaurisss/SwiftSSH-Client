import Foundation
import Citadel
import Observation

@Observable
@MainActor
final class SFTPViewModel {
    private(set) var currentPath = "/"
    private(set) var files: [SFTPFileItem] = []
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var pathHistory: [String] = []
    private(set) var directoryError: String?
    private(set) var hasLoadedInitialDirectory = false
    var error: String?
    var searchText = ""
    var showsHiddenFiles = false
    var sortOrder = SFTPFileItem.SortOrder.name

    private(set) var isTransferring = false
    private(set) var transferFileName = ""
    private(set) var transferType: TransferType = .download
    var downloadedFile: DownloadedFile?
    var showNewFolderAlert = false
    var newFolderName = ""
    var showFileImporter = false
    var itemToDelete: SFTPFileItem?
    var showDeleteConfirmation = false

    enum TransferType {
        case download, upload
    }

    struct DownloadedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private let sftpService: any SFTPServicing
    private enum HistoryChange { case append, back, unchanged }
    private var failedNavigation: (path: String, history: HistoryChange)?
    private var downloadDirectory: URL?

    var isBusy: Bool { isLoading || isTransferring || isMutating }

    var visibleFiles: [SFTPFileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter {
            (showsHiddenFiles || !$0.name.hasPrefix("."))
                && (query.isEmpty || $0.name.localizedStandardContains(query))
        }.sorted(by: sortOrder.precedes)
    }

    var breadcrumbs: [PathCrumb] {
        var crumbs = [PathCrumb(name: "/", path: "/")]
        var path = ""
        for component in currentPath.split(separator: "/") {
            path += "/" + component
            crumbs.append(PathCrumb(name: String(component), path: path))
        }
        return crumbs
    }

    convenience init(client: SSHClient) {
        self.init(service: SFTPService(client: client))
    }

    init(service: any SFTPServicing) {
        sftpService = service
    }

    func loadInitialDirectory() async {
        guard !isBusy, !hasLoadedInitialDirectory else { return }
        isLoading = true
        directoryError = nil
        defer { isLoading = false }
        do {
            let home = try await sftpService.getHomePath()
            let entries = try await sftpService.listDirectory(path: home)
            currentPath = home
            files = entries
            hasLoadedInitialDirectory = true
        } catch {
            directoryError = String(localized: "Failed to open home folder: \(error.localizedDescription)")
        }
    }

    func navigate(to path: String) async {
        guard path != currentPath else { return }
        await loadDirectory(at: path, history: .append)
    }

    func goUp() async {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        await navigate(to: parent.isEmpty ? "/" : parent)
    }

    func goBack() async {
        guard let previous = pathHistory.last else { return }
        await loadDirectory(at: previous, history: .back)
    }

    func refresh() async {
        if hasLoadedInitialDirectory {
            await loadDirectory(at: currentPath, history: .unchanged)
        } else {
            await loadInitialDirectory()
        }
    }

    func retryDirectory() async {
        if let failedNavigation {
            await loadDirectory(at: failedNavigation.path, history: failedNavigation.history)
        } else {
            await refresh()
        }
    }

    func download(item: SFTPFileItem) async {
        guard !isBusy, !item.isDirectory, SFTPFileItem.isValidName(item.name) else { return }
        discardDownload()
        isTransferring = true
        transferFileName = item.name
        transferType = .download
        defer { isTransferring = false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(item.name)
            try await sftpService.downloadFile(remotePath: item.path, localURL: url)
            downloadDirectory = directory
            downloadedFile = DownloadedFile(url: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            self.error = String(localized: "Download failed: \(error.localizedDescription)")
        }
    }

    func discardDownload() {
        if let downloadDirectory {
            try? FileManager.default.removeItem(at: downloadDirectory)
        }
        downloadDirectory = nil
        downloadedFile = nil
    }

    func upload(url: URL) async {
        guard !isBusy, hasLoadedInitialDirectory else { return }
        let name = url.lastPathComponent
        guard validateNewName(name) else { return }
        isTransferring = true
        transferFileName = name
        transferType = .upload
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            try await sftpService.uploadFile(localURL: url, remotePath: childPath(name))
        } catch {
            self.error = String(localized: "Upload failed. Existing files are kept; choose a different name and try again. \(error.localizedDescription)")
        }
        isTransferring = false
        await refresh()
    }

    func delete(item: SFTPFileItem) async {
        guard !isBusy, files.contains(where: { $0.path == item.path }) else { return }
        isMutating = true
        defer { itemToDelete = nil }
        do {
            if item.isDirectory {
                try await sftpService.deleteDirectory(path: item.path)
            } else {
                try await sftpService.deleteFile(path: item.path)
            }
        } catch {
            self.error = String(localized: "Delete failed: \(error.localizedDescription)")
        }
        isMutating = false
        await refresh()
    }

    func createDirectory() async {
        guard !isBusy, hasLoadedInitialDirectory else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateNewName(name) else { return }
        isMutating = true
        do {
            try await sftpService.createDirectory(path: childPath(name))
            newFolderName = ""
        } catch {
            self.error = String(localized: "Create folder failed: \(error.localizedDescription)")
        }
        isMutating = false
        await refresh()
    }

    private func validateNewName(_ name: String) -> Bool {
        guard SFTPFileItem.isValidName(name) else {
            error = String(localized: "Enter a name other than . or .., without / or null characters.")
            return false
        }
        guard !files.contains(where: { $0.name == name }) else {
            error = String(localized: "An item with this name already exists. Choose a different name.")
            return false
        }
        return true
    }

    private func childPath(_ name: String) -> String {
        currentPath.hasSuffix("/") ? currentPath + name : currentPath + "/" + name
    }

    @discardableResult
    private func loadDirectory(at path: String, history: HistoryChange) async -> Bool {
        guard !isBusy else { return false }
        isLoading = true
        directoryError = nil
        defer { isLoading = false }
        do {
            let entries = try await sftpService.listDirectory(path: path)
            switch history {
            case .append: pathHistory.append(currentPath)
            case .back: pathHistory.removeLast()
            case .unchanged: break
            }
            if path != currentPath { searchText = "" }
            currentPath = path
            files = entries
            failedNavigation = nil
            return true
        } catch {
            directoryError = String(localized: "Failed to list directory: \(error.localizedDescription)")
            failedNavigation = (path, history)
            return false
        }
    }
}

struct PathCrumb: Identifiable {
    var id: String { path }
    let name: String
    let path: String
}
