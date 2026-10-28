import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.accent)
                    .accessibilityHidden(true)

                Text("SwiftSSH")
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Connections are stored locally. Passwords and private keys use this device's Keychain. App-managed cloud sync is disabled.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Get Started", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppColors.onEmphasis)
                    .tint(AppColors.accent)
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background)
    }
}
