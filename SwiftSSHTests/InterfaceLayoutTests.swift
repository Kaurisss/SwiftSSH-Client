import SwiftUI
import XCTest
@testable import SwiftSSH

@MainActor
final class InterfaceLayoutTests: XCTestCase {
    func testHostKeyPromptsAtNarrowWidthAndLargeText() async throws {
        let fingerprint = "SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"
        let newHost = HostKeyPromptView(promptType: .newHost(fingerprint: fingerprint, keyType: "ssh-ed25519"),
            host: "2001:db8:1234:5678::1", port: 2222, onAccept: {}, onReject: {})
        try await snapshot(newHost.environment(\.locale, Locale(identifier: "zh_Hans"))
            .preferredColorScheme(.light), named: "Host-Key-Narrow-Light")
        let changed = HostKeyPromptView(promptType: .changedKey(oldFingerprint: fingerprint,
            newFingerprint: "SHA256:ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210abcdefghi", keyType: "ssh-ed25519"),
            host: "production.example.com", port: 22, onAccept: {}, onReject: {})
        try await snapshot(changed.environment(\.locale, Locale(identifier: "zh_Hans"))
            .environment(\.dynamicTypeSize, .accessibility3).preferredColorScheme(.dark),
            named: "Host-Key-Large-Text-Dark")
    }

    func testFileDetailsKeepLongPathAvailableAtLargeText() async throws {
        let item = SFTPFileItem(name: "production-configuration-backup.json",
            path: "/home/developer/projects/production/configuration/production-configuration-backup.json",
            isDirectory: false, size: 4096, modifiedDate: Date(timeIntervalSince1970: 1792689687), permissions: 0o100640)
        try await snapshot(SFTPFileInfoView(item: item)
            .environment(\.locale, Locale(identifier: "zh_Hans"))
            .environment(\.dynamicTypeSize, .accessibility3).preferredColorScheme(.dark),
            named: "File-Details-Large-Text-Dark")
    }
}
