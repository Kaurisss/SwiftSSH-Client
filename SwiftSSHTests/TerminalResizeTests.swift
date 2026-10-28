import QuartzCore
import SwiftTerm
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class TerminalResizeTests: XCTestCase {
    func testTerminalOwnLayoutReportsTheLatestGridAfterTheLayoutPass() async throws {
        let terminal = try XCTUnwrap(TerminalViewWrapper.makeTerminalView(backgroundColor: .white)
            as? LayoutReportingTerminalView)
        let firstLayout = expectation(description: "First completed terminal layout")
        var reported: (cols: Int, rows: Int, first: Bool)?
        terminal.onLayout = { view, first in
            reported = (view.getTerminal().cols, view.getTerminal().rows, first)
            firstLayout.fulfill()
        }
        terminal.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
        terminal.layoutIfNeeded()
        // Several frames can be assigned during a single Auto Layout pass.
        terminal.frame.size.width = 390
        terminal.layoutIfNeeded()
        await fulfillment(of: [firstLayout], timeout: 3)
        XCTAssertEqual(reported?.cols, terminal.getTerminal().cols)
        XCTAssertEqual(reported?.rows, terminal.getTerminal().rows)
        XCTAssertEqual(reported?.first, true)

        let fontLayout = expectation(description: "Font layout without resizing the container")
        terminal.onLayout = { view, first in
            reported = (view.getTerminal().cols, view.getTerminal().rows, first)
            fontLayout.fulfill()
        }
        terminal.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        terminal.setNeedsLayout()
        terminal.layoutIfNeeded()
        await fulfillment(of: [fontLayout], timeout: 3)
        XCTAssertEqual(reported?.cols, terminal.getTerminal().cols)
        XCTAssertEqual(reported?.rows, terminal.getTerminal().rows)
        XCTAssertEqual(reported?.first, false)
        terminal.onLayout = nil
    }

    func testContainerInsetsActualTerminalBoundsAndReportsGridAfterLayout() throws {
        let terminal = TerminalViewWrapper.makeTerminalView(backgroundColor: .white)
        terminal.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        let container = TerminalContainerView(terminal: terminal)
        var reportedGrid: (cols: Int, rows: Int)?
        container.onLayout = { view in
            reportedGrid = (view.getTerminal().cols, view.getTerminal().rows)
        }
        for size in [CGSize(width: 390, height: 600), CGSize(width: 844, height: 260),
                     CGSize(width: 390, height: 300)] {
            container.frame = CGRect(origin: .zero, size: size)
            container.setNeedsLayout()
            container.layoutIfNeeded()
            XCTAssertEqual(terminal.frame.minX, 10)
            XCTAssertEqual(terminal.bounds.width, size.width - 20)
            XCTAssertEqual(terminal.bounds.height, size.height)
            XCTAssertEqual(container.backgroundColor, terminal.nativeBackgroundColor)
            let grid = try XCTUnwrap(reportedGrid)
            XCTAssertEqual(grid.cols, terminal.getTerminal().cols)
            XCTAssertEqual(grid.rows, terminal.getTerminal().rows)
            XCTAssertGreaterThan(grid.cols, 0)
            XCTAssertGreaterThan(grid.rows, 0)
            let fitted = terminal.getOptimalFrameSize().size
            XCTAssertLessThanOrEqual(fitted.width, terminal.bounds.width)
            XCTAssertLessThanOrEqual(fitted.height, terminal.bounds.height)
            XCTAssertLessThan(terminal.bounds.width - fitted.width, fitted.width / CGFloat(grid.cols))
            XCTAssertLessThan(terminal.bounds.height - fitted.height, fitted.height / CGFloat(grid.rows))
        }
    }

    func testPinchRecomputesGridWithinLimitsAndSurvivesUnrelatedUpdates() {
        let terminal = TerminalViewWrapper.makeTerminalView(backgroundColor: .white)
        terminal.frame = CGRect(x: 0, y: 0, width: 370, height: 500)
        let coordinator = TerminalViewWrapper.Coordinator(bridge: SSHTerminalBridge())
        let preference = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        coordinator.applyFontPreference(preference, to: terminal)
        terminal.layoutIfNeeded()
        let originalCols = terminal.getTerminal().cols
        let originalRows = terminal.getTerminal().rows
        let pinch = SimulatedPinchGestureRecognizer()
        terminal.addGestureRecognizer(pinch)
        XCTAssertTrue(coordinator.gestureRecognizer(pinch,
            shouldRecognizeSimultaneouslyWith: terminal.panGestureRecognizer))
        pinch.simulatedState = .began
        coordinator.handlePinch(pinch)
        pinch.scale = 0.1
        pinch.simulatedState = .changed
        coordinator.handlePinch(pinch)
        XCTAssertEqual(terminal.font.pointSize, 8)
        XCTAssertGreaterThan(terminal.getTerminal().cols, originalCols)
        XCTAssertGreaterThan(terminal.getTerminal().rows, originalRows)
        coordinator.applyFontPreference(preference, to: terminal)
        XCTAssertEqual(terminal.font.pointSize, 8, "A SwiftUI refresh must preserve session zoom")

        pinch.scale = 10
        coordinator.handlePinch(pinch)
        XCTAssertEqual(terminal.font.pointSize, 24)
        XCTAssertLessThan(terminal.getTerminal().cols, originalCols)
        XCTAssertLessThan(terminal.getTerminal().rows, originalRows)
        XCTAssertTrue(terminal.font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))

        coordinator.applyFontPreference(preference.withSize(16), to: terminal)
        XCTAssertEqual(terminal.font.pointSize, 16, "An explicit font setting should still take effect")
    }

    func testLightPaletteWhitesHaveReadableContrastAndDarkPaletteIsRestored() {
        let palette = TerminalTheme.lightANSIColors
        XCTAssertEqual(palette.count, 16)
        for color in palette {
            func linear(_ channel: UInt16) -> Double {
                let value = Double(channel) / 65535
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
                + 0.0722 * linear(color.blue)
            XCTAssertGreaterThanOrEqual(1.05 / (luminance + 0.05), 4.5)
        }
        let terminal = TerminalViewWrapper.makeTerminalView(backgroundColor: .white)
        let coordinator = TerminalViewWrapper.Coordinator(bridge: SSHTerminalBridge())
        // OSC palette queries exercise installColors rather than only checking constants.
        let recorder = PaletteQueryDelegate()
        terminal.terminalDelegate = recorder
        coordinator.applyPalette(to: terminal, light: true)
        terminal.feed(text: "\u{1B}]4;7;?\u{1B}\\\u{1B}]4;15;?\u{1B}\\")
        XCTAssertTrue(recorder.response.contains("rgb:4b4b/5555/6363"))
        XCTAssertTrue(recorder.response.contains("rgb:3737/4141/5151"))
        recorder.response = ""
        coordinator.applyPalette(to: terminal, light: false)
        terminal.feed(text: "\u{1B}]4;15;?\u{1B}\\")
        XCTAssertTrue(recorder.response.contains("rgb:e9e9/ebeb/ebeb"))
    }

    func testResizingRedrawsGlyphsWithoutStretchingTheCachedScreen() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        let terminal = TerminalViewWrapper.makeTerminalView(backgroundColor: .white)
        terminal.frame = CGRect(x: 0, y: 0, width: 320, height: 520)
        controller.view.addSubview(terminal)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let configuredMode = terminal.contentMode
        let configuredGravity = terminal.layer.contentsGravity
        let configuredRedraw = terminal.layer.needsDisplayOnBoundsChange
        terminal.contentMode = .scaleToFill
        terminal.layer.contentsGravity = .resize
        terminal.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        terminal.nativeForegroundColor = .red
        terminal.feed(text: "\u{1B}[?25l\u{1B}[2J\u{1B}[HHHHH")
        terminal.layoutIfNeeded()
        terminal.setNeedsDisplay()
        terminal.layer.displayIfNeeded()
        let original = try glyphBounds(in: terminal.layer)
        XCTAssertGreaterThan(original.height, 5)

        let stretched = try await glyphsDuringResize(terminal, toHeight: 260)
        XCTAssertGreaterThan(stretched.height, original.height * 1.25,
                             "The control must reproduce the cached-bitmap stretching.")
        terminal.contentMode = configuredMode
        terminal.layer.contentsGravity = configuredGravity
        terminal.layer.needsDisplayOnBoundsChange = configuredRedraw

        for height in [CGFloat(520), 260, 520, 260] {
            let resized = try await glyphsDuringResize(terminal, toHeight: height)
            XCTAssertEqual(resized.width, original.width, accuracy: 1)
            XCTAssertEqual(resized.height, original.height, accuracy: 1,
                           "Terminal text must keep its shape while the keyboard changes the viewport.")
        }
    }

    private func glyphsDuringResize(_ view: UIView, toHeight height: CGFloat) async throws -> CGRect {
        let oldBounds = view.bounds
        var target = oldBounds
        target.size.height = height
        UIView.performWithoutAnimation {
            view.bounds = target
            view.layoutIfNeeded()
            view.setNeedsDisplay()
            view.layer.displayIfNeeded()
        }
        let animation = CABasicAnimation(keyPath: "bounds")
        animation.fromValue = NSValue(cgRect: oldBounds)
        animation.toValue = NSValue(cgRect: target)
        animation.duration = 1
        animation.speed = 0
        animation.timeOffset = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        view.layer.add(animation, forKey: "keyboard-resize-test")
        defer { view.layer.removeAnimation(forKey: "keyboard-resize-test") }
        CATransaction.flush()
        let midpoint = (oldBounds.height + height) / 2
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let layer = view.layer.presentation() else { return false }
            return abs(layer.bounds.height - midpoint) < 1
        }, object: nil)], timeout: 3)
        return try glyphBounds(in: XCTUnwrap(view.layer.presentation()))
    }

    private func glyphBounds(in layer: CALayer) throws -> CGRect {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: layer.bounds.size, format: format).image { context in
            // Composite transparent cached-layer space over the fixture's white parent.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: layer.bounds.size))
            layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Terminal viewport \(Int(layer.bounds.height))pt"
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for y in [0, height - 1] {
            let offset = (y * width + width - 1) * 4
            XCTAssertTrue(pixels[offset..<(offset + 4)].allSatisfy { $0 >= 250 },
                          "Newly exposed viewport space must keep the terminal background during resizing.")
        }
        var bounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if pixels[offset] > 180 && pixels[offset + 1] < 90 && pixels[offset + 2] < 90 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        XCTAssertFalse(bounds.isNull, "The fixture must contain rendered terminal text.")
        return bounds
    }
}

private final class SimulatedPinchGestureRecognizer: UIPinchGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
}

private final class PaletteQueryDelegate: NSObject, TerminalViewDelegate {
    var response = ""
    func send(source: TerminalView, data: ArraySlice<UInt8>) { response += String(decoding: data, as: UTF8.self) }
    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
