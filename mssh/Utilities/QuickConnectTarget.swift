import Foundation
import Network

struct QuickConnectTarget: Identifiable, Equatable {
    let username: String
    let host: String
    let port: Int

    var id: String { "\(username)@\(host):\(port)" }

    init(host: String, port: Int, username: String) throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        try self.init("\(username)@\(address):\(port)")
    }

    init(_ input: String) throws {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("ssh://") { text = String(text.dropFirst(6)) }
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !text.contains(where: { "/?#\\".contains($0) }) else { throw ParseError.invalidAddress }

        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw ParseError.invalidAddress }
        let user = parts.count == 2 ? String(parts[0]) : "root"
        guard !user.isEmpty, !user.contains(where: { ":[]".contains($0) }) else {
            throw ParseError.invalidAddress
        }
        let authority = String(parts.last ?? "")
        var parsedHost: String
        var portText: String?
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { throw ParseError.invalidAddress }
            parsedHost = String(authority[authority.index(after: authority.startIndex)..<close])
            guard IPv6Address(parsedHost) != nil else { throw ParseError.invalidAddress }
            let suffix = authority[authority.index(after: close)...]
            if !suffix.isEmpty {
                guard suffix.first == ":" else { throw ParseError.invalidAddress }
                portText = String(suffix.dropFirst())
            }
        } else if authority.filter({ $0 == ":" }).count > 1 {
            guard IPv6Address(authority) != nil else { throw ParseError.invalidAddress }
            parsedHost = authority
        } else if let colon = authority.firstIndex(of: ":") {
            parsedHost = String(authority[..<colon])
            portText = String(authority[authority.index(after: colon)...])
        } else {
            parsedHost = authority
        }
        guard !parsedHost.isEmpty, !parsedHost.contains(where: { "[]".contains($0) }) else {
            throw ParseError.invalidAddress
        }
        var parsedPort = 22
        if let portText {
            guard !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(portText), (1...65535).contains(value) else { throw ParseError.invalidAddress }
            parsedPort = value
        }
        username = user
        host = parsedHost
        port = parsedPort
    }

    enum ParseError: LocalizedError {
        case invalidAddress

        var errorDescription: String? {
            String(localized: "Enter user@host:port or ssh://user@host:port. For IPv6 with a port, use user@[address]:port.")
        }
    }
}
