import Foundation
import Citadel
import NIO

protocol SFTPServicing: SFTPDocumentServicing {
    func listDirectory(path: String) async throws -> [SFTPFileItem]
    func getHomePath() async throws -> String
    func downloadFile(remotePath: String, localURL: URL) async throws
    func uploadFile(localURL: URL, remotePath: String) async throws
    func deleteFile(path: String) async throws
    func deleteDirectory(path: String) async throws
    func createDirectory(path: String) async throws
}

final class SFTPService: SFTPServicing {
    let client: SSHClient

    init(client: SSHClient) {
        self.client = client
    }

    func listDirectory(path: String) async throws -> [SFTPFileItem] {
        try await client.withSFTP { sftp in
            let names = try await sftp.listDirectory(atPath: path)
            var items: [SFTPFileItem] = []

            for name in names {
                for component in name.components {
                    let filename = component.filename
                    // Skip . and ..
                    if !SFTPFileItem.isValidName(filename) {
                        continue
                    }

                    let fullPath: String
                    if path.hasSuffix("/") {
                        fullPath = path + filename
                    } else {
                        fullPath = path + "/" + filename
                    }

                    let isDirectory = Self.isDirectory(permissions: component.attributes.permissions)

                    let modifiedDate = component.attributes.accessModificationTime?.modificationTime

                    let item = SFTPFileItem(
                        name: filename,
                        path: fullPath,
                        isDirectory: isDirectory,
                        size: component.attributes.size,
                        modifiedDate: modifiedDate,
                        permissions: component.attributes.permissions
                    )
                    items.append(item)
                }
            }

            return items
        }
    }

    func downloadFile(remotePath: String, localURL: URL) async throws {
        try Task.checkCancellation()
        let temporary = localURL.deletingLastPathComponent().appendingPathComponent(".SwiftSSH-\(UUID().uuidString)")
        try Data().write(to: temporary, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try await client.withSFTP { sftp in
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await sftp.withFile(filePath: remotePath, flags: .read) { file in
                    let expectedSize = try await file.readAttributes().size
                    var offset: UInt64 = 0
                    while true {
                        try Task.checkCancellation()
                        if let expectedSize, offset >= expectedSize { break }
                        let length = UInt32(min(32_000, expectedSize.map { $0 - offset } ?? 32_000))
                        let chunk = try await file.read(from: offset, length: length)
                        guard chunk.readableBytes > 0 else {
                            if let expectedSize, offset < expectedSize { throw SFTPTransferError.incompleteDownload }
                            break
                        }
                        try output.write(contentsOf: chunk.data)
                        offset += UInt64(chunk.readableBytes)
                    }
                }
            } onCancel: {
                // Close only this transfer's SFTP channel; the terminal stays connected.
                Task { try? await sftp.close() }
            }
        }
        try output.close()
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: localURL.path) {
            _ = try FileManager.default.replaceItemAt(localURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: localURL)
        }
    }

    func uploadFile(localURL: URL, remotePath: String) async throws {
        try Task.checkCancellation()
        let input = try FileHandle(forReadingFrom: localURL)
        defer { try? input.close() }
        let sftp = try await client.openSFTP()
        do {
            try Task.checkCancellation()
            // Exclusive creation protects existing files and establishes cleanup ownership.
            let file = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .forceCreate])
            do {
                try await withTaskCancellationHandler {
                    var offset: UInt64 = 0
                    while true {
                        try Task.checkCancellation()
                        guard let data = try input.read(upToCount: 32_000), !data.isEmpty else { break }
                        try await file.write(ByteBuffer(data: data), at: offset)
                        offset += UInt64(data.count)
                    }
                    try await file.close()
                    try Task.checkCancellation()
                } onCancel: {
                    Task { try? await sftp.close() }
                }
            } catch {
                try? await file.close()
                do {
                    if Task.isCancelled {
                        // The cancelled channel is closed; remove our partial file on a fresh one.
                        try await self.deleteFile(path: remotePath)
                    } else {
                        try await sftp.remove(at: remotePath)
                    }
                } catch {
                    throw SFTPTransferError.uploadCleanupFailed(remotePath)
                }
                throw error
            }
            try await sftp.close()
        } catch {
            try? await sftp.close()
            throw error
        }
    }

    func deleteFile(path: String) async throws {
        try await client.withSFTP { sftp in
            try await sftp.remove(at: path)
        }
    }

    func deleteDirectory(path: String) async throws {
        try await client.withSFTP { sftp in
            try await sftp.rmdir(at: path)
        }
    }

    func createDirectory(path: String) async throws {
        try await client.withSFTP { sftp in
            try await sftp.createDirectory(atPath: path)
        }
    }

    func getHomePath() async throws -> String {
        try await client.withSFTP { sftp in
            try await sftp.getRealPath(atPath: ".")
        }
    }

    // MARK: - Helpers

    private static func isDirectory(permissions: UInt32?) -> Bool {
        guard let permissions else { return false }
        // S_IFDIR = 0o040000 on POSIX
        return (permissions & 0o170000) == 0o040000
    }
}

enum SFTPTransferError: LocalizedError {
    case incompleteDownload
    case uploadCleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompleteDownload:
            String(localized: "The remote file became shorter during download. Try again.")
        case .uploadCleanupFailed(let path):
            String(localized: "Transfer stopped, but the incomplete remote file could not be removed: \(path)")
        }
    }
}
