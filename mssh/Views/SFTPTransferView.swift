import SwiftUI

struct SFTPTransferView: View {
    let fileName: String
    let transferType: SFTPViewModel.TransferType

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: transferType == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)

            Text(transferType == .download ? String(localized: "Downloading") : String(localized: "Uploading"))
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .foregroundStyle(AppColors.textPrimary)

            Text(fileName)
                .font(AppFonts.monoCaption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            ProgressView()
                .tint(AppColors.accent)
        }
        .padding(AppSpacing.xl)
        .background(AppColors.surface)
        .clipShape(AppShape.container)
        .overlay(
            AppShape.container
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 20)
    }
}
