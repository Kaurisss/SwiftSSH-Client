import SwiftUI

struct LockScreenView: View {
    var onUnlock: () -> Void

    @State private var isAuthenticating = false
    @State private var showError = false

    private var biometricLabel: String {
        switch BiometricService.biometricType() {
        case .faceID: return String(localized: "Unlock with Face ID")
        case .touchID: return String(localized: "Unlock with Touch ID")
        case .none: return String(localized: "Unlock")
        }
    }

    private var biometricIcon: String {
        switch BiometricService.biometricType() {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.open"
        }
    }

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "lock")
                        .font(.largeTitle)
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityHidden(true)

                    Text("SwiftSSH")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)

                }

                Spacer()

                // Unlock button
                VStack(spacing: AppSpacing.md) {
                    Button {
                        performAuth()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: biometricIcon)
                                .font(.system(size: 18))
                            Text(biometricLabel)
                                .font(.system(.body, weight: .semibold))
                        }
                        .frame(maxWidth: 280)
                        .padding(.vertical, AppSpacing.md)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppColors.onEmphasis)
                    .tint(AppColors.accent)
                    .disabled(isAuthenticating)

                    if showError {
                        Text("Authentication failed. Try again.")
                            .font(.caption)
                            .foregroundStyle(AppColors.error)
                    }
                }

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            performAuth()
        }
    }

    private func performAuth() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        showError = false

        Task {
            let success = await BiometricService.authenticate(
                reason: String(localized: "Authenticate to access your SSH connections")
            )
            await MainActor.run {
                isAuthenticating = false
                if success {
                    onUnlock()
                } else {
                    showError = true
                }
            }
        }
    }
}
