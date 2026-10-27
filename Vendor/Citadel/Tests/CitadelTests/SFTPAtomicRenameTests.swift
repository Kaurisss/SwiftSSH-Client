import XCTest
import NIO
import NIOEmbedded
import Logging
@testable import Citadel

final class SFTPAtomicRenameTests: XCTestCase {
    private let extensionName = "posix-rename@openssh.com"

    private func encode(_ message: SFTPMessage) throws -> ByteBuffer {
        var buffer = ByteBuffer()
        try SFTPMessageSerializer().encode(data: message, out: &buffer)
        return buffer
    }

    private func parse(_ bytes: [UInt8]) throws -> SFTPMessage {
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(SFTPMessageParser()))
        defer { _ = try? channel.finish() }
        // Exercise a partial header as well as the complete packet.
        try channel.writeInbound(ByteBuffer(bytes: bytes.prefix(3)))
        XCTAssertNil(try channel.readInbound(as: SFTPMessage.self))
        try channel.writeInbound(ByteBuffer(bytes: bytes.dropFirst(3)))
        return try XCTUnwrap(channel.readInbound(as: SFTPMessage.self))
    }

    func testExtendedRenameWireFormatAndParser() throws {
        let paths: [UInt8] = [0, 0, 0, 2, 47, 97, 0, 0, 0, 2, 47, 98]
        let expected: [UInt8] = [0, 0, 0, 45, 200, 1, 2, 3, 4, 0, 0, 0, 24]
            + Array(extensionName.utf8) + paths
        let request = SFTPRequest.extended(.init(
            requestId: 0x01020304, name: extensionName, data: ByteBuffer(bytes: paths)
        ))
        XCTAssertEqual(request.requestId, 0x01020304)
        XCTAssertEqual(Array(try encode(request.makeMessage()).readableBytesView), expected)
        guard case .extended(let parsed) = try parse(expected) else {
            return XCTFail("Expected EXTENDED")
        }
        XCTAssertEqual(parsed.requestId, 0x01020304)
        XCTAssertEqual(parsed.name, extensionName)
        // The extension body is raw bytes, not another length-prefixed SSH string.
        XCTAssertEqual(Array(parsed.data.readableBytesView), paths)
    }

    func testLstatWireFormatAndParser() throws {
        let expected: [UInt8] = [0, 0, 0, 11, 7, 1, 2, 3, 4, 0, 0, 0, 2, 47, 97]
        let request = SFTPRequest.lstat(.init(requestId: 0x01020304, path: "/a"))
        XCTAssertEqual(request.requestId, 0x01020304)
        XCTAssertEqual(Array(try encode(request.makeMessage()).readableBytesView), expected)
        guard case .lstat(let parsed) = try parse(expected) else {
            return XCTFail("Expected LSTAT rather than STAT")
        }
        XCTAssertEqual(parsed.requestId, 0x01020304)
        XCTAssertEqual(parsed.path, "/a")
    }

    func testFstatWireFormatAndParser() throws {
        let expected: [UInt8] = [0, 0, 0, 11, 8, 1, 2, 3, 4, 0, 0, 0, 2, 0, 255]
        let request = SFTPRequest.fstat(.init(
            requestId: 0x01020304, handle: ByteBuffer(bytes: [0, 255])
        ))
        XCTAssertEqual(Array(try encode(request.makeMessage()).readableBytesView), expected)
        guard case .fstat(let parsed) = try parse(expected) else {
            return XCTFail("Expected FSTAT")
        }
        XCTAssertEqual(parsed.requestId, 0x01020304)
        XCTAssertEqual(Array(parsed.handle.readableBytesView), [0, 255])
    }

    func testMalformedExtendedNameIsRejected() throws {
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(SFTPMessageParser()))
        defer { _ = try? channel.finish() }
        // Complete packet, but its extension name claims two bytes and contains only one.
        let bytes: [UInt8] = [0, 0, 0, 10, 200, 0, 0, 0, 1, 0, 0, 0, 2, 97]
        XCTAssertThrowsError(try channel.writeInbound(ByteBuffer(bytes: bytes))) { error in
            guard case SFTPError.invalidPayload(type: .extended) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // An in-memory transport lets the public async APIs exercise the real response handler.
    private func withClient(
        extensions: [(String, String)] = [("posix-rename@openssh.com", "1")],
        _ body: (SFTPClient, NIOAsyncTestingChannel) async throws -> Void
    ) async throws {
        let channel = NIOAsyncTestingChannel()
        let (client, responses) = try await channel.eventLoop.submit {
            let responses = SFTPResponses(sftpVersion: channel.eventLoop.makePromise())
            let logger = Logger(label: "SFTPAtomicRenameTests")
            try channel.pipeline.syncOperations.addHandler(
                SFTPClientInboundHandler(responses: responses, logger: logger)
            )
            return (SFTPClient(channel: channel, responses: responses, logger: logger), responses)
        }.get()
        do {
            try await channel.writeInbound(SFTPMessage.version(.init(version: .v3, extensionData: extensions)))
            try await body(client, channel)
            try await channel.eventLoop.submit { responses.close() }.get()
            let remaining = try await channel.finish()
            guard case .clean = remaining else {
                return XCTFail("Unconsumed messages remain in the test transport")
            }
        } catch {
            try? await channel.eventLoop.submit { responses.close() }.get()
            _ = try? await channel.finish(acceptAlreadyClosed: true)
            throw error
        }
    }

    func testUnsupportedExtensionDoesNotSendRename() async throws {
        for extensions in [[], [(extensionName, "2")], [("another-extension", "1")]] {
            try await withClient(extensions: extensions) { client, channel in
                let supported = try await client.supportsPosixRename()
                XCTAssertFalse(supported)
                do {
                    try await client.posixRename(at: "/a", to: "/b")
                    XCTFail("Expected unsupported")
                } catch SFTPAtomicRenameError.unsupported {
                    // Expected: no destructive fallback or request was sent.
                }
                let outbound = try await channel.readOutbound(as: SFTPMessage.self)
                XCTAssertNil(outbound)
            }
        }
    }

    func testPosixRenameRequiresStatusOK() async throws {
        for code in [SFTPStatusCode.ok, .eof, .permissionDenied, .failure, .unsupportedOperation] {
            try await withClient { client, channel in
                let supported = try await client.supportsPosixRename()
                XCTAssertTrue(supported)
                let operation = Task { try await client.posixRename(at: "/a", to: "/b") }
                guard case .extended(var request) = try await channel.waitForOutboundWrite(as: SFTPMessage.self) else {
                    return XCTFail("Expected EXTENDED")
                }
                XCTAssertEqual(request.name, self.extensionName)
                XCTAssertEqual(request.data.readSSHString(), "/a")
                XCTAssertEqual(request.data.readSSHString(), "/b")
                XCTAssertEqual(request.data.readableBytes, 0)
                try await channel.writeInbound(SFTPMessage.status(.init(
                    requestId: request.requestId, errorCode: code, message: "test status", languageTag: "EN"
                )))
                do {
                    try await operation.value
                    XCTAssertEqual(code, .ok)
                } catch let status as SFTPMessage.Status {
                    // The inbound handler rejects failure statuses before returning a response.
                    XCTAssertNotEqual(code, .ok)
                    XCTAssertEqual(status.errorCode, code)
                } catch SFTPError.errorStatus(let status) {
                    // EOF passes the inbound handler, but is never a successful rename.
                    XCTAssertEqual(code, .eof)
                    XCTAssertEqual(status.errorCode, .eof)
                }
            }
        }
    }

    func testPosixRenameRejectsNonStatusResponse() async throws {
        try await withClient { client, channel in
            let operation = Task { try await client.posixRename(at: "/a", to: "/b") }
            guard case .extended(let request) = try await channel.waitForOutboundWrite(as: SFTPMessage.self) else {
                return XCTFail("Expected EXTENDED")
            }
            try await channel.writeInbound(SFTPMessage.attributes(.init(
                requestId: request.requestId, attributes: .init(size: 99)
            )))
            do {
                try await operation.value
                XCTFail("Expected invalid response")
            } catch SFTPError.invalidResponse { }
        }
    }

    func testLstatReturnsLinkAttributesAndPropagatesMissingFile() async throws {
        for missing in [false, true] {
            try await withClient { client, channel in
                let operation = Task { try await client.lstat(at: "/link") }
                guard case .lstat(let request) = try await channel.waitForOutboundWrite(as: SFTPMessage.self) else {
                    return XCTFail("Expected LSTAT rather than following the link")
                }
                XCTAssertEqual(request.path, "/link")
                if missing {
                    try await channel.writeInbound(SFTPMessage.status(.init(
                        requestId: request.requestId, errorCode: .noSuchFile, message: "missing", languageTag: "EN"
                    )))
                } else {
                    var attributes = SFTPFileAttributes(size: 12)
                    attributes.permissions = 0o120777
                    try await channel.writeInbound(SFTPMessage.attributes(.init(
                        requestId: request.requestId, attributes: attributes
                    )))
                }
                do {
                    let attributes = try await operation.value
                    XCTAssertFalse(missing)
                    XCTAssertEqual(attributes.permissions, 0o120777)
                    XCTAssertEqual(attributes.size, 12)
                } catch let status as SFTPMessage.Status {
                    XCTAssertTrue(missing)
                    XCTAssertEqual(status.errorCode, .noSuchFile)
                }
            }
        }
    }

    func testReadAttributesUsesOpenHandleAfterPathReplacement() async throws {
        try await withClient { client, channel in
            let handle = ByteBuffer(bytes: [0, 255])
            let file = SFTPFile(client: client, path: "/replaced-path", handle: handle)
            let operation = Task { try await file.readAttributes() }
            let request = try await channel.waitForOutboundWrite(as: SFTPMessage.self)
            let requestID: UInt32
            let size: UInt64
            switch request {
            case .fstat(let command):
                XCTAssertEqual(command.handle, handle)
                requestID = command.requestId
                size = 12 // The originally opened file.
            case .stat(let command):
                requestID = command.requestId
                size = 99 // A different file now occupies the same path.
            default:
                return XCTFail("Expected an attributes request")
            }
            try await channel.writeInbound(SFTPMessage.attributes(.init(
                requestId: requestID, attributes: .init(size: size)
            )))
            let attributes = try await operation.value
            XCTAssertEqual(attributes.size, 12)
        }
    }
}
