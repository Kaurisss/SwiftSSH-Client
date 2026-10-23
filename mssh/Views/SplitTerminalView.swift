import SwiftUI

// MARK: - Split Session Tab View

struct SplitSessionTabView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @State private var splitSession: SessionViewModel?
    @State private var splitDirection: SplitDirection = .leftRight
    @State private var focusedPane: Pane = .primary
    @State private var fileBrowser: SFTPBrowserView.Connection?
    @State private var snippetSession: SessionViewModel?

    enum SplitDirection {
        case leftRight   // side by side
        case topBottom   // stacked
    }

    enum Pane {
        case primary
        case secondary
    }

    private var isSplit: Bool { splitSession != nil }
    private var focusedSession: SessionViewModel? {
        focusedPane == .secondary ? splitSession : sessionManager.activeSession
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            if sessionManager.sessions.count > 1 {
                sessionTabBar
            }

            // Terminal content
            if let activeSession = sessionManager.activeSession {
                terminalContent(activeSession)
            } else {
                emptyState
            }
        }
        .background(AppColors.terminalBg)
        .toolbar {
            if isSplit {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Files", systemImage: "folder") {
                        if let client = focusedSession?.sshClient { fileBrowser = .init(client: client) }
                    }
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("terminal-files")
                    .disabled(focusedSession?.sshClient == nil || focusedSession?.isConnected != true)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .onAppear { injectModelContainer() }
        .sheet(item: $fileBrowser) { connection in
            SFTPBrowserView(client: connection.client)
        }
        .sheet(item: $snippetSession) { session in
            SnippetPickerView { snippet in
                guard session.isConnected else { return }
                session.bridge.sendToSSH(data: ArraySlice(snippet.command.utf8))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSnippetPicker)) { _ in
            if isSplit, let session = focusedSession, session.isConnected { snippetSession = session }
        }
        .onChange(of: sessionManager.sessions.map(\.id)) { _, identifiers in
            if let splitSession, !identifiers.contains(splitSession.id) {
                self.splitSession = nil
                focusedPane = .primary
            }
        }
        .onChange(of: sessionManager.activeSessionID) { _, _ in
            splitSession = nil
            focusedPane = .primary
        }
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private func terminalContent(_ session: SessionViewModel) -> some View {
        if let splitSession, isSplit {
            // Split view
            switch splitDirection {
            case .leftRight:
                HStack(spacing: 0) {
                    terminalPane(session: session, pane: .primary)
                    Rectangle().fill(AppColors.accent.opacity(0.3)).frame(width: 2)
                    terminalPane(session: splitSession, pane: .secondary)
                }
            case .topBottom:
                VStack(spacing: 0) {
                    terminalPane(session: session, pane: .primary)
                    Rectangle().fill(AppColors.accent.opacity(0.3)).frame(height: 2)
                    terminalPane(session: splitSession, pane: .secondary)
                }
            }
        } else {
            // Single pane
            singlePane(session: session)
        }
    }

    private func terminalPane(session: SessionViewModel, pane: Pane) -> some View {
        ZStack {
            AppColors.terminalBg
            TerminalViewWrapper(bridge: session.bridge, isFocused: focusedPane == pane)

            // Focus border
            if focusedPane == pane {
                Rectangle()
                    .strokeBorder(AppColors.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }

            // Status banner: same loading + error treatment as the single
            // pane, so a failure in either pane surfaces immediately.
            if SessionBannerInfo.shouldShow(for: session) {
                VStack {
                    Spacer()
                    sessionStatusBanner(session: session)
                        .padding(AppSpacing.md)
                }
            }

            if let promptType = session.pendingHostKeyPrompt {
                Color.black.opacity(0.6).ignoresSafeArea()
                HostKeyPromptView(promptType: promptType,
                                  host: session.endpoint.host, port: session.endpoint.port,
                                  onAccept: { session.acceptHostKey() },
                                  onReject: { session.rejectHostKey() })
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focusPane(pane) })
    }

    private func singlePane(session: SessionViewModel) -> some View {
        TerminalSessionView(session: session)
    }

    /// Inline banner shared by single and split panes — loading style
    /// (spinner, no buttons) while the SSH attempt is in flight, error style
    /// (warning + Retry / Close) once it has settled into a failure.
    private func sessionStatusBanner(session: SessionViewModel) -> some View {
        let loading = SessionBannerInfo.isLoading(for: session)
        let disconnected = session.statusMessage == String(localized: "Disconnected")
        return VStack(spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.accent)
                } else {
                    Image(systemName: disconnected ? "network" : "exclamationmark.triangle.fill")
                        .foregroundStyle(disconnected ? AppColors.textSecondary : AppColors.warning)
                        .font(.callout)
                }
                Text(session.statusMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !loading {
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        Task { await session.connect() }
                    } label: {
                        Text(disconnected ? String(localized: "Reconnect") : String(localized: "Retry"))
                            .font(AppFonts.label)
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.vertical, AppSpacing.sm)
                            .background(AppColors.accentDim)
                            .clipShape(Capsule())
                    }
                    Button {
                        sessionManager.closeSession(session.id)
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
                    (loading ? AppColors.accent : disconnected ? AppColors.border : AppColors.error).opacity(0.3),
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        if sessionManager.activeSession != nil {
            // Split controls
            Menu {
                Button {
                    performSplit(.leftRight)
                } label: {
                    Label("Split Left / Right", systemImage: "rectangle.split.2x1")
                }
                Button {
                    performSplit(.topBottom)
                } label: {
                    Label("Split Top / Bottom", systemImage: "rectangle.split.1x2")
                }
                if isSplit {
                    Button("Focus Other Pane", systemImage: "arrow.left.arrow.right") {
                        focusPane(focusedPane == .primary ? .secondary : .primary)
                    }
                    Divider()
                    Button {
                        closeSplit()
                    } label: {
                        Label("Close Split", systemImage: "xmark.rectangle")
                    }
                }
            } label: {
                Label("Split Terminal", systemImage: isSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }

            // Claude Code
            Menu {
                Button {
                    sendClaudeCommand()
                } label: {
                    Label("Run claude in terminal", systemImage: "sparkle")
                }
                Divider()
                Button {
                    performSplit(.leftRight)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        sendClaudeCommandToSplit()
                    }
                } label: {
                    Label("Claude Code — Split Right", systemImage: "rectangle.righthalf.inset.filled")
                }
                Button {
                    performSplit(.topBottom)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        sendClaudeCommandToSplit()
                    }
                } label: {
                    Label("Claude Code — Split Bottom", systemImage: "rectangle.bottomhalf.inset.filled")
                }
            } label: {
                Label("Claude Code", systemImage: "sparkle")
            }

            if isSplit {
                Menu {
                    if let session = focusedSession, !session.isConnected {
                        Button("Reconnect", systemImage: "arrow.clockwise") { Task { await session.connect() } }
                            .disabled(SessionBannerInfo.isLoading(for: session))
                    }
                    Button("Snippets", systemImage: "text.badge.plus") { snippetSession = focusedSession }
                        .accessibilityIdentifier("session-snippets")
                        .disabled(focusedSession?.isConnected != true)
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        if let text = AppClipboard.paste(), let session = focusedSession {
                            session.bridge.sendToSSH(data: ArraySlice(text.utf8))
                        }
                    }
                    .disabled(focusedSession?.isConnected != true)
                } label: {
                    Label("Session Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Session Tab Bar

    private var sessionTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(sessionManager.sessions.filter({ s in
                    // Don't show split sessions as separate tabs
                    s.id != splitSession?.id
                })) { session in
                    SessionTab(
                        title: session.title,
                        isConnected: session.isConnected,
                        status: session.statusMessage,
                        isActive: session.id == sessionManager.activeSessionID,
                        onTap: {
                            splitSession = nil
                            focusedPane = .primary
                            sessionManager.activeSessionID = session.id
                        },
                        onClose: {
                            sessionManager.requestCloseSession(session.id)
                        }
                    )
                    .id(session.id)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
        }
        .frame(minHeight: 44)
        .background(AppColors.surface)
        .overlay(
            Rectangle().frame(height: 0.5).foregroundStyle(AppColors.border),
            alignment: .bottom
        )
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.textTertiary)
            Text("No Active Sessions")
                .font(AppFonts.subheading)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func focusPane(_ pane: Pane) {
        focusedPane = pane
        _ = focusedSession?.bridge.terminalView?.becomeFirstResponder()
    }

    private func injectModelContainer() {
        for session in sessionManager.sessions {
            if session.modelContainer == nil {
                session.modelContainer = modelContext.container
            }
        }
    }

    private func performSplit(_ direction: SplitDirection) {
        guard let activeSession = sessionManager.activeSession else { return }

        if splitSession != nil {
            splitDirection = direction
            return
        }

        // Create new session for the split pane
        let newSession = SessionViewModel(profile: activeSession.profile)
        newSession.modelContainer = modelContext.container
        sessionManager.sessions.append(newSession)
        // Don't change activeSessionID

        splitDirection = direction
        splitSession = newSession
        focusedPane = .secondary

        Task { await newSession.connect() }
    }

    private func closeSplit() {
        if let session = splitSession {
            sessionManager.requestCloseSession(session.id)
        }
    }

    private func sendClaudeCommand() {
        guard let session = focusedSession, session.isConnected else { return }
        let bytes = Array("claude\n".utf8)
        session.bridge.sendToSSH(data: ArraySlice(bytes))
    }

    private func sendClaudeCommandToSplit() {
        guard let session = splitSession, session.isConnected else { return }
        let bytes = Array("claude\n".utf8)
        session.bridge.sendToSSH(data: ArraySlice(bytes))
    }
}

// MARK: - Banner classification

/// Pure helpers for deciding what status banner to show for a session.
/// Centralised so single-pane and split-pane stay in sync. Marked @MainActor
/// because `SessionViewModel`'s `isConnected` / `statusMessage` are isolated
/// to the main actor.
@MainActor
private enum SessionBannerInfo {
    static func shouldShow(for session: SessionViewModel) -> Bool {
        if session.isConnected { return false }
        let s = session.statusMessage
        return !s.isEmpty
    }

    static func isLoading(for session: SessionViewModel) -> Bool {
        !session.isConnected
            && (session.statusMessage == String(localized: "Connecting...")
                || session.statusMessage == String(localized: "Opening terminal..."))
    }
}
