import Foundation
import Citadel
import NIO

extension SFTPService {
    func readDocument(path: String, maximumBytes: Int) async throws -> SFTPDocumentSnapshot {
        try await withDocumentChannel { sftp in
            try await withTaskCancellationHandler {
                try await Self.readDocument(sftp: sftp, path: path, maximumBytes: maximumBytes)
            } onCancel: {
                Task { try? await sftp.close() }
            }
        }
    }

    func saveDocument(path: String, data: Data, replacing original: SFTPDocumentSnapshot) async throws -> SFTPDocumentSnapshot {
        guard data.count <= SFTPTextDocument.maximumBytes else { throw SFTPDocumentError.tooLarge }
        return try await withDocumentChannel { sftp in
            guard try await sftp.supportsPosixRename() else { throw SFTPDocumentError.unsafeReplacement }
            guard let permissions = original.permissions, let userID = original.userID,
                  let groupID = original.groupID, permissions & 0o170000 == 0o100000 else {
                throw SFTPDocumentError.unsafeReplacement
            }
            let metadata = try await sftp.lstat(at: path)
            guard metadata.extended.isEmpty else { throw SFTPDocumentError.unsafeReplacement }
            let current = try await Self.readDocument(sftp: sftp, path: path, maximumBytes: SFTPTextDocument.maximumBytes)
            guard current == original else { throw SFTPDocumentError.conflict }
            // Opening without truncate checks the server's write permissions on the original, not just its directory.
            let writable = try await sftp.openFile(filePath: path, flags: .write)
            try await writable.close()
            let parent = (original.canonicalPath as NSString).deletingLastPathComponent
            let temporary = (parent as NSString).appendingPathComponent(".SwiftSSH-edit-\(UUID().uuidString)")
            var ownsTemporary = false
            var commitStarted = false
            do {
                try Task.checkCancellation()
                var attributes = SFTPFileAttributes()
                attributes.permissions = 0o600
                let file = try await sftp.openFile(filePath: temporary, flags: [.write, .create, .forceCreate], attributes: attributes)
                ownsTemporary = true
                do {
                    var offset = 0
                    while offset < data.count {
                        try Task.checkCancellation()
                        let end = min(offset + 32_000, data.count)
                        try await file.write(ByteBuffer(data: data.subdata(in: offset..<end)), at: UInt64(offset))
                        offset = end
                    }
                    var owner = SFTPFileAttributes()
                    owner.uidgid = .init(userId: userID, groupId: groupID)
                    let created = try await file.readAttributes()
                    if created.uidgid != owner.uidgid { try await file.setAttributes(to: owner) }
                    var mode = SFTPFileAttributes()
                    mode.permissions = permissions & 0o7777
                    try await file.setAttributes(to: mode)
                    let finalAttributes = try await file.readAttributes()
                    guard finalAttributes.size == UInt64(data.count), finalAttributes.uidgid == owner.uidgid,
                          finalAttributes.permissions.map({ $0 & 0o7777 }) == (permissions & 0o7777) else {
                        throw SFTPDocumentError.unsafeReplacement
                    }
                    try await file.close()
                } catch {
                    try? await file.close()
                    throw error
                }
                // Recheck after staging, immediately before the only operation that changes the original path.
                let latest = try await Self.readDocument(sftp: sftp, path: path, maximumBytes: SFTPTextDocument.maximumBytes)
                guard latest == original else { throw SFTPDocumentError.conflict }
                try Task.checkCancellation()
                commitStarted = true
                do {
                    try await sftp.posixRename(at: temporary, to: original.canonicalPath)
                } catch let status as SFTPMessage.Status {
                    commitStarted = false
                    throw status
                }
                ownsTemporary = false
                let saved = try await Self.readDocument(sftp: sftp, path: path, maximumBytes: SFTPTextDocument.maximumBytes)
                guard saved.data == data, saved.permissions == permissions,
                      saved.userID == userID, saved.groupID == groupID else {
                    throw SFTPDocumentError.saveUnconfirmed
                }
                return saved
            } catch {
                if ownsTemporary {
                    do { try await self.deleteFile(path: temporary) }
                    catch {
                        if !commitStarted { throw SFTPDocumentError.stagingCleanupFailed(temporary) }
                    }
                }
                // A lost response may follow a successful rename. Keep the draft and require a reload.
                if commitStarted { throw SFTPDocumentError.saveUnconfirmed }
                throw error
            }
        }
    }

    private static func readDocument(sftp: SFTPClient, path: String, maximumBytes: Int) async throws -> SFTPDocumentSnapshot {
        try Task.checkCancellation()
        guard maximumBytes > 0 else { throw SFTPDocumentError.tooLarge }
        let before = try await sftp.lstat(at: path)
        guard before.permissions.map({ $0 & 0o170000 }) == 0o100000 else {
            throw SFTPDocumentError.notRegularFile
        }
        guard let size = before.size, size <= UInt64(maximumBytes) else { throw SFTPDocumentError.tooLarge }
        let canonicalPath = try await sftp.getRealPath(atPath: path)
        return try await sftp.withFile(filePath: path, flags: .read) { file in
            let opened = try await file.readAttributes()
            guard sameVersion(before, opened) else { throw SFTPDocumentError.changedDuringRead }
            var data = Data()
            while true {
                try Task.checkCancellation()
                let length = min(32_000, maximumBytes - data.count + 1)
                let chunk = try await file.read(from: UInt64(data.count), length: UInt32(length))
                if chunk.readableBytes == 0 { break }
                guard chunk.readableBytes <= maximumBytes - data.count else { throw SFTPDocumentError.tooLarge }
                data.append(chunk.data)
            }
            let after = try await file.readAttributes()
            let atPath = try await sftp.lstat(at: path)
            let finalPath = try await sftp.getRealPath(atPath: path)
            guard data.count == Int(size), sameVersion(before, after), sameVersion(before, atPath),
                  finalPath == canonicalPath else { throw SFTPDocumentError.changedDuringRead }
            return SFTPDocumentSnapshot(data: data, canonicalPath: canonicalPath,
                                        permissions: before.permissions, userID: before.uidgid?.userId,
                                        groupID: before.uidgid?.groupId,
                                        modifiedAt: before.accessModificationTime?.modificationTime)
        }
    }

    private func withDocumentChannel<T>(_ operation: (SFTPClient) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let sftp = try await client.openSFTP()
        do {
            let result = try await operation(sftp)
            try? await sftp.close()
            return result
        } catch {
            // Channel cleanup must not hide a conflict or an uncertain commit.
            try? await sftp.close()
            throw error
        }
    }

    private static func sameVersion(_ lhs: SFTPFileAttributes, _ rhs: SFTPFileAttributes) -> Bool {
        lhs.size == rhs.size && lhs.permissions == rhs.permissions && lhs.uidgid == rhs.uidgid
            && lhs.accessModificationTime?.modificationTime == rhs.accessModificationTime?.modificationTime
    }
}
