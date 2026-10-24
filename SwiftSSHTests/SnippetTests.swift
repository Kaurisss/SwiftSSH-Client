import SwiftData
import XCTest
@testable import SwiftSSH

@MainActor
final class SnippetTests: XCTestCase {
    func testSavingPreservesEveryCommandByteIncludingTrailingNewlines() throws {
        let container = try ModelContainer(for: Snippet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let command = "\n  printf 'hello'\n\n"
        try Snippet.save(nil, label: "  Greeting  ", command: command, in: container.mainContext)
        let context = ModelContext(container)
        let snippet = try XCTUnwrap(context.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(snippet.label, "Greeting")
        XCTAssertEqual(Array(snippet.command.utf8), Array(command.utf8))
        let identifier = snippet.syncID
        try Snippet.save(snippet, label: "Edited", command: "echo hello\r\n", in: context)
        XCTAssertEqual(snippet.syncID, identifier)
        XCTAssertEqual(snippet.command, "echo hello\r\n")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Snippet>()), 1)
    }

    func testWhitespaceOnlyCommandIsRejectedWithoutChangingExistingCommand() throws {
        let container = try ModelContainer(for: Snippet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        try Snippet.save(nil, label: "Original", command: "pwd\n", in: container.mainContext)
        let original = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertThrowsError(try Snippet.save(original, label: "Discarded", command: " \n\t", in: container.mainContext))
        XCTAssertEqual(original.label, "Original")
        XCTAssertEqual(original.command, "pwd\n")
        XCTAssertThrowsError(try Snippet.save(nil, label: "Empty", command: "", in: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Snippet>()), 1)
    }

    func testSearchMatchesLabelsOrCommandsAndPreservesRecencyOrder() {
        let first = Snippet(label: "Logs", command: "tail -f /var/log/app.log")
        let second = Snippet(label: "Status", command: "git status")
        let third = Snippet(label: "Repo", command: "git log --oneline")
        XCTAssertEqual(Snippet.filtered([first, second, third], query: " GIT ").map(\.syncID), [second.syncID, third.syncID])
        XCTAssertEqual(Snippet.filtered([first, second], query: "LOGS").map(\.syncID), [first.syncID])
        XCTAssertEqual(Snippet.filtered([first, second], query: " \n").count, 2)
        XCTAssertTrue(Snippet.filtered([first, second], query: "missing").isEmpty)
    }

    func testReadOnlyStoreFailurePreservesOriginalCommandAndOtherDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        try seedSnippet(at: url)
        let container = try ModelContainer(for: Snippet.self,
            configurations: ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<Snippet>()).first)
        let draft = Snippet(label: "Keep this draft", command: "ls")
        context.insert(draft)
        XCTAssertThrowsError(try Snippet.save(original, label: "Changed", command: "changed\n", in: context))
        XCTAssertEqual(original.label, "Original")
        XCTAssertEqual(original.command, "pwd\n")
        XCTAssertTrue(context.insertedModelsArray.contains { $0.persistentModelID == draft.persistentModelID })
    }

    private func seedSnippet(at url: URL) throws {
        let container = try ModelContainer(for: Snippet.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        try Snippet.save(nil, label: "Original", command: "pwd\n", in: container.mainContext)
    }
}
