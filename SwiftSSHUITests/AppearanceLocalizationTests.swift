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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
