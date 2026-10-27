import Foundation
import XCTest
@testable import SwiftSSH

final class SFTPTextDocumentTests: XCTestCase {
    private let formats: [(String.Encoding, [UInt8])] = [
        (.utf8, []),
        (.utf8, [0xEF, 0xBB, 0xBF]),
        (.utf16LittleEndian, [0xFF, 0xFE]),
        (.utf16BigEndian, [0xFE, 0xFF])
    ]

    private func bytes(_ text: String, encoding: String.Encoding, bom: [UInt8]) throws -> Data {
        Data(bom) + (try XCTUnwrap(text.data(using: encoding, allowLossyConversion: false)))
    }

    func testEmptyAndUnicodeDocumentsRoundTripEveryEncodingAndNewlineStyle() throws {
        for (encoding, bom) in formats {
            for ending in ["\n", "\r\n", "\r"] {
                for content in ["", "café 中文 😀 e\u{301} \u{FFFD}", "\tfirst\nsecond", "first\n", "first\n\n", "\n"] {
                    let original = content.replacingOccurrences(of: "\n", with: ending)
                    let data = try bytes(original, encoding: encoding, bom: bom)
                    let document = try SFTPTextDocument(data: data)
                    XCTAssertEqual(document.text, content)
                    XCTAssertEqual(document.lineEnding, content.contains("\n") ? ending : "\n")
                    XCTAssertEqual(try document.encode(document.text), data)
                }
            }
        }
    }

    func testKnownUnicodeByteSequencesRoundTrip() throws {
        let fixtures: [[UInt8]] = [
            [0xC3, 0xA9, 0xF0, 0x9F, 0x98, 0x80],
            [0xEF, 0xBB, 0xBF, 0xC3, 0xA9, 0xF0, 0x9F, 0x98, 0x80],
            [0xFF, 0xFE, 0xE9, 0x00, 0x3D, 0xD8, 0x00, 0xDE],
            [0xFE, 0xFF, 0x00, 0xE9, 0xD8, 0x3D, 0xDE, 0x00]
        ]
        for fixture in fixtures {
            let document = try SFTPTextDocument(data: Data(fixture))
            XCTAssertEqual(document.text, "é😀")
            XCTAssertEqual(try document.encode(document.text), Data(fixture))
        }
    }

    func testEditsPreserveEncodingAndNewlinesWithoutAddingOrRemovingFinalNewlines() throws {
        for (encoding, bom) in formats {
            for ending in ["\n", "\r\n", "\r"] {
                let original = try bytes("old\(ending)text", encoding: encoding, bom: bom)
                let document = try SFTPTextDocument(data: original)
                for edit in ["", "新 😀", "new\ntext", "new\ntext\n", "new\ntext\n\n"] {
                    let expected = try bytes(edit.replacingOccurrences(of: "\n", with: ending), encoding: encoding, bom: bom)
                    XCTAssertEqual(try document.encode(edit), expected)
                }
            }
        }
    }

    func testDocumentsWithoutNewlinesDefaultToLFWhenEdited() throws {
        for (encoding, bom) in formats {
            for original in ["", "hello"] {
                let document = try SFTPTextDocument(data: bytes(original, encoding: encoding, bom: bom))
                XCTAssertEqual(document.lineEnding, "\n")
                XCTAssertEqual(try document.encode("a\nb\n"), try bytes("a\nb\n", encoding: encoding, bom: bom))
            }
        }
    }

    func testInvalidAndUnsupportedEncodingsAreRejected() {
        let fixtures: [[UInt8]] = [
            [0xFF], [0x80], [0xC0, 0xAF], [0xE2, 0x82],
            [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80],
            [0xEF, 0xBB, 0xBF, 0xFF],
            [0xFF, 0xFE, 0x61], [0xFE, 0xFF, 0x00],
            [0xFF, 0xFE, 0x00, 0xD8], [0xFE, 0xFF, 0xD8, 0x00],
            [0xFF, 0xFE, 0x00, 0xDC], [0xFE, 0xFF, 0xDC, 0x00],
            [0xFF, 0xFE, 0x00, 0x00], [0x00, 0x00, 0xFE, 0xFF],
            [0xFF, 0xFE, 0x00, 0x00, 0x61, 0x00, 0x00, 0x00],
            [0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x61],
            [0x61, 0x00], [0x00, 0x61]
        ]
        for fixture in fixtures {
            XCTAssertThrowsError(try SFTPTextDocument(data: Data(fixture)), "\(fixture)")
        }
    }

    func testBinaryControlsAreRejectedOnReadAndWrite() throws {
        let document = try SFTPTextDocument(data: Data())
        for value in Array(0...0x1F) + Array(0x7F...0x9F) where ![9, 10, 13].contains(value) {
            let content = "a" + String(try XCTUnwrap(UnicodeScalar(value))) + "b"
            for (encoding, bom) in formats {
                XCTAssertThrowsError(try SFTPTextDocument(data: bytes(content, encoding: encoding, bom: bom)))
            }
            XCTAssertThrowsError(try document.encode(content))
        }
    }

    func testMixedNewlinesAreRejectedOnReadAndWrite() throws {
        let document = try SFTPTextDocument(data: Data())
        for content in ["a\r\nb\nc", "a\r\nb\rc", "a\rb\nc", "\r\r\n", "\n\r", "a\r\nb\rc\nd"] {
            for (encoding, bom) in formats {
                XCTAssertThrowsError(try SFTPTextDocument(data: bytes(content, encoding: encoding, bom: bom)))
            }
            XCTAssertThrowsError(try document.encode(content))
        }
    }

    func testInputAndOutputLimitsIncludeBOMAndEncodedByteWidth() throws {
        XCTAssertEqual(SFTPTextDocument.maximumBytes, 2 * 1024 * 1024)
        for (encoding, bom) in formats {
            let width = encoding == .utf8 ? 1 : 2
            let count = (SFTPTextDocument.maximumBytes - bom.count) / width
            let content = String(repeating: "a", count: count)
            let data = try bytes(content, encoding: encoding, bom: bom)
            XCTAssertEqual(data.count, SFTPTextDocument.maximumBytes)
            let document = try SFTPTextDocument(data: data)
            XCTAssertEqual(try document.encode(content), data)
            XCTAssertThrowsError(try SFTPTextDocument(data: data + Data([0x61])))
            XCTAssertThrowsError(try document.encode(content + "a"))
        }
    }

    func testOutputLimitAccountsForCRLFExpansionAndUnicode() throws {
        let crlf = try SFTPTextDocument(data: Data("a\r\n".utf8))
        let atLimit = String(repeating: "\n", count: SFTPTextDocument.maximumBytes / 2)
        XCTAssertEqual(try crlf.encode(atLimit).count, SFTPTextDocument.maximumBytes)
        XCTAssertThrowsError(try crlf.encode(atLimit + "\n"))

        let utf8 = try SFTPTextDocument(data: Data())
        let unicode = String(repeating: "😀", count: SFTPTextDocument.maximumBytes / 4)
        XCTAssertEqual(try utf8.encode(unicode).count, SFTPTextDocument.maximumBytes)
        XCTAssertThrowsError(try utf8.encode(unicode + "😀"))
    }
}
