import Foundation
import SwiftData
import XCTest
@testable import SwiftSSH

@MainActor
final class LocalStoreTests: XCTestCase {
    func testNewLocalStorePersistsConnectionsAcrossReopen() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("default.store")

        do {
            let container = try LocalStore.open(at: url)
            container.mainContext.insert(ConnectionProfile(
                label: "Fixture",
                host: "192.0.2.1",
                username: "tester"
            ))
            try container.mainContext.save()
        }

        let reopened = try LocalStore.open(at: url)
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<ConnectionProfile>())
        XCTAssertEqual(profiles.map(\.label), ["Fixture"])
        XCTAssertEqual(profiles.map(\.host), ["192.0.2.1"])
    }

    func testUnreadableStoreIsNotDeletedOrReplaced() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("default.store")
        let original = Data("corrupt store fixture — keep for recovery".utf8)
        try original.write(to: url)
        let otherStore = directory.appendingPathComponent("default-cloud.store")
        try original.write(to: otherStore)

        XCTAssertThrowsError(try LocalStore.open(at: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try Data(contentsOf: otherStore), original)
    }

    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
