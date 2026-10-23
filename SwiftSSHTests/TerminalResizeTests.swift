import SwiftUI
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class TerminalResizeTests: XCTestCase {
    func testResizingRedrawsGlyphsWithoutStretchingTheCachedScreen() async throws {
        let bridge = SSHTerminalBridge()
        let host = UIHostingController(rootView: TerminalViewWrapper(bridge: bridge))
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 260)
        host.view.layoutIfNeeded()
        let terminal = try XCTUnwrap(bridge.terminalView)
        terminal.nativeBackgroundColor = .white
        terminal.nativeForegroundColor = .red
        terminal.feed(text: "\u{1B}[?25l\u{1B}[2J\u{1B}[HHHHH")
        try await Task.sleep(for: .milliseconds(100))
        terminal.layoutIfNeeded()
        terminal.layer.displayIfNeeded()
        let original = try glyphBounds(in: terminal)
        XCTAssertGreaterThan(original.height, 5)

        // A keyboard transition can composite the resized layer before its next layout pass.
        for height in [CGFloat(520), 260, 520, 260] {
            terminal.bounds.size.height = height
            terminal.layer.displayIfNeeded()
            let resized = try glyphBounds(in: terminal)
            XCTAssertEqual(resized.width, original.width, accuracy: 1)
            XCTAssertEqual(resized.height, original.height, accuracy: 1,
                           "Terminal text must keep its shape while the keyboard changes the viewport.")
            terminal.layoutIfNeeded()
            terminal.layer.displayIfNeeded()
        }
    }

    private func glyphBounds(in view: UIView) throws -> CGRect {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
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
