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
