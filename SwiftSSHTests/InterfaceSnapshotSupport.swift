import SwiftUI
import UIKit
import XCTest

extension XCTestCase {
    @MainActor
    func snapshot<Content: View>(_ view: Content, named name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 740)
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(host.view.bounds.width, 320)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
