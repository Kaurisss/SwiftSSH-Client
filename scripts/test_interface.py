"""Validate localization resources and guard the reported appearance regressions."""
import json
import plistlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InterfaceTests(unittest.TestCase):
    def test_catalog_translations_and_placeholders(self):
        catalog = json.loads((ROOT / 'mssh/Resources/Localizable.xcstrings').read_text(encoding='utf-8'))
        self.assertEqual(catalog['sourceLanguage'], 'en')
        self.assertGreater(len(catalog['strings']), 300)
        token = re.compile(r'%(?:(\d+)\$)?(lld|d|@)')

        def arguments(value):
            result = {}
            for index, match in enumerate(token.finditer(value), 1):
                result[int(match[1]) if match[1] else index] = match[2]
            return result

        for key, entry in catalog['strings'].items():
            with self.subTest(key=key):
                english = entry['localizations']['en']['stringUnit']['value']
                chinese = entry['localizations']['zh-Hans']['stringUnit']['value']
                self.assertEqual(key, english)
                self.assertTrue(chinese.strip())
                self.assertEqual(arguments(english), arguments(chinese))
        self.assertEqual(catalog['strings']['Connections']['localizations']['zh-Hans']['stringUnit']['value'], '主机')

    def test_adaptive_colors_and_no_forced_dark_chrome(self):
        design = (ROOT / 'mssh/App/DesignSystem.swift').read_text(encoding='utf-8')
        app = (ROOT / 'mssh/App/msshApp.swift').read_text(encoding='utf-8')
        hosts = (ROOT / 'mssh/App/ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('.systemGroupedBackground', design)
        self.assertIn('case .system: return nil', design)
        self.assertIn('@AppStorage("appAppearance")', app)
        self.assertNotIn('UINavigationBarAppearance', app)
        self.assertNotIn('.preferredColorScheme(.dark)', design)
        self.assertNotIn('.toolbarColorScheme(.dark', hosts)
        self.assertIn('.background(AppColors.surface, in: Capsule())', hosts)
        for file in ('KeyManagerView.swift', 'KnownHostsView.swift'):
            code = (ROOT / 'mssh/Views' / file).read_text(encoding='utf-8')
            self.assertIn('.frame(maxWidth: .infinity, maxHeight: .infinity)', code)

    def test_settings_uses_hierarchical_navigation(self):
        settings = (ROOT / 'mssh/Views/SettingsView.swift').read_text(encoding='utf-8')
        index = settings.split('    private var appearanceSettings:', 1)[0]
        self.assertEqual(settings.count('NavigationStack {'), 1)
        self.assertNotIn('Picker(', index)
        self.assertNotIn('Toggle(', index)
        self.assertNotIn('Clear All Data', index)
        self.assertNotIn('Button("Done")', settings)
        for identifier in ('appearance', 'terminal', 'security', 'known-hosts',
                           'snippets', 'storage', 'about'):
            self.assertIn(f'.accessibilityIdentifier("settings-{identifier}")', index)
        self.assertIn('.accessibilityIdentifier("settings-terminal-theme")', settings)
        self.assertIn('.alert("Clear All Data?", isPresented: $showClearDataAlert)', settings)

    def test_generated_version_uses_project_build_settings(self):
        spec = (ROOT / 'project.yml').read_text(encoding='utf-8')
        self.assertIn('CFBundleShortVersionString: "$(MARKETING_VERSION)"', spec)
        self.assertIn('CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"', spec)

    def test_keychain_entitlements_are_simulator_only(self):
        entitlements = plistlib.loads((ROOT / 'mssh/Simulator.entitlements').read_bytes())
        self.assertEqual(entitlements['application-identifier'], 'local.com.example.swiftssh')
        self.assertEqual(entitlements['keychain-access-groups'], ['local.com.example.swiftssh'])
        spec = (ROOT / 'project.yml').read_text(encoding='utf-8')
        self.assertIn('"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": mssh/Simulator.entitlements', spec)
        workflow = (ROOT / '.github/workflows/unsigned-ipa.yml').read_text(encoding='utf-8')
        simulator, archive = workflow.split('      - name: Archive without signing', 1)
        self.assertIn('CODE_SIGN_IDENTITY="-"', simulator)
        self.assertIn('CODE_SIGNING_ALLOWED=YES', simulator)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', archive)
        self.assertIn('CODE_SIGN_IDENTITY=""', archive)

    def test_localized_connection_status_comparisons(self):
        for file in ('TerminalSessionView.swift', 'SplitTerminalView.swift'):
            code = (ROOT / 'mssh/Views' / file).read_text(encoding='utf-8')
            self.assertNotRegex(code, r'statusMessage\s*[!=]=\s*"(?:Disconnected|Connecting|Opening terminal)')
            self.assertIn('String(localized: "Opening terminal...")', code)


if __name__ == '__main__':
    unittest.main(verbosity=2)
