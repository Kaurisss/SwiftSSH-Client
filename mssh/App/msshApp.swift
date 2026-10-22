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
    @State private var isLocked = false
    @State private var modelContainer: ModelContainer?
    @State private var storageError: String?

    init() {
        _isLocked = State(initialValue:
            UserDefaults.standard.bool(forKey: "biometricEnabled")
                && BiometricService.canUseBiometrics()
        )
        configureAppearance()
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

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: 32, weight: .bold)
        ]
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.05)
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.30, green: 0.85, blue: 0.85, alpha: 1)

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = appearance.backgroundColor
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}
