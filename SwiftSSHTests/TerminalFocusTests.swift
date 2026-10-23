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
        defer {
            primary.terminalView?.resignFirstResponder()
            secondary.terminalView?.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            primary.terminalView?.isFirstResponder == true
        }, object: nil)], timeout: 5)
        XCTAssertEqual(primary.terminalView?.isFirstResponder, true)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, false)

        focus.primary = false
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            secondary.terminalView?.isFirstResponder == true
        }, object: nil)], timeout: 5)
        XCTAssertEqual(primary.terminalView?.isFirstResponder, false)
        XCTAssertEqual(secondary.terminalView?.isFirstResponder, true)

        let focusedTerminal = try XCTUnwrap(secondary.terminalView)
        primary.statusMessage = "Background update"
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(secondary.terminalView === focusedTerminal)
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
