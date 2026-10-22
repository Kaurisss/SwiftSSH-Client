import XCTest
@testable import SwiftSSH

final class QuickConnectTargetTests: XCTestCase {
    func testHostAndUserAndOptionalPort() throws {
        let host = try QuickConnectTarget(" example.com \n")
        XCTAssertEqual(host.username, "root")
        XCTAssertEqual(host.host, "example.com")
        XCTAssertEqual(host.port, 22)
        let target = try QuickConnectTarget("alice@server.local:2222")
        XCTAssertEqual(target.username, "alice")
        XCTAssertEqual(target.host, "server.local")
        XCTAssertEqual(target.port, 2222)
        XCTAssertEqual(try QuickConnectTarget("SSH://alice@server.local:2222"), target)
    }

    func testIPv6NeverTreatsAnAddressSegmentAsAPort() throws {
        let raw = try QuickConnectTarget("2001:db8::22")
        XCTAssertEqual(raw.host, "2001:db8::22")
        XCTAssertEqual(raw.port, 22)
        let bracketed = try QuickConnectTarget("alice@[2001:db8::22]:2200")
        XCTAssertEqual(bracketed.host, "2001:db8::22")
        XCTAssertEqual(bracketed.port, 2200)
        XCTAssertEqual(bracketed.username, "alice")
        XCTAssertEqual(try QuickConnectTarget("[::1]").host, "::1")
    }

    func testMalformedInputDoesNotSilentlyFallBackToPort22() {
        for input in ["", " ", "@host", "alice@", "a@b@host", "host:", "host:0",
                      "host:65536", "host:-1", "host:+22", "host:abc", "host:2 2",
                      "host:999999999999999999999999", "[::1]:", "[example.com]:22",
                      "[::1]suffix", "[::1", "[::1]:22:33", "bad::address", "host/path",
                      "http://host", "ssh://", "host?query", "host#fragment", "a\nb",
                      "user:password@host", "bad\0host", "[host]", "host\\path"] {
            XCTAssertThrowsError(try QuickConnectTarget(input), input)
        }
        XCTAssertNoThrow(try QuickConnectTarget("host:1"))
        XCTAssertNoThrow(try QuickConnectTarget("host:65535"))
    }
}
