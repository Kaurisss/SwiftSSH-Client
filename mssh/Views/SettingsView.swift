import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showClearDataAlert = false

    @AppStorage(AppPreferences.Key.terminalThemeName)
    private var themeName = AppPreferences.Default.terminalThemeName
    @AppStorage(AppPreferences.Key.terminalFontFamily)
    private var fontFamily = AppPreferences.Default.terminalFontFamily
    @AppStorage(AppPreferences.Key.terminalFontSize)
    private var fontSize = AppPreferences.Default.terminalFontSize
    @AppStorage(AppPreferences.Key.terminalCursorStyle)
    private var cursorStyleRaw = AppPreferences.Default.terminalCursorStyle
    @AppStorage(AppPreferences.Key.terminalBlinkCursor)
    private var blinkCursor = AppPreferences.Default.terminalBlinkCursor

    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("biometricEnabled") private var biometricEnabled = false
    @AppStorage("lockOnBackground") private var lockOnBackground = true

    private var biometricsAvailable: Bool {
        BiometricService.canUseBiometrics()
    }

    private var biometricLabel: String {
        switch BiometricService.biometricType() {
        case .faceID: return String(localized: "Require Face ID")
        case .touchID: return String(localized: "Require Touch ID")
        case .none: return String(localized: "Require Biometrics")
        }
    }

    private var biometricIcon: String {
        switch BiometricService.biometricType() {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.shield"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        appearanceSettings
                    } label: {
                        Label("App Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityIdentifier("settings-appearance")

                    NavigationLink {
                        terminalSettings
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .accessibilityIdentifier("settings-terminal")

                    NavigationLink {
                        securitySettings
                    } label: {
                        Label("Security", systemImage: "lock.shield")
                    }
                    .accessibilityIdentifier("settings-security")
                }

                Section {
                    NavigationLink {
                        KnownHostsView()
                    } label: {
                        Label("Known Hosts", systemImage: "server.rack")
                    }
                    .accessibilityIdentifier("settings-known-hosts")

                    NavigationLink {
                        SnippetsView()
                    } label: {
                        Label("Snippets", systemImage: "text.badge.plus")
                    }
                    .accessibilityIdentifier("settings-snippets")
                } header: {
                    Label("SSH", systemImage: "network")
                }

                Section {
                    NavigationLink {
                        storageSettings
                    } label: {
                        Label("Storage", systemImage: "externaldrive")
                    }
                    .accessibilityIdentifier("settings-storage")

                    NavigationLink {
                        aboutSettings
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("settings-about")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle("Settings")
            .iOSOnlyNavigationBarTitleDisplayMode()
        }
        .appTheme()
    }

    private var appearanceSettings: some View {
        Form {
            Section {
                Picker("Color Scheme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance-picker")
            } header: {
                Label("App Appearance", systemImage: "circle.lefthalf.filled")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("App Appearance")
        .iOSOnlyNavigationBarTitleDisplayMode()
    }

    private var terminalSettings: some View {
        Form {
            Section {
                NavigationLink {
                    terminalThemeSettings
                } label: {
                    Label("Terminal Theme", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("settings-terminal-theme")
            }

            Section {
                Picker(selection: $fontFamily) {
                    ForEach(AppPreferences.availableFontFamilies, id: \.self) { name in
                        Text(LocalizedStringKey(name)).tag(name)
                    }
                } label: {
                    Label("Font Family", systemImage: "textformat")
                }

                HStack {
                    Label("Font Size", systemImage: "textformat.size")
                    Spacer()
                    Stepper(value: $fontSize, in: AppPreferences.fontSizeRange) {
                        Text("\(fontSize) pt")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(AppColors.accent)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }

                Picker(selection: $cursorStyleRaw) {
                    ForEach(AppPreferences.CursorStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                } label: {
                    Label("Cursor", systemImage: "cursorarrow.click")
                }

                Toggle(isOn: $blinkCursor) {
                    Label("Blink Cursor", systemImage: "cursorarrow.click.badge.clock")
                }
                .tint(AppColors.accent)

                // Live preview
                HStack {
                    Text("Preview")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text("ssh root@host")
                        .font(previewFont())
                        .foregroundStyle(TerminalTheme.named(themeName).foreground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TerminalTheme.named(themeName).background)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            } header: {
                Label("Terminal", systemImage: "terminal")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("Terminal")
        .iOSOnlyNavigationBarTitleDisplayMode()
    }

    private var terminalThemeSettings: some View {
        Form {
            Section {
                ForEach(TerminalTheme.allThemes, id: \.name) { theme in
                    Button {
                        themeName = theme.name
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            ThemeSwatch(theme: theme)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(theme.name))
                                    .font(.subheadline)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("$ ssh root@host")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.foreground.opacity(0.85))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(theme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            Spacer()
                            if themeName == theme.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Label("Terminal Theme", systemImage: "paintpalette")
            } footer: {
                Text("The default terminal theme follows the app appearance. Other terminal themes can be selected separately.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("Terminal Theme")
        .iOSOnlyNavigationBarTitleDisplayMode()
    }

    private var securitySettings: some View {
        Form {
            Section {
                Toggle(isOn: $biometricEnabled) {
                    Label(biometricLabel, systemImage: biometricIcon)
                }
                .disabled(!biometricsAvailable)
                .tint(AppColors.accent)

                if biometricEnabled {
                    Toggle(isOn: $lockOnBackground) {
                        Label("Lock on Background", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                    .tint(AppColors.accent)
                }
            } header: {
                Label("Security", systemImage: "lock.shield")
            } footer: {
                if !biometricsAvailable {
                    Text("Biometric authentication is not available on this device.")
                } else if biometricEnabled {
                    Text(lockOnBackground
                        ? String(localized: "Authentication required when opening the app and returning from background.")
                        : String(localized: "Authentication required when opening the app."))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("Security")
        .iOSOnlyNavigationBarTitleDisplayMode()
    }

    private var storageSettings: some View {
        Form {
            Section {
                Label("Stored on this device", systemImage: "internaldrive")
            } header: {
                Label("Storage", systemImage: "externaldrive")
            } footer: {
                Text("App-managed cloud sync is disabled. Passwords and private keys stay in this device's Keychain.")
            }

            Section {
                Button(role: .destructive) {
                    showClearDataAlert = true
                } label: {
                    Label("Clear All Data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } header: {
                Label("Data", systemImage: "externaldrive")
            } footer: {
                Text("Removes all connections, keys, snippets, port forwards, and known hosts from this device.")
            }
            .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear Everything", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will delete all connections, SSH keys, snippets, port forwards, and known hosts. This cannot be undone.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("Storage")
        .iOSOnlyNavigationBarTitleDisplayMode()
    }

    private var aboutSettings: some View {
        Form {
            Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(appVersion)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
                HStack {
                    Label("Build", systemImage: "hammer")
                    Spacer()
                    Text(appBuild)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
                HStack {
                    Label("SSH Engine", systemImage: "shippingbox")
                    Spacer()
                    Text("Citadel")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
                HStack {
                    Label("Terminal Engine", systemImage: "shippingbox")
                    Spacer()
                    Text("SwiftTerm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
                HStack {
                    Label("Based on", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Link("nirasnet/mssh", destination: URL(string: "https://github.com/nirasnet/mssh")!)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
            } header: {
                Label("About", systemImage: "info.circle")
            } footer: {
                Text("Built with Citadel (orlandos-nl) and SwiftTerm (migueldeicaza).")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("About")
        .iOSOnlyNavigationBarTitleDisplayMode()
    }

    /// Resolved preview font that honors family + size, with a system fallback.
    private func previewFont() -> Font {
        let pt = CGFloat(fontSize)
        if fontFamily == "System" {
            return .system(size: pt, design: .monospaced)
        }
        return .custom(fontFamily, size: pt)
    }

    private func clearAllData() {
        let context = modelContext
        do {
            try context.delete(model: ConnectionProfile.self)
            try context.delete(model: SSHKey.self)
            try context.delete(model: KnownHost.self)
            try context.delete(model: Snippet.self)
            try context.delete(model: PortForward.self)
            try context.save()
        } catch {
            print("[mSSH] Failed to clear data: \(error)")
        }
    }
}

// MARK: - Theme swatch for the appearance picker

private struct ThemeSwatch: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 0) {
            theme.background
            theme.foreground
            theme.cursorColor
        }
        .frame(width: 36, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}
