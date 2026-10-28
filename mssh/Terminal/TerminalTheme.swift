import SwiftUI
import SwiftTerm

struct TerminalTheme: Equatable {
    var background: SwiftUI.Color
    var foreground: SwiftUI.Color
    var cursorColor: SwiftUI.Color
    var name: String

    static let `default` = TerminalTheme(
        background: AppColors.terminalBg,
        foreground: AppColors.textPrimary,
        cursorColor: AppColors.accent,
        name: "Default"
    )

    static let solarizedDark = TerminalTheme(
        background: SwiftUI.Color(red: 0.0, green: 0.17, blue: 0.21),
        foreground: SwiftUI.Color(red: 0.51, green: 0.58, blue: 0.59),
        cursorColor: SwiftUI.Color(red: 0.52, green: 0.6, blue: 0.0),
        name: "Solarized Dark"
    )

    static let monokai = TerminalTheme(
        background: SwiftUI.Color(red: 0.15, green: 0.15, blue: 0.15),
        foreground: SwiftUI.Color(red: 0.97, green: 0.97, blue: 0.95),
        cursorColor: SwiftUI.Color(red: 0.97, green: 0.15, blue: 0.31),
        name: "Monokai"
    )

    static let nord = TerminalTheme(
        background: SwiftUI.Color(red: 0.18, green: 0.20, blue: 0.25),
        foreground: SwiftUI.Color(red: 0.85, green: 0.87, blue: 0.91),
        cursorColor: SwiftUI.Color(red: 0.53, green: 0.75, blue: 0.82),
        name: "Nord"
    )

    static let dracula = TerminalTheme(
        background: SwiftUI.Color(red: 0.16, green: 0.16, blue: 0.21),
        foreground: SwiftUI.Color(red: 0.97, green: 0.97, blue: 0.95),
        cursorColor: SwiftUI.Color(red: 0.74, green: 0.58, blue: 0.98),
        name: "Dracula"
    )

    static let tokyoNight = TerminalTheme(
        background: SwiftUI.Color(red: 0.10, green: 0.11, blue: 0.17),
        foreground: SwiftUI.Color(red: 0.66, green: 0.70, blue: 0.84),
        cursorColor: SwiftUI.Color(red: 0.49, green: 0.51, blue: 0.98),
        name: "Tokyo Night"
    )

    static let allThemes: [TerminalTheme] = [
        .default, .solarizedDark, .monokai, .nord, .dracula, .tokyoNight
    ]

    /// Look up a theme by its display name. Falls back to `.default` for
    /// unknown names so a stale UserDefaults value never crashes the UI.
    static func named(_ name: String) -> TerminalTheme {
        allThemes.first { $0.name == name } ?? .default
    }

    /// All sixteen entries stay readable on white, including normal and bold ANSI white.
    static let lightANSIColors: [SwiftTerm.Color] = ansiColors([
        0x202124, 0xB42318, 0x216E39, 0x785A00,
        0x2455A4, 0x873B8E, 0x006970, 0x4B5563,
        0x626262, 0xC12F23, 0x287D3C, 0x876600,
        0x3265B4, 0x98459F, 0x267373, 0x374151,
    ])

    /// SwiftTerm 1.13's original Terminal.app palette, restored when leaving light mode.
    static let darkANSIColors: [SwiftTerm.Color] = ansiColors([
        0x000000, 0xC23621, 0x25BC24, 0xADAD27,
        0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
        0x818383, 0xFC391F, 0x31E722, 0xEAEC23,
        0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB,
    ])

    private static func ansiColors(_ values: [UInt32]) -> [SwiftTerm.Color] {
        values.map { rgb in
            // SwiftTerm's public initializer takes 16-bit rather than 8-bit channels.
            SwiftTerm.Color(red: UInt16((rgb >> 16) & 255) * 257,
                            green: UInt16((rgb >> 8) & 255) * 257,
                            blue: UInt16(rgb & 255) * 257)
        }
    }
}
