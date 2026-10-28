import Foundation
import SwiftTerm
import Citadel
import NIO
import NIOSSH

/// Bridges SwiftTerm's TerminalView with Citadel's SSH PTY channel.
/// Handles keepalive, error recovery, and clean disconnect on iOS.
@MainActor
final class SSHTerminalBridge: NSObject, ObservableObject {
    weak var terminalView: TerminalView?

    @Published var isConnected = false
    @Published var statusMessage = String(localized: "Disconnected")

    /// Called on MainActor whenever isConnected or statusMessage changes.
    var onStateChange: ((_ connected: Bool, _ status: String) -> Void)?

    private var connectionTask: Task<Void, Never>?
    private var isDisconnecting = false
    private var connectionID = UUID()

    private struct TerminalSize: Equatable {
        let cols: Int
        let rows: Int
    }

    private enum PTYCommand {
        case input([UInt8])
        case resize(TerminalSize)
    }

    // Retain layout changes even while the SSH channel is still opening.
    private var latestTerminalSize: TerminalSize?

    /// Serialized write queue — all SSH writes are funnelled through this stream
    /// so that only one `outbound.write` is in-flight at a time.
    ///
    /// Background: Thai (and other multi-byte UTF-8) IME input can produce several
    /// rapid `send` callbacks in quick succession.  Each used to spawn a new
    /// `Task { @MainActor }` that called `await writer.write` concurrently.
    /// NIO's channel pipeline is not designed for concurrent callers and would
    /// deadlock/stall the SSH channel, causing the app to hang indefinitely.
    /// Routing every write through an AsyncStream ensures strict serialisation.
    private var writeStreamContinuation: AsyncStream<PTYCommand>.Continuation?

    private func updateState(connected: Bool, status: String) {
        isConnected = connected
        statusMessage = status
        onStateChange?(connected, status)
    }

    func connect(client: SSHClient, cols: Int, rows: Int) {
        // Cancel any existing connection first
        if connectionTask != nil {
            disconnect()
        }

        let attempt = UUID()
        connectionID = attempt
        isDisconnecting = false
        if let view = terminalView, view.bounds.width > 0, view.bounds.height > 0 {
            let grid = view.getTerminal()
            latestTerminalSize = TerminalSize(cols: grid.cols, rows: grid.rows)
        }
        updateState(connected: false, status: String(localized: "Opening terminal..."))

        connectionTask = Task { [weak self] in
            guard let self, self.connectionID == attempt else { return }
            // Track whether a catch arm set an actionable error — without
            // this flag the cleanup `updateState(... "Disconnected")` below
            // overwrites the real reason and the UI shows only a blinking
            // cursor with no diagnosis.
            var didSetTerminalError = false
            do {
                try await self.runPTYSession(client: client, cols: cols, rows: rows, connectionID: attempt)
            } catch is CancellationError {
                // Normal disconnect — don't show error
            } catch let error as NIOSSHError {
                guard self.connectionID == attempt else { return }
                let msg = self.friendlySSHError(error)
                self.updateState(connected: false, status: msg)
                didSetTerminalError = true
            } catch {
                if self.connectionID == attempt && !self.isDisconnecting {
                    self.updateState(connected: false, status: String(localized: "Error: \(error.localizedDescription)"))
                    didSetTerminalError = true
                }
            }
            guard self.connectionID == attempt else { return }
            if !self.isDisconnecting && !didSetTerminalError
                && (self.isConnected || self.statusMessage == String(localized: "Opening terminal...")) {
                self.updateState(connected: false, status: String(localized: "Disconnected"))
            }
        }
    }

    func disconnect() {
        connectionID = UUID()
        isDisconnecting = true
        connectionTask?.cancel()
        connectionTask = nil
        // Signal the write loop to stop
        writeStreamContinuation?.finish()
        writeStreamContinuation = nil
        updateState(connected: false, status: String(localized: "Disconnected"))
    }

