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

    func testReplacingCredentialsUpdatesTheSameDeviceLocalItem() throws {
        let id = UUID().uuidString
        defer {
            KeychainService.deleteItem(account: "pwd-\(id)")
            KeychainService.deletePrivateKey(id: id)
            KeychainService.deleteItem(account: "hostkey-\(id):22")
        }
        try KeychainService.savePassword(for: id, password: "first")
        try KeychainService.savePassword(for: id, password: "second")
        XCTAssertEqual(KeychainService.getPassword(for: id), "second")
        try KeychainService.savePrivateKey(id: id, pemData: Data("first".utf8))
        try KeychainService.savePrivateKey(id: id, pemData: Data("second".utf8))
        XCTAssertEqual(KeychainService.getPrivateKey(id: id), Data("second".utf8))
        try KeychainService.saveHostKey(host: id, port: 22, keyData: Data("first".utf8))
        try KeychainService.saveHostKey(host: id, port: 22, keyData: Data("second".utf8))
        XCTAssertEqual(KeychainService.getHostKey(host: id, port: 22), Data("second".utf8))
        XCTAssertEqual(synchronizedItemStatus(account: "pwd-\(id)"), errSecItemNotFound)
        XCTAssertEqual(synchronizedItemStatus(account: "key-\(id)"), errSecItemNotFound)
        XCTAssertEqual(synchronizedItemStatus(account: "hostkey-\(id):22"), errSecItemNotFound)
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
