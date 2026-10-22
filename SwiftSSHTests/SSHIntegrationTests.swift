import Citadel
import Foundation
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
            try await sftp.downloadFile(remotePath: remote, localURL: destination)
            XCTAssertEqual(try Data(contentsOf: destination), expected)
            let items = try await sftp.listDirectory(path: directory)
            let item = try XCTUnwrap(items.first(where: { $0.name == "空 格.bin" }))
            XCTAssertEqual(item.size, UInt64(expected.count))
            XCTAssertFalse(item.isDirectory)
            XCTAssertEqual(item.path, remote)
            XCTAssertFalse(items.contains { $0.name == "." || $0.name == ".." })
            try await sftp.deleteFile(path: remote)
            try await sftp.deleteDirectory(path: directory)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<KnownHost>()), 1)
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

    private struct Fixture: Decodable {
        let username: String
        let port: Int
        let directory: String
        let privateKey: String
    }

    private func loadFixture() throws -> Fixture {
        guard let url = Bundle(for: Self.self).url(forResource: "ssh-integration", withExtension: "json") else {
            throw XCTSkip("Run the isolated SSH fixture setup from the CI workflow to enable loopback integration tests.")
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: KnownHost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}

private actor PromptCounter {
    private(set) var count = 0
    func record() { count += 1 }
}
