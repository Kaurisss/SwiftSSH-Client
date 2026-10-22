import SwiftTerm
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class TerminalAccessoryBarTests: XCTestCase {
    func testInterruptAndEndOfInputButtonsSendControlBytes() throws {
        let terminal = TerminalView()
        let delegate = RecordingTerminalDelegate()
        terminal.terminalDelegate = delegate
        let bar = TerminalAccessoryBar(terminal: terminal)
        let buttons = buttons(in: bar)
        let interrupt = try XCTUnwrap(buttons.first { $0.currentTitle == "Ctrl C" })
        let endOfInput = try XCTUnwrap(buttons.first { $0.currentTitle == "Ctrl D" })
        interrupt.sendActions(for: .touchUpInside)
        endOfInput.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.sent, [[0x03], [0x04]])
    }

    func testControlModifierAnnouncesSelectionAndResetsAfterSending() throws {
        let terminal = TerminalView()
        let delegate = RecordingTerminalDelegate()
        terminal.terminalDelegate = delegate
        let bar = TerminalAccessoryBar(terminal: terminal)
        let buttons = buttons(in: bar)
        let control = try XCTUnwrap(buttons.first { $0.currentTitle == "Ctrl" })
        let pipe = try XCTUnwrap(buttons.first { $0.currentTitle == "|" })
        control.sendActions(for: .touchUpInside)
        XCTAssertTrue(control.isSelected)
        pipe.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.sent, [[0x1C]])
        XCTAssertFalse(control.isSelected)
        XCTAssertTrue(buttons.contains { $0.accessibilityLabel == String(localized: "Hide Keyboard") })
        XCTAssertTrue(buttons.contains { $0.accessibilityLabel == String(localized: "Snippets") })
    }

    private func buttons(in view: UIView) -> [UIButton] {
        (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }
}

private final class RecordingTerminalDelegate: NSObject, TerminalViewDelegate {
    var sent: [[UInt8]] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(Array(data)) }
    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
