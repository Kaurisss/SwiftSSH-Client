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

                Text("Welcome to SwiftSSH")
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Manage your servers from iPhone and iPad.")
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Label("Organize hosts, groups and favorites", systemImage: "server.rack")
                    Label("Connect with a password or SSH key", systemImage: "key.fill")
                    Label("Use a terminal and transfer files with SFTP", systemImage: "terminal")
                    Label("Save commands for quick access", systemImage: "text.badge.plus")
                }
                .foregroundStyle(AppColors.textPrimary)
                .padding(AppSpacing.lg)
                .appCard()

                Text("Connections are stored locally. Passwords and private keys use this device's Keychain. App-managed cloud sync is disabled.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Get Started", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background)
    }
}
