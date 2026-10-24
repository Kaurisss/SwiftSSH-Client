import SwiftUI

struct HostKeyPromptView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let promptType: HostKeyPromptType
    let host: String
    let port: Int
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                information
                ScrollView { information }
            }
            buttonSection
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360)
        .background(AppColors.surface)
        .clipShape(AppShape.container)
        .overlay(
            AppShape.container
                .strokeBorder(isWarning ? AppColors.error.opacity(0.3) : AppColors.accent.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(AppSpacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var isWarning: Bool {
        if case .changedKey = promptType { return true }
        return false
    }

    private var information: some View {
        VStack(spacing: 0) {
            headerSection
            detailSection
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            if !dynamicTypeSize.isAccessibilitySize { ZStack {
                Circle()
                    .fill(isWarning ? AppColors.errorDim : AppColors.accentDim)
                    .frame(width: 56, height: 56)
                Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "key.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isWarning ? AppColors.error : AppColors.accent)
            }
            .accessibilityHidden(true)
            }

            Text(isWarning ? String(localized: "Host Key Changed") : String(localized: "Unknown Host Key"))
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)")
                .font(.callout.monospaced())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.md)
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(isWarning
                 ? String(localized: "The host key has changed. This could indicate a MITM attack, or the server was reinstalled.")
                 : String(localized: "First time connecting to this host. Verify the fingerprint before continuing.")
            )
            .font(.callout)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                switch promptType {
                case .newHost(let fingerprint, let keyType):
                    fingerprintRow("Type", keyType)
                    fingerprintRow("Fingerprint", fingerprint)

                case .changedKey(let oldFingerprint, let newFingerprint, let keyType):
                    fingerprintRow("Type", keyType)
                    fingerprintRow("Previous", oldFingerprint)
                    fingerprintRow("Current", newFingerprint)
                }
            }
            .padding(AppSpacing.md)
            .background(AppColors.background)
            .clipShape(AppShape.container)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
    }

    private var buttonSection: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AppSpacing.sm))
            : AnyLayout(HStackLayout(spacing: AppSpacing.md))
        return layout {
            Button(action: onReject) {
                Text("Reject")
                    .font(.system(.subheadline, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
            }
            .buttonStyle(.bordered)
            .tint(AppColors.textSecondary)

            Button(action: onAccept) {
                Text(isWarning ? String(localized: "Trust Anyway") : String(localized: "Trust"))
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AppColors.onEmphasis)
            .tint(isWarning ? AppColors.error : AppColors.accent)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
    }

    private func fingerprintRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
        }
    }
}
