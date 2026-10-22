import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class AppearanceLocalizationTests: XCTestCase {
    func testAppearanceModesAndDefaultTerminalColors() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)

        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let background = UIColor(AppColors.background)
        XCTAssertNotEqual(background.resolvedColor(with: light), background.resolvedColor(with: dark))
        let terminalBackground = UIColor(TerminalTheme.default.background)
        XCTAssertNotEqual(terminalBackground.resolvedColor(with: light), terminalBackground.resolvedColor(with: dark))
    }

    func testSimplifiedChineseResourcesAndFormatting() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(chinese.localizedString(forKey: "Connections", value: nil, table: nil), "主机")
        XCTAssertEqual(chinese.localizedString(forKey: "Light", value: nil, table: nil), "浅色")
        let format = chinese.localizedString(forKey: "Connection failed: %@", value: nil, table: nil)
        XCTAssertEqual(String(format: format, "fixture"), "连接失败：fixture")
        let count = chinese.localizedString(forKey: "%lld items", value: nil, table: nil)
        XCTAssertEqual(String(format: count, 3), "3 项")
    }

    func testLoadingAndDisconnectedBannersUseTheLocalizedStatus() throws {
        let session = SessionViewModel(profile: ConnectionProfile(label: "Fixture", host: "192.0.2.1"))
        XCTAssertEqual(session.statusMessage, String(localized: "Disconnected"))
        XCTAssertEqual(session.bridge.statusMessage, String(localized: "Disconnected"))
    }
}
