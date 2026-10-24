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
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            TerminalFocusHarness(primary: primary, secondary: secondary, focus: focus))
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        defer {
            primary.terminalView?.resignFirstResponder()
            secondary.terminalView?.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        try await waitForFocus(on: primary)
        XCTAssertEqual(primary.terminalView?.isFirstResponder, true)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, false)

        focus.primary = false
        try await waitForFocus(on: secondary)
        XCTAssertEqual(primary.terminalView?.isFirstResponder, false)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, true)

        let focusedTerminal = try XCTUnwrap(secondary.terminalView)
        primary.statusMessage = "Background update"
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(secondary.terminalView === focusedTerminal)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, true)
    }

    private func waitForFocus(on bridge: SSHTerminalBridge) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        // Poll UIKit on MainActor while allowing the first keyboard presentation to finish.
        while bridge.terminalView?.isFirstResponder != true && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
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
