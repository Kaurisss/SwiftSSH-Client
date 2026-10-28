import SwiftUI

struct SFTPTransferView: View {
    let fileName: String
    let transferType: SFTPViewModel.TransferType
    let isCancelling: Bool
    let onCancel: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.md) {
                status
                Spacer(minLength: 0)
                cancelButton
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                status
                cancelButton
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var status: some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView()
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(isCancelling ? String(localized: "Cancelling…")
                     : transferType == .download ? String(localized: "Downloading") : String(localized: "Uploading"))
                    .font(.subheadline.weight(.medium))
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel, action: onCancel)
            .buttonStyle(.bordered)
            .disabled(isCancelling)
            .accessibilityIdentifier("sftp-cancel-transfer")
    }
}
