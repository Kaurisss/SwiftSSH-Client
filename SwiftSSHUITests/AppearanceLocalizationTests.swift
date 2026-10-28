import XCTest

final class AppearanceLocalizationTests: XCTestCase {
    @MainActor
    func testChineseInterfaceAndAppearanceSwitching() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-hasCompletedOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["主机"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["connection-add"].exists)
        capture("Chinese-Hosts")

        app.tabBars.buttons["密钥"].tap()
        XCTAssertTrue(app.staticTexts["暂无 SSH 密钥"].waitForExistence(timeout: 5))
        capture("Chinese-Keys")

        app.tabBars.buttons["设置"].tap()
        capture("Chinese-Settings")
        let appearanceLink = app.buttons["settings-appearance"]
        XCTAssertTrue(appearanceLink.waitForExistence(timeout: 5))
        appearanceLink.tap()
        let appearance = app.segmentedControls["appearance-picker"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.buttons["浅色"].tap()
        XCTAssertTrue(appearance.buttons["浅色"].isSelected)
        app.tabBars.buttons["主机"].tap()
        capture("Chinese-Hosts-Light")

        app.tabBars.buttons["设置"].tap()
        appearance.buttons["深色"].tap()
        XCTAssertTrue(appearance.buttons["深色"].isSelected)
        app.tabBars.buttons["主机"].tap()
        capture("Chinese-Hosts-Dark")

        app.tabBars.buttons["设置"].tap()
        appearance.buttons["跟随系统"].tap()
        XCTAssertTrue(appearance.buttons["跟随系统"].isSelected)
    }

    @MainActor
    func testSettingsHierarchyAndBackNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-hasCompletedOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 30))
        app.tabBars.buttons["设置"].tap()
        XCTAssertFalse(app.segmentedControls["appearance-picker"].exists)
        XCTAssertFalse(app.buttons["清除所有数据"].exists)

        let destinations = [
            ("settings-appearance", "应用外观"),
            ("settings-terminal", "终端"),
            ("settings-security", "安全"),
            ("settings-known-hosts", "已信任的主机"),
            ("settings-snippets", "常用命令"),
            ("settings-storage", "存储"),
            ("settings-about", "关于")
        ]
        for (identifier, title) in destinations {
            let link = app.buttons[identifier]
            XCTAssertTrue(link.waitForExistence(timeout: 5), identifier)
            link.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))

            if identifier == "settings-terminal" {
                app.buttons["settings-terminal-theme"].tap()
                XCTAssertTrue(app.navigationBars["终端主题"].waitForExistence(timeout: 5))
                app.navigationBars["终端主题"].buttons.element(boundBy: 0).tap()
                XCTAssertTrue(app.navigationBars["终端"].waitForExistence(timeout: 5))
            }
            if identifier == "settings-storage" {
                app.buttons["清除所有数据"].tap()
                let alert = app.alerts["清除所有数据？"]
                XCTAssertTrue(alert.waitForExistence(timeout: 5))
                alert.buttons["取消"].tap()
                XCTAssertFalse(alert.exists)
            }

            app.navigationBars[title].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testKeyImportChoosesSourceBeforeShowingInputs() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["密钥"].waitForExistence(timeout: 15))
        app.tabBars.buttons["密钥"].tap()
        app.buttons["导入已有密钥"].tap()

        XCTAssertTrue(app.buttons["key-import-files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["key-import-paste"].exists)
        XCTAssertFalse(app.textFields["key-import-name"].exists)
        XCTAssertFalse(app.textViews["key-import-private-key"].exists)
        capture("Chinese-Key-Import-Sources")

        app.buttons["key-import-paste"].tap()
        let editor = app.textViews["key-import-private-key"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["key-import-name"].exists)
        editor.tap()
        editor.typeText("not-a-private-key")
        app.buttons["key-import-save"].tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "请选择未加密")
        ).firstMatch.exists)
        alert.buttons.firstMatch.tap()
        XCTAssertEqual(editor.value as? String, "not-a-private-key")
    }

    @MainActor
    func testSnippetEditorPreservesCommandNewlineAndValidatesEmptyInput() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 15))
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings-snippets"].tap()
        app.buttons["snippet-add"].tap()
        app.buttons["snippet-save"].tap()
        XCTAssertTrue(app.alerts["无法保存命令"].waitForExistence(timeout: 5))
        app.alerts.buttons["关闭"].tap()
        let name = "Fixture-\(UUID().uuidString.prefix(6))"
        let label = app.textFields["snippet-label"]
        label.tap()
        label.typeText(name)
        let editor = app.textViews["snippet-command"]
        editor.tap()
        editor.typeText("printf 'hello'\n")
        app.buttons["snippet-save"].tap()
        let saved = app.buttons.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertEqual(editor.value as? String, "printf 'hello'\n")
        capture("Chinese-Snippet-Editor")
        app.buttons["取消"].tap()
        saved.swipeLeft()
        app.buttons["删除"].tap()
        app.buttons["取消"].tap()
        XCTAssertTrue(saved.exists)
    }

    @MainActor
    func testEmptyTerminalConnectActionReturnsToHosts() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["终端"].waitForExistence(timeout: 15))
        app.tabBars.buttons["终端"].tap()
        XCTAssertTrue(app.staticTexts["暂无活动会话"].waitForExistence(timeout: 5))
        app.buttons["连接"].tap()
        XCTAssertTrue(app.tabBars.buttons["主机"].isSelected)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
