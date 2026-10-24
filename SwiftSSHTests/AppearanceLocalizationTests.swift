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

    func testMetadataAndStatusTextMeetContrastInBothAppearances() {
        func rgba(_ color: UIColor) -> [Double] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return [Double(red), Double(green), Double(blue), Double(alpha)]
        }
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let textColors = [AppColors.textSecondary, AppColors.textTertiary, AppColors.accent,
                          AppColors.connected, AppColors.warning, AppColors.error]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for surface in [AppColors.background, AppColors.surface, AppColors.surfaceElevated] {
                let background = rgba(UIColor(surface).resolvedColor(with: traits))
                for color in textColors {
                    let foreground = rgba(UIColor(color).resolvedColor(with: traits))
                    let rendered = zip(foreground.prefix(3), background.prefix(3)).map { pair in
                        pair.0 * foreground[3] + pair.1 * (1 - foreground[3])
                    }
                    let front = luminance(rendered), back = luminance(background)
                    let contrast = (max(front, back) + 0.05) / (min(front, back) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5, "Normal text must remain readable on every app surface")
                }
            }
            let label = luminance(rgba(UIColor(AppColors.onEmphasis).resolvedColor(with: traits)))
            for fill in [AppColors.accent, AppColors.error] {
                let background = luminance(rgba(UIColor(fill).resolvedColor(with: traits)))
                let contrast = (max(label, background) + 0.05) / (min(label, background) + 0.05)
                XCTAssertGreaterThanOrEqual(contrast, 4.5, "Filled buttons must have readable labels")
            }
        }
    }
}
