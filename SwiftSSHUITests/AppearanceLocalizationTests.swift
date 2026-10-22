import XCTest

final class AppearanceLocalizationTests: XCTestCase {
    @MainActor
    func testChineseInterfaceAndAppearanceSwitching() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-hasCompletedOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["主机"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["quick-connect"].exists)
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

        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 15))
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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
