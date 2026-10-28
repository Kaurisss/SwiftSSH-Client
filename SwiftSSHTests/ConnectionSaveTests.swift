import SwiftData
import XCTest
@testable import SwiftSSH

@MainActor
final class ConnectionSaveTests: XCTestCase {
    func testSaveNormalizesEndpointAndPersistsPasswordInKeychain() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = try ConnectionListViewModel().saveConnection(
            profile: nil, label: "Fixture", host: " 2001:db8::22 ", port: 2200,
            username: " alice ", authType: .password, password: "fixture", keyID: nil,
            isFavorite: true, groupName: "Test", colorTag: "blue", modelContext: context)
        defer { KeychainService.deleteItem(account: "pwd-\(saved.syncID)") }
        XCTAssertEqual(saved.host, "2001:db8::22")
        XCTAssertEqual(saved.username, "alice")
        XCTAssertEqual(saved.port, 2200)
        XCTAssertEqual(KeychainService.getPassword(for: saved.syncID), "fixture")
        let reopened = ModelContext(container)
        let rows = try reopened.fetch(FetchDescriptor<ConnectionProfile>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.syncID, saved.syncID)
        XCTAssertTrue(try XCTUnwrap(rows.first).isFavorite)
        XCTAssertEqual(rows.first?.groupName, "Test")
    }

    func testEditingWithBlankPasswordKeepsTheExistingCredentialAndIdentity() throws {
        let container = try makeContainer()
        let model = ConnectionListViewModel()
        let context = container.mainContext
        let saved = try model.saveConnection(profile: nil, label: "Before", host: "host.local", port: 22,
            username: "root", authType: .password, password: "keep", keyID: nil, modelContext: context)
        defer { KeychainService.deleteItem(account: "pwd-\(saved.syncID)") }
        let updated = try model.saveConnection(profile: saved, label: "After", host: "new.local", port: 2222,
            username: "alice", authType: .password, password: "", keyID: nil, modelContext: context)
        XCTAssertTrue(saved === updated)
        XCTAssertEqual(updated.label, "After")
        XCTAssertEqual(KeychainService.getPassword(for: saved.syncID), "keep")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConnectionProfile>()), 1)
    }

    func testInvalidEndpointAndMissingKeyNeverInsertAProfile() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let model = ConnectionListViewModel()
        for (host, port, username) in [(" ", 22, "root"), ("host", 0, "root"), ("host", 65536, "root"),
                                       ("host", 22, " "), ("host/path", 22, "root")] {
            XCTAssertThrowsError(try model.saveConnection(profile: nil, label: "Invalid", host: host, port: port,
                username: username, authType: .password, password: "", keyID: nil, modelContext: context))
        }
        XCTAssertThrowsError(try model.saveConnection(profile: nil, label: "Invalid", host: "host", port: 22,
            username: "root", authType: .key, password: nil, keyID: nil, modelContext: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConnectionProfile>()), 0)
    }

    func testReadOnlyStoreFailureRestoresProfileAndPasswordWithoutDiscardingOtherDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let identifier = try seedProfile(at: url)
        defer { KeychainService.deleteItem(account: "pwd-\(identifier)") }
        let container = try ModelContainer(for: ConnectionProfile.self,
            configurations: ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<ConnectionProfile>()).first)
        let otherDraft = ConnectionProfile(label: "Keep this draft", host: "other.local")
        context.insert(otherDraft)

        XCTAssertThrowsError(try ConnectionListViewModel().saveConnection(profile: saved, label: "Changed",
            host: "changed.local", port: 2222, username: "alice", authType: .password,
            password: "replacement", keyID: nil, modelContext: context))
        XCTAssertEqual(saved.label, "Original")
        XCTAssertEqual(saved.host, "original.local")
        XCTAssertEqual(saved.username, "root")
        XCTAssertEqual(saved.port, 22)
        XCTAssertEqual(KeychainService.getPassword(for: identifier), "original-password")
        XCTAssertTrue(context.insertedModelsArray.contains { $0.persistentModelID == otherDraft.persistentModelID })
    }

    private func seedProfile(at url: URL) throws -> String {
        let container = try ModelContainer(for: ConnectionProfile.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        return try ConnectionListViewModel().saveConnection(profile: nil, label: "Original",
            host: "original.local", port: 22, username: "root", authType: .password,
            password: "original-password", keyID: nil, modelContext: container.mainContext).syncID
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: ConnectionProfile.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}
