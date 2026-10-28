import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    var sessions: [SessionViewModel] = []
    var activeSessionID: UUID?
    var sessionPendingClose: SessionViewModel?

    var activeSession: SessionViewModel? {
        sessions.first { $0.id == activeSessionID }
    }

    func createSession(for profile: ConnectionProfile) -> SessionViewModel {
        let session = SessionViewModel(profile: profile)
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    func closeSession(_ id: UUID) {
        if sessionPendingClose?.id == id { sessionPendingClose = nil }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].disconnect()
            sessions.remove(at: index)
        }
        if activeSessionID == id {
            activeSessionID = sessions.last?.id
        }
    }

    func requestCloseSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if session.isConnected {
            sessionPendingClose = session
        } else {
            closeSession(id)
        }
    }

    func closeAllSessions() {
        sessionPendingClose = nil
        for session in sessions {
            session.disconnect()
        }
        sessions.removeAll()
        activeSessionID = nil
    }
}
