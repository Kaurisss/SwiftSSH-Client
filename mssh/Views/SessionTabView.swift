import SwiftUI

struct SessionTabView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        @Bindable var manager = sessionManager
        VStack(spacing: 0) {
            // Tab bar - only shown for multiple sessions
            if sessionManager.sessions.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(sessionManager.sessions) { session in
                                SessionTab(
                                    title: session.title,
                                    isConnected: session.isConnected,
                                    isActive: session.id == sessionManager.activeSessionID,
                                    onTap: {
                                        sessionManager.activeSessionID = session.id
                                    },
                                    onClose: { sessionManager.requestCloseSession(session.id) }
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
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(AppColors.border),
                        alignment: .bottom
                    )
                    .onChange(of: sessionManager.activeSessionID) { _, newID in
                        if let newID {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }

            // Active terminal
            if let session = sessionManager.activeSession {
                TerminalSessionView(session: session)
            }
        }
    }
}

struct SessionTab: View {
    let title: String
    let isConnected: Bool
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: AppSpacing.sm) {
                    StatusDot(isConnected: isConnected)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.caption.monospaced().weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.leading, AppSpacing.md)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityValue(isConnected ? Text("Connected") : Text("Disconnected"))

            Button(action: onClose) {
                Label("Close \(title)", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(isActive ? AppColors.textSecondary : AppColors.textTertiary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? AppColors.accentDim : AppColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isActive ? AppColors.accent.opacity(0.3) : AppColors.border, lineWidth: 0.5)
        )
    }
}
