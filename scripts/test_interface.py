"""Validate localization resources and guard the reported appearance regressions."""
import json
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

    def test_localized_connection_status_comparisons(self):
        for file in ('TerminalSessionView.swift', 'SplitTerminalView.swift'):
            code = (ROOT / 'mssh/Views' / file).read_text(encoding='utf-8')
            self.assertNotRegex(code, r'statusMessage\s*[!=]=\s*"(?:Disconnected|Connecting|Opening terminal)')
            self.assertIn('String(localized: "Opening terminal...")', code)


if __name__ == '__main__':
    unittest.main(verbosity=2)
