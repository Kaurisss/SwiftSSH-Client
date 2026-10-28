import Citadel
import Foundation
import Observation
import SwiftData
import XCTest
@testable import SwiftSSH

@MainActor
final class SSHIntegrationTests: XCTestCase {
    func testKeyAuthenticationAndSFTPRoundTripKeepsExistingFiles() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let client = try await service.connect(host: "127.0.0.1", port: fixture.port,
            username: fixture.username, authMethod: .privateKey(Data(fixture.privateKey.utf8)),
            modelContainer: container, hostKeyPrompt: { _ in .accept })
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let sftp = SFTPService(client: client)
        let directory = fixture.directory + "/" + UUID().uuidString
        let remote = directory + "/空 格.bin"
        do {
            let home = try await sftp.getHomePath()
            XCTAssertTrue(home.hasPrefix("/"))
            let output = try await client.executeCommand("printf 'SwiftSSH-fixture'")
            XCTAssertEqual(String(decoding: output.readableBytesView, as: UTF8.self), "SwiftSSH-fixture")
            try await sftp.createDirectory(path: directory)
            let source = local.appendingPathComponent("source.bin")
            let expected = Data((0..<200_001).map { UInt8(truncatingIfNeeded: $0) })
            try expected.write(to: source)
            try await sftp.uploadFile(localURL: source, remotePath: remote)
            try Data("replacement".utf8).write(to: source)
            do {
                try await sftp.uploadFile(localURL: source, remotePath: remote)
                XCTFail("An existing remote file must not be overwritten")
            } catch {}

            let destination = local.appendingPathComponent("download.bin")
            try Data("old local content".utf8).write(to: destination)
            try await sftp.downloadFile(remotePath: remote, localURL: destination)
            XCTAssertEqual(try Data(contentsOf: destination), expected)
            do {
                try await sftp.downloadFile(remotePath: directory + "/missing", localURL: destination)
                XCTFail("Missing files must fail without replacing the local destination")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: destination), expected)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: local.path)
                .contains { $0.hasPrefix(".SwiftSSH-") }, "Failed downloads must clean up staging files")
            let empty = directory + "/empty"
            try Data().write(to: source)
            try await sftp.uploadFile(localURL: source, remotePath: empty)
            try await sftp.downloadFile(remotePath: empty, localURL: destination)
            XCTAssertEqual(try Data(contentsOf: destination), Data())
            try await sftp.deleteFile(path: empty)
            let items = try await sftp.listDirectory(path: directory)
            let item = try XCTUnwrap(items.first(where: { $0.name == "空 格.bin" }))
            XCTAssertEqual(item.size, UInt64(expected.count))
            XCTAssertFalse(item.isDirectory)
            XCTAssertEqual(item.path, remote)
            XCTAssertFalse(items.contains { $0.name == "." || $0.name == ".." })
            try await sftp.deleteFile(path: remote)
            try await sftp.deleteDirectory(path: directory)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<KnownHost>()), 1)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<KnownHost>()).first?.fingerprintSHA256,
                           fixture.hostFingerprint, "Fingerprint must match OpenSSH's independent calculation")
            await service.disconnect()
        } catch {
            try? await sftp.deleteFile(path: remote)
            try? await sftp.deleteDirectory(path: directory)
            await service.disconnect()
            throw error
        }
    }

    func testSFTPDocumentSavePreservesModeAndDetectsConflicts() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let client = try await service.connect(host: "127.0.0.1", port: fixture.port,
            username: fixture.username, authMethod: .privateKey(Data(fixture.privateKey.utf8)),
            modelContainer: container, hostKeyPrompt: { _ in .accept })
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let sftp = SFTPService(client: client)
        let directory = fixture.directory + "/" + UUID().uuidString
        let remote = directory + "/空 格.txt"
        do {
            try await sftp.createDirectory(path: directory)
            let source = local.appendingPathComponent("source.txt")
            let originalData = Data("你好，SwiftSSH！\nOriginal text with a trailing line to remove.\n".utf8)
            try originalData.write(to: source)
            try await sftp.uploadFile(localURL: source, remotePath: remote)
            try await client.withSFTP { connection in
                var attributes = SFTPFileAttributes()
                attributes.permissions = 0o640
                try await connection.setAttributes(at: remote, to: attributes)
            }
            let original = try await sftp.readDocument(path: remote, maximumBytes: SFTPTextDocument.maximumBytes)
            XCTAssertEqual(original.data, originalData)
            XCTAssertEqual(original.permissions.map { $0 & 0o7777 }, 0o640)
            XCTAssertNotNil(original.userID)
            XCTAssertNotNil(original.groupID)

            let replacement = Data("短文\n".utf8)
            XCTAssertLessThan(replacement.count, originalData.count)
            let saved = try await sftp.saveDocument(path: remote, data: replacement, replacing: original)
            let reread = try await sftp.readDocument(path: remote, maximumBytes: SFTPTextDocument.maximumBytes)
            XCTAssertEqual(saved, reread)
            XCTAssertEqual(reread.data, replacement, "Shorter saves must not leave trailing bytes")
            XCTAssertEqual(reread.canonicalPath, original.canonicalPath)
            XCTAssertEqual(reread.permissions, original.permissions)
            XCTAssertEqual(reread.permissions.map { $0 & 0o7777 }, 0o640)
            XCTAssertEqual(reread.userID, original.userID)
            XCTAssertEqual(reread.groupID, original.groupID)

            do {
                _ = try await sftp.saveDocument(path: remote, data: Data("stale edit".utf8), replacing: original)
                XCTFail("Saving a stale snapshot must report a conflict")
            } catch SFTPDocumentError.conflict {}
            let afterConflict = try await sftp.readDocument(path: remote, maximumBytes: SFTPTextDocument.maximumBytes)
            XCTAssertEqual(afterConflict, reread, "A conflict must preserve the saved file")

            do {
                _ = try await sftp.readDocument(path: remote, maximumBytes: replacement.count - 1)
                XCTFail("Reading beyond the requested byte limit must fail")
            } catch SFTPDocumentError.tooLarge {}

            let cancelledSave = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await sftp.saveDocument(path: remote, data: Data("cancelled edit".utf8), replacing: reread)
            }
            do {
                _ = try await cancelledSave.value
                XCTFail("An already-cancelled save must stop")
            } catch is CancellationError {}
            let afterCancellation = try await sftp.readDocument(path: remote, maximumBytes: SFTPTextDocument.maximumBytes)
            XCTAssertEqual(afterCancellation, reread, "Cancellation must preserve the saved file")
            let remaining = try await sftp.listDirectory(path: directory)
            XCTAssertFalse(remaining.contains { $0.name.hasPrefix(".SwiftSSH-edit-") },
                           "Saves must not leave staging files behind")
            let output = try await client.executeCommand("printf 'still-connected'")
            XCTAssertEqual(String(decoding: output.readableBytesView, as: UTF8.self), "still-connected")
            try await sftp.deleteFile(path: remote)
            try await sftp.deleteDirectory(path: directory)
            await service.disconnect()
        } catch {
            try? await sftp.deleteFile(path: remote)
            if let remaining = try? await sftp.listDirectory(path: directory) {
                for item in remaining where item.name.hasPrefix(".SwiftSSH-edit-") {
                    try? await sftp.deleteFile(path: item.path)
                }
            }
            try? await sftp.deleteDirectory(path: directory)
            await service.disconnect()
            throw error
        }
    }

    func testCancellingSFTPTransfersCleansPartialFilesAndKeepsSSHConnected() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let client = try await service.connect(host: "127.0.0.1", port: fixture.port,
            username: fixture.username, authMethod: .privateKey(Data(fixture.privateKey.utf8)),
            modelContainer: container, hostKeyPrompt: { _ in .accept })
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let sftp = SFTPService(client: client)
        let directory = fixture.directory + "/" + UUID().uuidString
        let remote = directory + "/transfer.bin"
        let source = local.appendingPathComponent("source.bin")
        let byteCount: UInt64 = 16 * 1024 * 1024
        try Data().write(to: source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: byteCount)
        try handle.close()
        try await sftp.createDirectory(path: directory)
        do {
            let upload = Task { try await sftp.uploadFile(localURL: source, remotePath: remote) }
            defer { upload.cancel() }
            var uploadStarted = false
            for _ in 0..<200 {
                let files = try await sftp.listDirectory(path: directory)
                if let size = files.first(where: { $0.path == remote })?.size, size > 0, size < byteCount {
                    uploadStarted = true
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            upload.cancel()
            XCTAssertTrue(uploadStarted, "Cancel during an actual partial write")
            do {
                try await upload.value
                XCTFail("Cancelled upload must stop")
            } catch {}
            let remaining = try await sftp.listDirectory(path: directory)
            XCTAssertFalse(remaining.contains { $0.path == remote }, "Remove only the cancelled upload's partial file")

            try await sftp.uploadFile(localURL: source, remotePath: remote)
            let destination = local.appendingPathComponent("download.bin")
            let preserved = Data("keep existing local file".utf8)
            try preserved.write(to: destination)
            let download = Task { try await sftp.downloadFile(remotePath: remote, localURL: destination) }
            defer { download.cancel() }
            var downloadStarted = false
            for _ in 0..<200 {
                let staging = try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix(".SwiftSSH-") }
                if let staging, let size = try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 0, UInt64(size) < byteCount {
                    downloadStarted = true
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            download.cancel()
            XCTAssertTrue(downloadStarted, "Cancel during an actual partial read")
            do {
                try await download.value
                XCTFail("Cancelled download must stop")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: destination), preserved)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: local.path)
                .contains { $0.hasPrefix(".SwiftSSH-") })
            let output = try await client.executeCommand("printf 'still-connected'")
            XCTAssertEqual(String(decoding: output.readableBytesView, as: UTF8.self), "still-connected")
            try await sftp.deleteFile(path: remote)
            try await sftp.deleteDirectory(path: directory)
            await service.disconnect()
        } catch {
            try? await sftp.deleteFile(path: remote)
            try? await sftp.deleteDirectory(path: directory)
            await service.disconnect()
            throw error
        }
    }

    func testRejectingUnknownHostPreventsAuthentication() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let prompts = PromptCounter()
        do {
            _ = try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
                authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
                hostKeyPrompt: { _ in await prompts.record(); return .reject })
            XCTFail("Rejecting the host key must stop the connection")
        } catch {}
        await service.disconnect()
        let count = await prompts.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<KnownHost>()), 0)
    }

    func testTrustedHostDoesNotPromptAgain() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let prompts = PromptCounter()
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        for _ in 0..<2 {
            do {
                _ = try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
                    authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
                    hostKeyPrompt: { _ in await prompts.record(); return .accept })
                await service.disconnect()
            } catch {
                await service.disconnect()
                throw error
            }
        }
        let count = await prompts.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<KnownHost>()), 1)
    }

    func testDisconnectDuringHostKeyDecisionCannotCreateALateConnectionOrTrustEntry() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let entered = expectation(description: "Host key decision requested")
        let gate = HostKeyGate(entered: entered)
        let attempt = Task {
            try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
                authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
                hostKeyPrompt: { _ in await gate.wait() })
        }
        await fulfillment(of: [entered], timeout: 10)
        await service.disconnect()
        await gate.accept()
        do {
            let unexpected = try await attempt.value
            try? await unexpected.close()
            XCTFail("A disconnected attempt must not become a live connection")
        } catch {}
        XCTAssertFalse(service.isConnected)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<KnownHost>()), 0)
    }

    func testClosingSessionAfterTrustKeepsItDisconnectedAndPreservesTheAttemptAddress() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let keyID = UUID().uuidString
        try KeychainService.savePrivateKey(id: keyID, pemData: Data(fixture.privateKey.utf8))
        defer {
            KeychainService.deletePrivateKey(id: keyID)
            KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)")
        }
        let profile = ConnectionProfile(label: "Fixture", host: "127.0.0.1", port: fixture.port,
            username: fixture.username, authType: .key, keyID: keyID)
        let session = SessionViewModel(profile: profile)
        session.modelContainer = container
        let prompt = expectation(description: "Session requests host key decision")
        withObservationTracking { _ = session.pendingHostKeyPrompt } onChange: { prompt.fulfill() }
        let attempt = Task { await session.connect() }
        await fulfillment(of: [prompt], timeout: 10)
        XCTAssertNotNil(session.pendingHostKeyPrompt)
        profile.host = "edited.example.com"
        profile.port = 2222
        XCTAssertEqual(session.endpoint.host, "127.0.0.1")
        XCTAssertEqual(session.endpoint.port, fixture.port)
        session.acceptHostKey()
        session.disconnect()
        await attempt.value
        XCTAssertNil(session.sshClient)
        XCTAssertFalse(session.isConnected)
        XCTAssertNil(session.pendingHostKeyPrompt)
        XCTAssertEqual(session.statusMessage, String(localized: "Disconnected"))
    }

    func testPTYReconnectStillDeliversInputAfterPreviousSessionCleanup() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let client = try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
            authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
            hostKeyPrompt: { _ in .accept })
        let bridge = SSHTerminalBridge()
        let remote = fixture.directory + "/pty-" + UUID().uuidString
        let quoted = "'" + remote.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let sftp = SFTPService(client: client)
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        do {
            for _ in 0..<2 {
                let connected = expectation(description: "PTY connected")
                connected.assertForOverFulfill = true
                bridge.onStateChange = { isConnected, _ in if isConnected { connected.fulfill() } }
                bridge.connect(client: client, cols: 80, rows: 24)
                await fulfillment(of: [connected], timeout: 10)
                XCTAssertTrue(bridge.isConnected)
            }
            let marker = "SwiftSSH-PTY-UTF8-你好"
            bridge.sendToSSH(data: ArraySlice("printf '%s' '\(marker)' > \(quoted)\n".utf8))
            var actual = ""
            for _ in 0..<30 {
                if let data = try? await client.executeCommand("cat \(quoted)") {
                    actual = String(decoding: data.readableBytesView, as: UTF8.self)
                    if actual == marker { break }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(actual, marker)
            XCTAssertTrue(bridge.isConnected, "Prior PTY cleanup must not disconnect the replacement")
            try await sftp.deleteFile(path: remote)
            bridge.disconnect()
            await service.disconnect()
        } catch {
            bridge.disconnect()
            try? await sftp.deleteFile(path: remote)
            await service.disconnect()
            throw error
        }
    }

    func testPTYKeepsLatestSizeBeforeOpeningDuringResizeAndAcrossReconnect() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let client = try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
            authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
            hostKeyPrompt: { _ in .accept })
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        let bridge = SSHTerminalBridge()
        let remote = fixture.directory + "/pty-size-" + UUID().uuidString
        let quoted = "'" + remote.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let sftp = SFTPService(client: client)

        func assertRemoteSize(cols: Int, rows: Int) async throws {
            // Let the nonisolated UI callback reach MainActor before queuing input.
            try await Task.sleep(for: .milliseconds(50))
            bridge.sendToSSH(data: ArraySlice("stty size > \(quoted)\n".utf8))
            var actual = ""
            for _ in 0..<50 {
                if let data = try? await client.executeCommand("cat \(quoted)") {
                    actual = String(decoding: data.readableBytesView, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if actual.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                        == [String(rows), String(cols)] { break }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(actual.split(whereSeparator: { $0.isWhitespace }).map(String.init),
                           [String(rows), String(cols)])
            try await sftp.deleteFile(path: remote)
        }

        do {
            // Layout arrives before a channel exists; this must not be dropped.
            bridge.resizeTerminal(cols: 101, rows: 37)
            try await Task.sleep(for: .milliseconds(50))
            for attempt in 0..<2 {
                let connected = expectation(description: "PTY opened with the latest grid")
                bridge.onStateChange = { isConnected, _ in if isConnected { connected.fulfill() } }
                bridge.connect(client: client, cols: 80, rows: 24)
                if attempt == 0 {
                    // Another layout arrives while withPTY is still opening.
                    bridge.resizeTerminal(cols: 93, rows: 29)
                }
                await fulfillment(of: [connected], timeout: 10)
                try await assertRemoteSize(cols: attempt == 0 ? 93 : 120,
                                           rows: attempt == 0 ? 29 : 42)
                for cols in 100...120 { bridge.resizeTerminal(cols: cols, rows: 42) }
                bridge.resizeTerminal(cols: 0, rows: 0) // Ignore zero-sized transition layouts.
                try await assertRemoteSize(cols: 120, rows: 42)
                bridge.disconnect()
            }
            await service.disconnect()
        } catch {
            bridge.disconnect()
            try? await sftp.deleteFile(path: remote)
            await service.disconnect()
            throw error
        }
    }

    func testHostKeyDecisionCanOutlastNetworkTimeout() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let entered = expectation(description: "Fingerprint verification is waiting for the user")
        let gate = HostKeyGate(entered: entered)
        let attempt = Task {
            try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
                authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
                hostKeyPrompt: { _ in await gate.wait() })
        }
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        await fulfillment(of: [entered], timeout: 10)
        try await Task.sleep(for: .seconds(17))
        await gate.accept()
        do {
            _ = try await attempt.value
            XCTAssertTrue(service.isConnected)
            await service.disconnect()
        } catch {
            await service.disconnect()
            throw error
        }
    }

    func testShellExitIsNormalAndReplacementPTYCanConnect() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let service = SSHService()
        let client = try await service.connect(host: "127.0.0.1", port: fixture.port, username: fixture.username,
            authMethod: .privateKey(Data(fixture.privateKey.utf8)), modelContainer: container,
            hostKeyPrompt: { _ in .accept })
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        let bridge = SSHTerminalBridge()
        for _ in 0..<2 {
            let connected = expectation(description: "PTY connected")
            let ended = expectation(description: "Shell exit is reported")
            bridge.onStateChange = { connectedState, status in
                if connectedState { connected.fulfill() }
                if !connectedState && status != String(localized: "Opening terminal...") { ended.fulfill() }
            }
            bridge.connect(client: client, cols: 80, rows: 24)
            await fulfillment(of: [connected], timeout: 10)
            bridge.sendToSSH(data: ArraySlice("exit\n".utf8))
            await fulfillment(of: [ended], timeout: 10)
            XCTAssertFalse(bridge.isConnected)
            XCTAssertEqual(bridge.statusMessage, String(localized: "Disconnected"))
            bridge.onStateChange = nil
            bridge.disconnect()
        }
        await service.disconnect()
    }

    func testChangedHostKeyRequiresApprovalAndRejectionPreservesTrust() async throws {
        let fixture = try loadFixture()
        let container = try makeContainer()
        let oldKey = Data("previous-host-key".utf8)
        let context = ModelContext(container)
        context.insert(KnownHost(host: "127.0.0.1", port: fixture.port, keyTypeDescription: "ssh-ed25519",
            fingerprintSHA256: "SHA256:previous", publicKeyData: oldKey))
        try context.save()
        let service = SSHService()
        defer { KeychainService.deleteItem(account: "hostkey-127.0.0.1:\(fixture.port)") }
        for decision in [HostKeyPromptResult.reject, .accept] {
            do {
                _ = try await service.connect(host: "127.0.0.1", port: fixture.port,
                    username: fixture.username, authMethod: .privateKey(Data(fixture.privateKey.utf8)),
                    modelContainer: container, hostKeyPrompt: { prompt in
                        guard case .changedKey(let old, let new, _) = prompt else {
                            XCTFail("A changed key must never appear as a first connection")
                            return .reject
                        }
                        XCTAssertEqual(old, "SHA256:previous")
                        XCTAssertEqual(new, fixture.hostFingerprint)
                        return decision
                    })
                XCTAssertEqual(decision, .accept)
            } catch {
                guard decision == .reject else { await service.disconnect(); throw error }
            }
            let freshContext = ModelContext(container)
            let stored = try XCTUnwrap(freshContext.fetch(FetchDescriptor<KnownHost>()).first)
            if decision == .reject {
                XCTAssertEqual(stored.publicKeyData, oldKey)
                XCTAssertEqual(stored.fingerprintSHA256, "SHA256:previous")
                XCTAssertFalse(service.isConnected)
            } else {
                XCTAssertNotEqual(stored.publicKeyData, oldKey)
                XCTAssertEqual(stored.fingerprintSHA256, fixture.hostFingerprint)
                XCTAssertTrue(service.isConnected)
            }
            await service.disconnect()
        }
    }

    private struct Fixture: Decodable {
        let username: String
        let port: Int
        let directory: String
        let privateKey: String
        let hostFingerprint: String
    }

    func testTwoPendingHostApprovalsPersistOnlyOneKnownHost() async throws {
        let container = try makeContainer()
        let entered = expectation(description: "Both windows request trust before either decision")
        entered.expectedFulfillmentCount = 2
        let firstGate = HostKeyGate(entered: entered)
        let secondGate = HostKeyGate(entered: entered)
        let host = "trust-\(UUID().uuidString).invalid"
        defer { KeychainService.deleteItem(account: "hostkey-\(host):22") }
        func approve(using gate: HostKeyGate) async throws -> HostKeyPromptResult {
            try await TOFUHostKeyValidator.evaluate(host: host, port: 22,
                presentedKeyData: Data("same-public-key".utf8), presentedFingerprint: "SHA256:fixture",
                keyType: "ssh-ed25519", container: container, promptHandler: { _ in await gate.wait() })
        }
        let first = Task { try await approve(using: firstGate) }
        let second = Task { try await approve(using: secondGate) }
        await fulfillment(of: [entered], timeout: 5)
        await firstGate.accept()
        let firstDecision = try await first.value
        XCTAssertTrue(firstDecision == .accept)
        await secondGate.accept()
        let secondDecision = try await second.value
        XCTAssertTrue(secondDecision == .accept)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<KnownHost>()), 1)
    }

    private func loadFixture() throws -> Fixture {
        guard let url = Bundle(for: Self.self).url(forResource: "ssh-integration", withExtension: "json") else {
            throw XCTSkip("Run the isolated SSH fixture setup from the CI workflow to enable loopback integration tests.")
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: KnownHost.self, ConnectionProfile.self, SSHKey.self, Snippet.self, PortForward.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}

private actor PromptCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor HostKeyGate {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<HostKeyPromptResult, Never>?
    private var accepted = false

    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async -> HostKeyPromptResult {
        if accepted { return .accept }
        return await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }
    func accept() {
        accepted = true
        continuation?.resume(returning: .accept)
        continuation = nil
    }
}