    /// Queue bytes for delivery to the SSH channel.
    ///
    /// Bytes are yielded into the serialised AsyncStream consumed by the write
    /// task inside `runPTYSession`.  This replaces the old pattern of spawning a
    /// fresh `Task { await writer.write(...) }` per keystroke, which allowed
    /// concurrent writes and caused hangs with multi-byte input (e.g. Thai UTF-8).
    nonisolated func sendToSSH(data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.writeStreamContinuation?.yield(.input(bytes))
        }
    }

    nonisolated func resizeTerminal(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let size = TerminalSize(cols: cols, rows: rows)
            guard self.latestTerminalSize != size else { return }
            self.latestTerminalSize = size
            // Resize shares the input queue: fast pinch/layout updates cannot race
            // each other or overlap NIO writes, leaving the remote at an old size.
            self.writeStreamContinuation?.yield(.resize(size))
        }
    }

    private func runPTYSession(client: SSHClient, cols: Int, rows: Int, connectionID: UUID) async throws {
        let initialSize = latestTerminalSize ?? TerminalSize(cols: max(1, cols), rows: max(1, rows))
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: initialSize.cols,
            terminalRowHeight: initialSize.rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        // Create a serialised write stream for this PTY session.
        // The producer side (continuation) is stored on self so that sendToSSH()
        // can yield bytes from the main actor.  The consumer side (writeStream)
        // is drained by the dedicated writerTask below — one write at a time.
        let (writeStream, writeContinuation) = AsyncStream<PTYCommand>.makeStream()
        self.writeStreamContinuation = writeContinuation

        defer {
            // Always tidy up the continuation when this session exits, regardless
            // of how it exits (cancellation, error, normal completion).
            writeContinuation.finish()
            if self.connectionID == connectionID {
                self.writeStreamContinuation = nil
            }
        }

        var finishedOutput = false
        do {
            try await client.withPTY(ptyRequest) { [weak self] inbound, outbound in
                guard let self else { return }
                try Task.checkCancellation()

                let isCurrent = await MainActor.run {
                    guard self.connectionID == connectionID else { return false }
                    // Replay after PTY creation: layout may have completed before
                    // this channel existed, or changed during the SSH handshake.
                    writeContinuation.yield(.resize(self.latestTerminalSize ?? initialSize))
                    self.updateState(connected: true, status: String(localized: "Connected"))
                    return true
                }
                guard isCurrent else { throw CancellationError() }

                // Writer task: drains the write stream ONE item at a time, guaranteeing
                // that each `outbound.write` completes before the next one starts.
                // This is the key fix for the Thai-character hang: no concurrent writes.
                let writerTask = Task {
                    var lastSize: TerminalSize?
                    commandLoop: for await command in writeStream {
                        guard !Task.isCancelled else { break }
                        switch command {
                        case .resize(let size):
                            guard size != lastSize else { continue }
                            do {
                                try await outbound.changeSize(cols: size.cols, rows: size.rows,
                                                              pixelWidth: 0, pixelHeight: 0)
                                lastSize = size
                            } catch {
                                // Resize failure does not end an otherwise usable session.
                                print("[mSSH] Resize failed: \(error)")
                            }
                        case .input(let bytes):
                            do {
                                try await outbound.write(ByteBuffer(bytes: bytes))
                            } catch {
                                await MainActor.run { [weak self] in
                                    guard let self, self.connectionID == connectionID, !self.isDisconnecting else { return }
                                    self.updateState(connected: false, status: String(localized: "Connection lost"))
                                }
                                break commandLoop
                            }
                        }
                    }
                }

                // Read SSH output and feed to terminal — this loop keeps the PTY alive
                do {
                    for try await chunk in inbound {
                        // Check for cancellation periodically
                        try Task.checkCancellation()

                        switch chunk {
                        case .stdout(let buffer):
                            let bytes = Array(buffer.readableBytesView)
                            await MainActor.run {
                                guard self.connectionID == connectionID else { return }
                                self.terminalView?.feed(byteArray: ArraySlice(bytes))
                            }
                        case .stderr(let buffer):
                            let bytes = Array(buffer.readableBytesView)
                            await MainActor.run {
                                guard self.connectionID == connectionID else { return }
                                self.terminalView?.feed(byteArray: ArraySlice(bytes))
                            }
                        }
                    }
                } catch is CancellationError {
                    writerTask.cancel()
                    throw CancellationError()
                } catch {
                    writerTask.cancel()
                    await MainActor.run {
                        if self.connectionID == connectionID && !self.isDisconnecting {
                            self.updateState(connected: false, status: String(localized: "Connection lost: \(error.localizedDescription)"))
                        }
                    }
                }

                writerTask.cancel()
                finishedOutput = true
            }
        } catch ChannelError.alreadyClosed where finishedOutput {
            // Citadel closes the PTY again after the server has already closed it.
        }
    }

    /// Convert NIOSSHError to user-friendly messages
    private func friendlySSHError(_ error: NIOSSHError) -> String {
        let desc = String(describing: error)
        if desc.contains("algorithm") || desc.contains("negotiation") {
            return String(localized: "Algorithm negotiation failed. This server may use unsupported encryption.")
        }
        if desc.contains("auth") {
            return String(localized: "Authentication failed. Check your password or SSH key.")
        }
        if desc.contains("channel") || desc.contains("open") {
            return String(localized: "Failed to open terminal channel.")
        }
        if desc.contains("banner") || desc.contains("protocol") {
            return String(localized: "SSH protocol error. The server may not be running SSH.")
        }
        return String(localized: "SSH error: \(error.localizedDescription)")
    }
}
