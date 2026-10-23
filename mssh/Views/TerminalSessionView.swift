import SwiftUI

struct TerminalSessionView: View {
    @Bindable var session: SessionViewModel
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @State private var fileBrowser: SFTPBrowserView.Connection?
    @State private var showConnectionInfo = false
    @State private var showSnippetPicker = false

    var body: some View {
        ZStack {
            // Terminal fills entire area
            AppColors.terminalBg
                .ignoresSafeArea()

            TerminalViewWrapper(bridge: session.bridge,
                                isFocused: fileBrowser == nil && !showSnippetPicker && !showConnectionInfo)
                .ignoresSafeArea(.container, edges: .bottom)

            // Connection error overlay — show whenever the session isn't
            // connected and the status message isn't a transient "happy" state.
            // The earlier strict "Connection failed" / "Error:" prefix-match
            // missed our pre-flight errors (KeyParseError, AuthResolutionError),
            // leaving the user with a blank cursor and no explanation.
            if shouldShowStatusOverlay {
                VStack {
                    Spacer()
                    statusBanner
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.xxl)
                }
            }

            // Host key verification prompt
            if let promptType = session.pendingHostKeyPrompt {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                HostKeyPromptView(
                    promptType: promptType,
                    host: session.endpoint.host,
                    port: session.endpoint.port,
                    onAccept: { session.acceptHostKey() },
                    onReject: { session.rejectHostKey() }
                )
            }
        }
        .onAppear {
            session.modelContainer = modelContext.container
            if session.connectionAttempts == 0 && session.sshClient == nil {
                Task { await session.connect() }
            }
        }
        .iOSOnlyNavigationBarTitleDisplayMode()
        #if os(iOS)
        .toolbarBackground(AppColors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Files", systemImage: "folder") {
                    if let client = session.sshClient { fileBrowser = .init(client: client) }
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("terminal-files")
                .disabled(!session.isConnected || session.sshClient == nil)
            }
            ToolbarItem(placement: .principal) {
                Button {
                    showConnectionInfo = true
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        StatusDot(isConnected: session.isConnected)
                        Text(session.title)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .accessibilityLabel(Text("Connection Details: \(session.title)"))
                .accessibilityIdentifier("connection-details")
                .accessibilityValue(session.isConnected ? String(localized: "Connected") : session.statusMessage)
                .popover(isPresented: $showConnectionInfo) {
                    ConnectionInfoPopover(
                        session: session,
                        connectedSince: session.connectedAt ?? Date()
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !session.isConnected {
                        Button("Reconnect", systemImage: "arrow.clockwise") { Task { await session.connect() } }
                            .disabled(isLoading)
                    }
                    Button("Snippets", systemImage: "text.badge.plus") { showSnippetPicker = true }
                        .accessibilityIdentifier("session-snippets")
                        .disabled(!session.isConnected)
                    Button("Paste", systemImage: "doc.on.clipboard") { pasteFromClipboard() }
                        .disabled(!session.isConnected)
                    Divider()
                    Button("Close Session", systemImage: "xmark", role: .destructive) {
                        sessionManager.requestCloseSession(session.id)
                    }
                } label: {
                    Label("Session Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("terminal-actions")
            }
        }
        .sheet(item: $fileBrowser) { connection in
            SFTPBrowserView(client: connection.client)
        }
        .sheet(isPresented: $showSnippetPicker) {
            SnippetPickerView { snippet in
                sendSnippet(snippet)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSnippetPicker)) { _ in
            // The iOS keyboard accessory bar can't present sheets directly;
            // it broadcasts this notification so the active terminal view
            // can put up the picker.
            if session.id == sessionManager.activeSessionID {
                showSnippetPicker = true
            }
        }
        .appTheme()
    }

    private func sendSnippet(_ snippet: Snippet) {
        let bytes = Array(snippet.command.utf8)
        guard !bytes.isEmpty else { return }
        session.bridge.sendToSSH(data: ArraySlice(bytes))
    }

    /// Show the error banner whenever we're not connected and we have a
    /// non-empty status to display. Catches every failure path including
    /// pre-flight errors (KeyParseError, AuthResolutionError) whose messages
    /// don't start with "Connection failed", AND the loading states so the
    /// user gets immediate feedback instead of a silent blinking cursor.
    private var shouldShowStatusOverlay: Bool {
        if session.isConnected { return false }
        if session.statusMessage.isEmpty {
            return false
        }
        return true
    }

    /// True while the session is mid-handshake. Drives the banner's loading
    /// style (spinner instead of warning icon, no Retry/Close).
    private var isLoading: Bool {
        !session.isConnected
            && (session.statusMessage == String(localized: "Connecting...") || session.statusMessage == String(localized: "Opening terminal..."))
    }

    private var isDisconnected: Bool { session.statusMessage == String(localized: "Disconnected") }

    // MARK: - Status Banner

    private var statusBanner: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.accent)
                } else {
                    Image(systemName: isDisconnected ? "network" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isDisconnected ? AppColors.textSecondary : AppColors.warning)
                        .font(.callout)
                }
                Text(session.statusMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Hide action buttons while we're still trying — they only make
            // sense once the attempt has settled into a failure state.
            if !isLoading {
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        Task { await session.connect() }
                    } label: {
                        Text(isDisconnected ? String(localized: "Reconnect") : String(localized: "Retry"))
                            .font(AppFonts.label)
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColors.accentDim)
                            .clipShape(Capsule())
                    }

