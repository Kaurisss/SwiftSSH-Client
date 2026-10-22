import SwiftUI
import SwiftData
import UIKit

@main
struct msshApp: App {
    @State private var sessionManager = SessionManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("biometricEnabled") private var biometricEnabled = false
    @AppStorage("lockOnBackground") private var lockOnBackground = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @State private var isLocked = false
    @State private var modelContainer: ModelContainer?
    @State private var storageError: String?

    init() {
        _isLocked = State(initialValue:
            UserDefaults.standard.bool(forKey: "biometricEnabled")
                && BiometricService.canUseBiometrics()
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer {
                    appContent
                        .modelContainer(modelContainer)
                } else if let storageError {
                    ContentUnavailableView {
                        Label("Unable to Open Local Data", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your database has been kept. No data was reset.\n\n\(storageError)")
                    } actions: {
                        Button("Retry") { openStore() }
                    }
                } else {
                    ProgressView("Opening local data…")
                }
            }
            .environment(sessionManager)
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
            .tint(AppColors.accent)
            .task {
                if modelContainer == nil && storageError == nil {
                    openStore()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && biometricEnabled && lockOnBackground
                    && BiometricService.canUseBiometrics() {
                    isLocked = true
                }
            }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if !hasCompletedOnboarding {
            WelcomeView {
                hasCompletedOnboarding = true
            }
        } else {
            ContentView()
                .allowsHitTesting(!isLocked)
                .accessibilityHidden(isLocked)
                .overlay {
                    if isLocked {
                        LockScreenView {
                            isLocked = false
                        }
                    }
                }
        }
    }

    private func openStore() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            modelContainer = try LocalStore.open(
                at: directory.appendingPathComponent("default.store")
            )
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}
