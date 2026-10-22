"""Source/configuration regression checks; does not compile or run the iOS app."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BaselineTests(unittest.TestCase):
    def test_project_has_fork_identity_and_tests(self):
        spec = source("project.yml")
        self.assertIn("name: SwiftSSH\n", spec)
        self.assertIn('DEVELOPMENT_TEAM: ""', spec)
        self.assertIn('SWIFT_VERSION: "5.0"', spec)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.example.swiftssh\n", spec)
        self.assertIn("type: bundle.unit-test", spec)
        self.assertIn("- SwiftSSHTests", spec)
        for old_value in ("com.m4ck", "CC24ZA67DK", "CloudKit", "icloud", "NSAllowsArbitraryLoads"):
            self.assertNotIn(old_value, spec)
        self.assertIn("properties: {}", spec)

    def test_cloud_and_placeholder_sources_are_excluded(self):
        spec = source("project.yml")
        for path in (
            "Services/AutoImportService.swift",
            "Services/ConnectionSyncBridge.swift",
            "Services/iCloudSyncService.swift",
            "Services/SSHFolderImporter.swift",
            "Services/TipJarService.swift",
            "Services/PortForwardManager.swift",
            "Views/MacContentView.swift",
            "Views/MacSetupGuideView.swift",
            "Views/SyncStatusView.swift",
            "Views/TipJarView.swift",
            "Views/PortForwardEditorView.swift",
        ):
            self.assertIn("- " + path + "\n", spec)
            self.assertTrue((ROOT / "mssh" / path).is_file())

    def test_store_failure_does_not_delete_or_fall_back_to_memory(self):
        store = source("mssh/Services/LocalStore.swift")
        app = source("mssh/App/msshApp.swift")
        self.assertIn("cloudKitDatabase: .none", store)
        self.assertIn("return try ModelContainer", store)
        for model in ("ConnectionProfile", "SSHKey", "KnownHost", "Snippet", "PortForward"):
            self.assertIn(model + ".self", store)
        for forbidden in ("removeItem", "try!", "isStoredInMemoryOnly", "migrateStore", "cloudSyncEnabled"):
            self.assertNotIn(forbidden, app + store)
        self.assertIn("storageError = error.localizedDescription", app)
        self.assertIn('Button("Retry") { openStore() }', app)
        self.assertNotIn("AutoImportService", app)
        self.assertNotIn("iCloudSyncService", app)

    def test_credentials_have_no_synchronized_api(self):
        keychain = source("mssh/Services/KeychainService.swift")
        management = source("mssh/Services/KeyManagementService.swift")
        save = source("mssh/ViewModels/ConnectionListViewModel.swift")
        session = source("mssh/ViewModels/SessionViewModel.swift")
        self.assertIn('serviceName = "com.example.swiftssh"', keychain)
        self.assertIn("kSecAttrAccessibleWhenUnlockedThisDeviceOnly", keychain)
        for forbidden in ("Syncable", "repinPrivateKeySync", "kSecAttrSynchronizableAny"):
            self.assertNotIn(forbidden, keychain + management + save + session)
        self.assertNotIn("syncAcrossDevices", management)
        self.assertNotIn("PortForwardManager", session)

    def test_active_ui_has_no_sync_purchase_or_forwarding_entry(self):
        for path in (
            "mssh/Views/SettingsView.swift",
            "mssh/Views/WelcomeView.swift",
            "mssh/Views/KeyManagerView.swift",
            "mssh/Views/ConnectionFormView.swift",
        ):
            code = source(path)
            for forbidden in ("cloudSyncEnabled", "ConnectionSyncBridge", "TipJarView", "PortForwardListSection", "syncToggleKey", "MacSetupGuideView"):
                self.assertNotIn(forbidden, code)
        self.assertNotIn("iCloudDrive", source("mssh/Views/KeyImportWizardView.swift"))

    def test_build_script_propagates_errors_and_does_not_deploy(self):
        script = source("build.sh")
        self.assertIn("set -euo pipefail", script)
        self.assertIn("xcodegen generate", script)
        self.assertIn("xcodebuild test", script)
        self.assertIn("-project SwiftSSH.xcodeproj", script)
        self.assertNotIn("tail -", script)
        self.assertNotIn("devicectl", script)

    def test_unsigned_ipa_workflow_has_no_signing_or_deployment(self):
        workflow = source(".github/workflows/unsigned-ipa.yml")
        for required in (
            "workflow_dispatch:", "contents: read", "runs-on: macos-26",
            "xcodegen generate", "xcodebuild archive",
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
            'CODE_SIGN_IDENTITY=""', 'DEVELOPMENT_TEAM=""',
            "generic/platform=iOS", "Payload/SwiftSSH.app",
            "build/SwiftSSH-unsigned.ipa", "if-no-files-found: error",
        ):
            self.assertIn(required, workflow)
        for forbidden in ("secrets.", "-exportArchive", "devicectl", "app-store-connect"):
            self.assertNotIn(forbidden, workflow)

    def test_upstream_license_is_retained(self):
        license_text = source("LICENSE")
        self.assertIn("MIT License", license_text)
        self.assertIn("Copyright (c) 2026 M4ck Jsd (nirasnet)", license_text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
