import SwiftUI
import UIKit

// MARK: - Adaptive App Colors

enum AppColors {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator).opacity(0.35)
    static let borderActive = Color(uiColor: .separator)

    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.85, blue: 0.85, alpha: 1)
            : UIColor(red: 0, green: 0.43, blue: 0.46, alpha: 1)
    })
    static let accentDim = accent.opacity(0.12)

    static let connected = Color(uiColor: .systemGreen)
    static let connectedDim = connected.opacity(0.15)
    static let warning = Color(uiColor: .systemOrange)
    static let error = Color(uiColor: .systemRed)
    static let errorDim = error.opacity(0.15)

    static let terminalBg = Color(uiColor: .systemBackground)
    static let terminalCursor = accent
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppFonts {
    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
    static let monoCaption = Font.system(.caption2, design: .monospaced)
    static let monoLarge = Font.system(.title3, design: .monospaced).weight(.semibold)

    static let heading = Font.system(.title2, design: .default).weight(.semibold)
    static let subheading = Font.system(.subheadline, design: .default).weight(.medium)
    static let label = Font.system(.caption, design: .default).weight(.medium)
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Reusable Components

struct AppCardStyle: ViewModifier {
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.md)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? AppColors.borderActive : AppColors.border, lineWidth: 0.5)
            )
    }
}

struct AppSectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(AppColors.accentDim)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xs)
    }
}

struct StatusDot: View {
    let isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? AppColors.connected : AppColors.textTertiary)
            .frame(width: 8, height: 8)
            .shadow(color: isConnected ? AppColors.connected.opacity(0.5) : .clear, radius: 4)
    }
}

extension View {
    func appCard(isActive: Bool = false) -> some View {
        modifier(AppCardStyle(isActive: isActive))
    }
}

// MARK: - App Theme Modifier

struct AppThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(AppColors.accent)
    }
}

extension View {
    func appTheme() -> some View {
        modifier(AppThemeModifier())
    }
}
