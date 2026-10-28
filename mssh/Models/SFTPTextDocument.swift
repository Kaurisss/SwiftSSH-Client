import Foundation

struct SFTPTextDocument {
    static let maximumBytes = 2 * 1024 * 1024

    let text: String
    let lineEnding: String

    private let encoding: String.Encoding
    private let byteOrderMark: Data

    init(data: Data) throws {
        guard data.count <= Self.maximumBytes else {
            throw SFTPTextDocumentError.tooLarge
        }
        guard !data.starts(with: [0xFF, 0xFE, 0x00, 0x00]),
              !data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) else {
            throw SFTPTextDocumentError.invalidEncoding
        }

        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            encoding = .utf8
            byteOrderMark = Data([0xEF, 0xBB, 0xBF])
        } else if data.starts(with: [0xFF, 0xFE]) {
            encoding = .utf16LittleEndian
            byteOrderMark = Data([0xFF, 0xFE])
        } else if data.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16BigEndian
            byteOrderMark = Data([0xFE, 0xFF])
        } else {
            encoding = .utf8
            byteOrderMark = Data()
        }

        let payload = Data(data.dropFirst(byteOrderMark.count))
        guard let decoded = String(data: payload, encoding: encoding),
              decoded.data(using: encoding, allowLossyConversion: false) == payload else {
            throw SFTPTextDocumentError.invalidEncoding
        }
        let normalized = try Self.normalize(decoded)
        text = normalized.text
        lineEnding = normalized.lineEnding
    }

    func encode(_ text: String) throws -> Data {
        let normalized = try Self.normalize(text)
        let restored = normalized.text.replacingOccurrences(of: "\n", with: lineEnding)
        guard let payload = restored.data(using: encoding, allowLossyConversion: false),
              String(data: payload, encoding: encoding) == restored else {
            throw SFTPTextDocumentError.invalidEncoding
        }
        guard payload.count <= Self.maximumBytes - byteOrderMark.count else {
            throw SFTPTextDocumentError.tooLarge
        }
        return byteOrderMark + payload
    }

    private static func normalize(_ text: String) throws -> (text: String, lineEnding: String) {
        guard !text.unicodeScalars.contains(where: {
            ($0.value < 0x20 && $0.value != 0x09 && $0.value != 0x0A && $0.value != 0x0D)
                || (0x7F...0x9F).contains($0.value)
        }) else {
            throw SFTPTextDocumentError.binaryContent
        }

        let hasCRLF = text.contains("\r\n")
        let withoutCRLF = text.replacingOccurrences(of: "\r\n", with: "")
        let hasCR = withoutCRLF.contains("\r")
        let hasLF = withoutCRLF.contains("\n")
        guard [hasCRLF, hasCR, hasLF].filter({ $0 }).count <= 1 else {
            throw SFTPTextDocumentError.mixedLineEndings
        }
        let lineEnding = hasCRLF ? "\r\n" : (hasCR ? "\r" : "\n")
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return (normalized, lineEnding)
    }
}

enum SFTPTextDocumentError: LocalizedError {
    case tooLarge
    case invalidEncoding
    case binaryContent
    case mixedLineEndings

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return NSLocalizedString("Text files must be 2 MiB or smaller.", comment: "Text editor file size error")
        case .invalidEncoding:
            return NSLocalizedString("The text encoding is invalid or unsupported. Use UTF-8, or UTF-16 with a byte order mark.", comment: "Text editor encoding error")
        case .binaryContent:
            return NSLocalizedString("The text contains binary control characters.", comment: "Text editor binary content error")
        case .mixedLineEndings:
            return NSLocalizedString("The text contains mixed line endings. Use only LF, CRLF, or CR.", comment: "Text editor newline error")
        }
    }
}
