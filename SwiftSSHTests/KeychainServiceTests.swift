import Foundation
import Security
import XCTest
@testable import SwiftSSH

final class KeychainServiceTests: XCTestCase {
    func testPasswordIsDeviceLocal() throws {
        let id = UUID().uuidString
        defer { KeychainService.deleteItem(account: "pwd-\(id)") }

        try KeychainService.savePassword(for: id, password: "fixture-password")
        XCTAssertEqual(KeychainService.getPassword(for: id), "fixture-password")
        XCTAssertEqual(synchronizedItemStatus(account: "pwd-\(id)"), errSecItemNotFound)
    }

    func testPrivateKeyIsDeviceLocalAndCanBeDeleted() throws {
        let id = UUID().uuidString
        defer { KeychainService.deletePrivateKey(id: id) }
        let bytes = Data("fixture-private-key".utf8)

        try KeychainService.savePrivateKey(id: id, pemData: bytes)
        XCTAssertEqual(KeychainService.getPrivateKey(id: id), bytes)
        XCTAssertEqual(synchronizedItemStatus(account: "key-\(id)"), errSecItemNotFound)

        KeychainService.deletePrivateKey(id: id)
        XCTAssertNil(KeychainService.getPrivateKey(id: id))
    }

    private func synchronizedItemStatus(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.example.swiftssh",
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
    }
}
