import SwiftUI
import UIKit
import XCTest
@testable import SwiftSSH

@MainActor
final class TerminalResizeTests: XCTestCase {
    func testResizingRedrawsGlyphsWithoutStretchingTheCachedScreen() async throws {
        let bridge = SSHTerminalBridge()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: TerminalViewWrapper(bridge: bridge)
            .frame(width: 320, height: 260))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let terminal = try XCTUnwrap(bridge.terminalView)
        let configuredMode = terminal.contentMode
        terminal.contentMode = .scaleToFill
        terminal.nativeBackgroundColor = .white
        terminal.nativeForegroundColor = .red
        terminal.feed(text: "\u{1B}[?25l\u{1B}[2J\u{1B}[HHHHH")
        terminal.layoutIfNeeded()
        terminal.setNeedsDisplay()
        terminal.layer.displayIfNeeded()
        let original = try glyphBounds(in: terminal)
        XCTAssertGreaterThan(original.height, 5)

        terminal.bounds.size.height = 520
        terminal.layer.displayIfNeeded()
        let stretched = try glyphBounds(in: terminal)
        XCTAssertGreaterThan(stretched.height, original.height * 1.5,
                             "The control must reproduce the cached-bitmap stretching.")
        terminal.bounds.size.height = 260
        terminal.contentMode = configuredMode
        terminal.layoutIfNeeded()
        terminal.setNeedsDisplay()
        terminal.layer.displayIfNeeded()

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
        let attachment = XCTAttachment(image: image)
        attachment.name = "Terminal viewport \(Int(view.bounds.height))pt"
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
