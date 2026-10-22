import XCTest
@testable import SwiftSSH

@MainActor
final class SessionManagerTests: XCTestCase {
    func testConnectedSessionRequiresConfirmationAndCancelPreservesIt() {
        let manager = SessionManager()
        let session = manager.createSession(for: ConnectionProfile(label: "Fixture", host: "192.0.2.1"))
        session.isConnected = true
        manager.requestCloseSession(session.id)
        XCTAssertEqual(manager.sessionPendingClose?.id, session.id)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertTrue(session.isConnected)
        manager.sessionPendingClose = nil
        XCTAssertEqual(manager.activeSessionID, session.id)
        XCTAssertEqual(manager.sessions.count, 1)
        manager.closeAllSessions()
    }

    func testConfirmedCloseDisconnectsOnlyRequestedSessionAndSelectsRemainingSession() throws {
        let manager = SessionManager()
        let first = manager.createSession(for: ConnectionProfile(label: "First", host: "192.0.2.1"))
        let second = manager.createSession(for: ConnectionProfile(label: "Second", host: "192.0.2.2"))
        first.isConnected = true
        second.isConnected = true
        manager.requestCloseSession(second.id)
        manager.closeSession(try XCTUnwrap(manager.sessionPendingClose?.id))
        XCTAssertEqual(manager.sessions.map(\.id), [first.id])
        XCTAssertEqual(manager.activeSessionID, first.id)
        XCTAssertTrue(first.isConnected)
        XCTAssertFalse(second.isConnected)
        XCTAssertNil(manager.sessionPendingClose)
        manager.closeAllSessions()
    }

    func testDisconnectedSessionClosesWithoutConfirmationAndUnknownIDDoesNothing() {
        let manager = SessionManager()
        let session = manager.createSession(for: ConnectionProfile(label: "Fixture", host: "192.0.2.1"))
        manager.requestCloseSession(UUID())
        XCTAssertEqual(manager.sessions.count, 1)
        manager.requestCloseSession(session.id)
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertNil(manager.activeSessionID)
        XCTAssertNil(manager.sessionPendingClose)
    }

    func testCloseAllClearsPendingConfirmation() {
        let manager = SessionManager()
        let session = manager.createSession(for: ConnectionProfile(label: "Fixture", host: "192.0.2.1"))
        session.isConnected = true
        manager.requestCloseSession(session.id)
        manager.closeAllSessions()
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertNil(manager.activeSessionID)
        XCTAssertNil(manager.sessionPendingClose)
    }
}
