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
    static let textSecondary = adaptive(light: 0x555555, dark: 0xAAAAAA)
    static let textTertiary = textSecondary

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.85, blue: 0.85, alpha: 1)
            : UIColor(red: 0, green: 0.43, blue: 0.46, alpha: 1)
    })
    static let accentDim = accent.opacity(0.12)
    static let onEmphasis = adaptive(light: 0xFFFFFF, dark: 0x000000)

    static let connected = adaptive(light: 0x1F7A36, dark: 0x5DE27A)
    static let connectedDim = connected.opacity(0.15)
    static let warning = adaptive(light: 0x9A5D00, dark: 0xFFBF54)
    static let error = adaptive(light: 0xB42318, dark: 0xFF8A80)
    static let errorDim = error.opacity(0.15)

    static let terminalBg = Color(uiColor: .systemBackground)
    static let terminalCursor = accent

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
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

enum AppShape {
    static let cornerRadius: CGFloat = 24
    static let container = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
}

// MARK: - Reusable Components

struct AppCardStyle: ViewModifier {
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.md)
            .background(AppColors.surface)
            .clipShape(AppShape.container)
            .overlay(
                AppShape.container
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
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
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
