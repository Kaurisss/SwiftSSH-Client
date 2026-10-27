# Citadel 0.12.1 — local SFTP safety patch

## Provenance and scope

- Upstream: https://github.com/orlandos-nl/Citadel
- Tag: `0.12.1`
- Exact revision: `ae8562f895de06ccb86fdb1cbb65fd99c8976e12`
- License: upstream MIT license, retained in `Citadel/LICENSE`.
- Included: library sources (`Citadel`, `CCitadelBcrypt`), upstream tests, README,
  `Package.swift`, and the upstream `Package.resolved`.
- Excluded: `.git`, CI files, example sources/targets, build caches and binaries.
- This is a patch to 0.12.1, not a dependency upgrade. The upstream lockfile is
  retained verbatim (including its now-unused example dependency pin).

## Public API

```swift
public enum SFTPAtomicRenameError: Error, Sendable {
    case unsupported
}

// On SFTPClient:
public func lstat(at filePath: String) async throws -> SFTPFileAttributes
public func supportsPosixRename() async throws -> Bool
public func posixRename(at oldPath: String, to newPath: String) async throws
```

`lstat` sends `SSH_FXP_LSTAT` and returns attributes of the final path component
itself rather than following a symbolic link. Failures propagate through the
existing response handler; a non-attributes success response is rejected.

`supportsPosixRename` awaits the negotiated SFTP version and checks for the exact
advertisement `("posix-rename@openssh.com", "1")`.

`posixRename` checks that capability before sending any request. Its
`SSH_FXP_EXTENDED` body is the request ID, SSH-string extension name, then two
SSH-string paths. There is no extra length prefix around the extension body and
no flags field. Only `SSH_FXP_STATUS` with `SSH_FX_OK` succeeds. Other failure
statuses propagate as `SFTPMessage.Status`; EOF, which the existing inbound
handler treats as a response, is explicitly rejected as `SFTPError.errorStatus`.
An unexpected response type throws `SFTPError.invalidResponse`.

The wire model also adds public `SFTPMessage.Extended` (request ID, name and raw
`ByteBuffer` data) and `SFTPMessage.extended`. Like upstream message structs, its
memberwise initializer remains internal. `SSH_FXP_EXTENDED_REPLY` remains
unsupported; the POSIX rename extension uses ordinary STATUS responses.

Existing `SFTPFile.readAttributes()` now uses `SSH_FXP_FSTAT` with the open handle,
not `STAT` with its original pathname. This keeps metadata tied to the opened
file if the pathname is replaced. Its signature and active-handle validation are
unchanged. `SFTPFileAttributes`, including mutable `permissions` and `uidgid`, is
unchanged.

## Unsupported servers and safety boundaries

- A missing advertisement or a version other than `1` makes the capability check
  false and rename throw `SFTPAtomicRenameError.unsupported` without sending a
  request.
- A server advertising support but rejecting the operation returns an error to
  the caller. No retry with ordinary rename or remove-then-rename is attempted.
- Citadel's own server does not advertise or implement this extension. It now
  parses EXTENDED requests and answers `SSH_FX_OP_UNSUPPORTED` with the matching
  request ID instead of treating the message type as an invalid payload.
- Existing ordinary rename/upload behavior is unchanged.
- Atomic rename replaces a directory entry on the same remote filesystem. It
  does not implement conflict detection, preserve destination metadata by itself,
  or provide a durability/fsync guarantee. The application owns those policies.
  A disconnected request may have executed remotely before its response was lost.

## Files changed relative to upstream

Paths below are relative to `Vendor/Citadel`:

| File | Change |
| --- | --- |
| `Package.swift` | Remove the omitted server example target and its ColorizeSwift dependency; add NIOEmbedded to tests; remove stale local-path comment. Library dependency versions and deployment targets remain unchanged. |
| `Sources/Citadel/SFTP/Client/SFTPClient.swift` | Three public operations, unsupported error, and fileprivate-to-internal initializer visibility for in-memory tests. |
| `Sources/Citadel/SFTP/Client/SFTPFile.swift` | Read metadata using FSTAT on the current handle. |
| `Sources/Citadel/SFTP/SFTPMessage.swift` | LSTAT request plumbing, EXTENDED message/request plumbing, exhaustive type/debug/response switches. |
| `Sources/Citadel/SFTP/SFTPSerializer.swift` | Serialize EXTENDED name plus raw body. |
| `Sources/Citadel/SFTP/SFTPMessageParser.swift` | Parse EXTENDED name and retain the remaining payload as raw body. |
| `Sources/Citadel/SFTP/Server/SFTPServerInboundHandler.swift` | Reply unsupported to EXTENDED using the existing inbound handler's `NIOAny` outbound convention. |
| `Tests/CitadelTests/SFTPAtomicRenameTests.swift` | New focused in-memory tests. |

## Verification

Run on macOS with the Swift toolchain required by the package:

```sh
cd SwiftSSH/Vendor/Citadel
swift test --filter SFTPAtomicRenameTests
```

The tests cover independently specified wire bytes and fragmented parser input
for EXTENDED, LSTAT and FSTAT; malformed EXTENDED names; supported and unsupported
advertisements; no request on unsupported servers; OK, EOF, permission-denied,
failure and unsupported STATUS responses; unexpected rename response types;
LSTAT attributes/missing files; and open-handle metadata after pathname
replacement. NIOEmbedded/NIOAsyncTestingChannel provide the in-memory transport;
no SSH server, credentials, remote files or network sockets are used.

Static verification performed on Windows: checked the exact upstream revision
and tag, reviewed the limited upstream diff and all affected switches, checked
packet lengths against literal test bytes, checked package target/source layout,
and ran whitespace checks. The server's outbound write uses
`NIOAny(SFTPMessage.status(...))`; it does not call `wrapOutboundOut` on an
inbound-only handler.

Swift is not installed in this environment. Compilation and XCTest execution
remain required on macOS; neither is claimed as passed here. Real-server atomic
replacement and disconnect behavior are application integration checks outside
this patch's in-memory tests.