                    Button {
                        sessionManager.requestCloseSession(session.id)
                    } label: {
                        Text("Close")
                            .font(AppFonts.label)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColors.surfaceElevated)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.surface.opacity(0.95))
        .clipShape(AppShape.container)
        .overlay(
            AppShape.container
                .strokeBorder(
                    (isLoading ? AppColors.accent : isDisconnected ? AppColors.border : AppColors.error).opacity(0.3),
                    lineWidth: 0.5
                )
        )
    }

    private func pasteFromClipboard() {
        guard let text = AppClipboard.paste(), !text.isEmpty else { return }
        let bytes = Array(text.utf8)
        session.bridge.sendToSSH(data: ArraySlice(bytes))
    }
}

// MARK: - Connection Info Popover

struct ConnectionInfoPopover: View {
    let session: SessionViewModel
    let connectedSince: Date

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text("Connection")
                    .font(AppFonts.subheading)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                StatusDot(isConnected: session.isConnected)
            }

            VStack(spacing: AppSpacing.sm) {
                infoRow("person.fill", "User", session.endpoint.username)
                infoRow("server.rack", "Host", session.endpoint.host)
                infoRow("number", "Port", "\(session.endpoint.port)")
                infoRow(
                    session.isConnected ? "checkmark.circle.fill" : "xmark.circle",
                    "Status",
                    session.isConnected ? String(localized: "Connected") : session.statusMessage,
                    color: session.isConnected ? AppColors.connected : AppColors.error
                )
                if session.isConnected {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        infoRow("clock", "Uptime", uptimeString(at: context.date))
                    }
                }
                infoRow(
                    "lock.fill", "Auth",
                    session.profile.authType == .password ? String(localized: "Password") : String(localized: "SSH Key")
                )
            }
        }
        .padding(AppSpacing.lg)
        .frame(idealWidth: 320)
        .background(AppColors.surface)
    }

    private func infoRow(_ icon: String, _ label: LocalizedStringKey, _ value: String, color: Color = AppColors.textPrimary) -> some View {
        LabeledContent {
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(color)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        } label: {
            Label(label, systemImage: icon)
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func uptimeString(at date: Date) -> String {
        let interval = max(0, date.timeIntervalSince(connectedSince))
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m \(seconds)s")
        } else if minutes > 0 {
            return String(localized: "\(minutes)m \(seconds)s")
        } else {
            return String(localized: "\(seconds)s")
        }
    }
}
