import XCTest

final class SSHFlowTests: XCTestCase {
    @MainActor
    func testLiveSSHAndFilesFlow() throws {
        guard let fixtureURL = Bundle(for: Self.self).url(forResource: "ssh-integration", withExtension: "json") else {
            throw XCTSkip("The CI loopback SSH fixture is not configured.")
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-hasCompletedOnboarding", "YES", "-terminalBlinkCursor", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Keys"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Keys"].tap()
        if !app.buttons["Import Existing Key"].exists { app.buttons["Add Key"].tap() }
        app.buttons["Import Existing Key"].tap()
        app.buttons["key-import-paste"].tap()
        let keyName = "CI-Key-\(UUID().uuidString.prefix(6))"
        let name = app.textFields["key-import-name"]
        name.tap()
        name.typeText(keyName)
        let privateKey = app.textViews["key-import-private-key"]
        privateKey.tap()
        privateKey.typeText(fixture.privateKey)
        app.buttons["key-import-save"].tap()
        XCTAssertTrue(app.staticTexts[keyName].waitForExistence(timeout: 10))

        app.tabBars.buttons["Connections"].tap()
        let quick = app.textFields["quick-connect"]
        quick.tap()
        quick.typeText("\(fixture.username)@127.0.0.1:\(fixture.port)\n")
        let method = app.segmentedControls["connection-auth-method"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.buttons["SSH Key"].tap()
        app.buttons["connection-key"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", keyName)).firstMatch.tap()
        app.buttons["connection-save"].tap()
        let trust = app.buttons["Trust"]
        XCTAssertTrue(trust.waitForExistence(timeout: 15))
        capture("Live-SSH-Host-Key-Prompt")
        trust.tap()
        let details = app.buttons["connection-details"]
        waitForConnected(details)

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.buttons["Hide Keyboard"].tap()
        XCTAssertTrue(app.tabBars.buttons["Terminal"].waitForExistence(timeout: 10))
        capture("Live-SSH-Keyboard-Hidden")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        capture("Live-SSH-Keyboard-Visible")

        let files = app.buttons["terminal-files"]
        XCTAssertTrue(files.isHittable)
        files.tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 10))
        app.buttons["File Actions"].tap()
        app.buttons["New Folder"].tap()
        let folderName = "ui-\(UUID().uuidString.prefix(8))"
        let folderInput = app.alerts.textFields.firstMatch
        folderInput.tap()
        folderInput.typeText(folderName)
        app.alerts.buttons["Create"].tap()
        let folder = app.buttons.containing(.staticText, identifier: folderName).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        capture("Live-SFTP-Created-Folder")
        folder.tap()
        XCTAssertTrue(app.staticTexts["Empty Directory"].waitForExistence(timeout: 10))
        app.buttons["Parent Folder"].tap()
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts.buttons["Cancel"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(folder.exists)
        folder.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Empty Directory"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.buttons["terminal-actions"].tap()
        app.buttons["session-snippets"].tap()
        app.buttons["Add Snippet"].firstMatch.tap()
        let snippetName = "CI-Exit-\(UUID().uuidString.prefix(6))"
        app.textFields["snippet-label"].tap()
        app.textFields["snippet-label"].typeText(snippetName)
        app.textViews["snippet-command"].tap()
        app.textViews["snippet-command"].typeText("exit\n")
        app.buttons["snippet-save"].tap()
        let snippet = app.buttons.containing(.staticText, identifier: snippetName).firstMatch
        XCTAssertTrue(snippet.waitForExistence(timeout: 5))
        snippet.tap()
        let reconnect = app.buttons["Reconnect"]
        XCTAssertTrue(reconnect.waitForExistence(timeout: 10))
        capture("Live-SSH-Disconnected-Recovery")
        reconnect.tap()
        waitForConnected(details)
        XCTAssertFalse(app.buttons["Trust"].exists)

        app.buttons["terminal-actions"].tap()
        app.buttons["Close Session"].tap()
        XCTAssertTrue(app.alerts.buttons["Cancel"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(details.exists)
        capture("Live-SSH-Connected-Terminal")
        app.buttons["terminal-actions"].tap()
        app.buttons["Close Session"].tap()
        app.alerts.buttons["Disconnect"].tap()
        XCTAssertTrue(app.staticTexts["No Active Sessions"].waitForExistence(timeout: 10))
    }

    private struct Fixture: Decodable {
        let username: String
        let port: Int
        let privateKey: String
    }

    @MainActor
    private func waitForConnected(_ details: XCUIElement) {
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            details.exists && details.value as? String == "Connected"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 15), .completed)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
