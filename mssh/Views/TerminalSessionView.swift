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

    // MARK: - Status Banner

    private var statusBanner: some View {
        SessionStatusBanner(
            message: session.statusMessage,
            isLoading: isLoading,
            onReconnect: { Task { await session.connect() } },
            onClose: { sessionManager.requestCloseSession(session.id) }
        )
    }

    private func pasteFromClipboard() {
        guard let text = AppClipboard.paste(), !text.isEmpty else { return }
        let bytes = Array(text.utf8)
        session.bridge.sendToSSH(data: ArraySlice(bytes))
    }
}

// MARK: - Session Status Banner

struct SessionStatusBanner: View {
    let message: String
    let isLoading: Bool
    let onReconnect: () -> Void
    let onClose: () -> Void

    private var isDisconnected: Bool { message == String(localized: "Disconnected") }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.accent)
                    } else {
                        Image(systemName: isDisconnected ? "wifi.slash" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isDisconnected ? AppColors.textSecondary : AppColors.warning)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            }

            if !isLoading {
                HStack(spacing: AppSpacing.sm) {
                    Button(action: onReconnect) {
                        Text(isDisconnected ? String(localized: "Reconnect") : String(localized: "Retry"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, AppSpacing.sm)
                            .foregroundStyle(AppColors.onEmphasis)
                            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: AppSpacing.md))
                    }
                    Button(action: onClose) {
                        Text("Close")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, AppSpacing.sm)
                            .foregroundStyle(AppColors.textPrimary)
                            .background(AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppSpacing.md))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface, in: AppShape.container)
        .overlay(AppShape.container.strokeBorder(AppColors.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 420)
    }
}

// MARK: - Connection Info Popover

struct ConnectionInfoPopover: View {
    let session: SessionViewModel
    let connectedSince: Date
    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 24

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
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(label)
                    .multilineTextAlignment(.leading)
            }
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
