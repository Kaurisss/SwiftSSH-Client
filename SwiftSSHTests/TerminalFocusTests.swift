import Observation
import SwiftUI
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class TerminalFocusTests: XCTestCase {
    func testOnlyFocusedPaneRequestsTheKeyboardAndBackgroundUpdatesCannotStealIt() async throws {
        let primary = SSHTerminalBridge()
        let secondary = SSHTerminalBridge()
        primary.isConnected = true
        secondary.isConnected = true
        let focus = TerminalFocusFixture()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            TerminalFocusHarness(primary: primary, secondary: secondary, focus: focus))
        window.makeKeyAndVisible()
        defer {
            primary.terminalView?.resignFirstResponder()
            secondary.terminalView?.resignFirstResponder()
            window.isHidden = true
        }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(primary.terminalView?.isFirstResponder, true)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, false)

        focus.primary = false
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(primary.terminalView?.isFirstResponder, false)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, true)

        primary.statusMessage = "Background update"
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, true)
    }
}

@MainActor
@Observable
private final class TerminalFocusFixture {
    var primary = true
}

private struct TerminalFocusHarness: View {
    let primary: SSHTerminalBridge
    let secondary: SSHTerminalBridge
    let focus: TerminalFocusFixture

    var body: some View {
        HStack {
            TerminalViewWrapper(bridge: primary, isFocused: focus.primary)
            TerminalViewWrapper(bridge: secondary, isFocused: !focus.primary)
        }
    }
}
