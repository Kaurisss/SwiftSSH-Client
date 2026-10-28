import SwiftTerm
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class TerminalAccessoryBarTests: XCTestCase {
    func testRestingScrollEdgesNeverShowAnEmptyPartialCapsule() throws {
        let terminal = TerminalView()
        let bar = TerminalAccessoryBar(terminal: terminal)
        let scroll = try XCTUnwrap(bar.subviews.compactMap { $0 as? UIScrollView }.first)
        let keys = buttons(in: scroll)
        for width in [CGFloat(320), 390, 393, 430, 844, 1024] {
            bar.frame = CGRect(x: 0, y: 0, width: width, height: 46)
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
            let maximum = max(0, scroll.contentSize.width - scroll.bounds.width)
            for offset in [CGFloat(0), maximum * 0.23, maximum * 0.54, maximum] {
                var target = CGPoint(x: offset, y: 0)
                bar.scrollViewWillEndDragging(scroll, withVelocity: .zero, targetContentOffset: &target)
                scroll.setContentOffset(target, animated: false)
                scroll.layoutIfNeeded()
                let viewport = scroll.convert(scroll.bounds, to: bar)
                var visibleKeys = 0
                for key in keys {
                    let frame = key.convert(key.bounds, to: bar)
                    guard frame.intersection(viewport).width > 0.5 else { continue }
                    visibleKeys += 1
                    XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 0.5)
                    XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 0.5)
                    XCTAssertFalse(key.currentTitle?.isEmpty ?? true)
                    XCTAssertNil(key.layer.mask)
                    XCTAssertNil(key.titleLabel?.layer.mask)
                    XCTAssertEqual(key.alpha, 1)
                }
                XCTAssertGreaterThan(visibleKeys, 0)
                XCTAssertTrue(scroll.clipsToBounds)
                XCTAssertNil(scroll.layer.mask)
            }
        }
    }

    func testFrequentKeysComeFirstAndArrowsSendANSISequences() throws {
        let terminal = TerminalView()
        let delegate = RecordingTerminalDelegate()
        terminal.terminalDelegate = delegate
        let bar = TerminalAccessoryBar(terminal: terminal)
        let keys = buttons(in: bar).filter { $0.currentTitle != nil }.sorted { $0.tag < $1.tag }
        XCTAssertEqual(Array(keys.prefix(8).compactMap(\.currentTitle)),
                       ["Esc", "Tab", "Ctrl", "↑", "↓", "←", "→", "Ctrl C"])
        for key in keys[3...6] { key.sendActions(for: .touchUpInside) }
        XCTAssertEqual(delegate.sent, [[0x1B, 0x5B, 0x41], [0x1B, 0x5B, 0x42],
                                       [0x1B, 0x5B, 0x44], [0x1B, 0x5B, 0x43]])
    }

    func testLastKeyIsFullyVisibleBeforeFixedButtonsAtEndOfScroll() throws {
        let terminal = TerminalView()
        let bar = TerminalAccessoryBar(terminal: terminal)
        let scroll = try XCTUnwrap(bar.subviews.compactMap { $0 as? UIScrollView }.first)
        let last = try XCTUnwrap(buttons(in: scroll).max { $0.tag < $1.tag })
        let snippets = try XCTUnwrap(buttons(in: bar).first {
            $0.accessibilityLabel == String(localized: "Snippets")
        })
        // Cover narrow phones, landscape and iPad widths.
        for width in [CGFloat(320), 390, 844, 1024] {
            bar.frame = CGRect(x: 0, y: 0, width: width, height: 46)
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
            XCTAssertGreaterThan(scroll.contentSize.width, 0)
            scroll.contentOffset.x = max(0, scroll.contentSize.width - scroll.bounds.width)
            let frame = last.convert(last.bounds, to: bar)
            XCTAssertGreaterThanOrEqual(frame.minX, scroll.frame.minX)
            XCTAssertLessThanOrEqual(frame.maxX, scroll.frame.maxX - 5)
            XCTAssertLessThan(scroll.frame.maxX, snippets.frame.minX)
            XCTAssertTrue(scroll.clipsToBounds)
            XCTAssertFalse(bar.hasAmbiguousLayout)
        }
    }

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

    func testControlModifierAppliesToSystemKeyboardInput() throws {
        let terminal = TerminalView()
        let delegate = RecordingTerminalDelegate()
        terminal.terminalDelegate = delegate
        let bar = TerminalAccessoryBar(terminal: terminal)
        let control = try XCTUnwrap(buttons(in: bar).first { $0.currentTitle == "Ctrl" })
        control.sendActions(for: .touchUpInside)
        terminal.insertText("c")
        XCTAssertEqual(delegate.sent, [[0x03]])
        XCTAssertFalse(control.isSelected)
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
