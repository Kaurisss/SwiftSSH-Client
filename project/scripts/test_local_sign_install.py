"""Offline tests: no real certificate, phone, or signing operation is used."""
import datetime as dt
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("local_sign", Path(__file__).with_name("local-sign-install.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        self.profile = {
            "ExpirationDate": dt.datetime(2027, 1, 1),
            "DeveloperCertificates": [b"test-cert"],
            "ProvisionedDevices": ["test-device"],
            "ApplicationIdentifierPrefix": ["TEAM"],
            "Entitlements": {"application-identifier": "TEAM.com.example.app"},
        }

    def test_password_file_formats(self):
        self.assertEqual(module.password_bytes(b"test-pass\r\n"), b"test-pass")
        self.assertEqual(module.password_bytes("\ufeff密码：test-pass\r\n".encode()), b"test-pass")
        self.assertEqual(module.password_bytes("证书密码: test-pass".encode()), b"test-pass")
        self.assertEqual(module.password_bytes(b" leading-and-trailing "), b" leading-and-trailing ")

    def test_matching_profile(self):
        self.assertEqual(module.validate_profile(self.profile, b"test-cert", "test-device", self.now), "com.example.app")

    def test_rejects_expired_mismatched_and_wrong_device(self):
        cases = [
            ({"ExpirationDate": dt.datetime(2025, 1, 1)}, b"test-cert", "test-device"),
            ({}, b"wrong-cert", "test-device"),
            ({}, b"test-cert", "wrong-device"),
            ({"ApplicationIdentifierPrefix": ["OTHER"]}, b"test-cert", "test-device"),
            ({"Entitlements": {"application-identifier": "TEAM.com.*.app"}}, b"test-cert", "test-device"),
            ({"Entitlements": {"application-identifier": "TEAM.com.**"}}, b"test-cert", "test-device"),
        ]
        for updates, cert, device in cases:
            with self.subTest(updates=updates, cert=cert, device=device):
                with self.assertRaises(ValueError):
                    module.validate_profile({**self.profile, **updates}, cert, device, self.now)

    def test_fixed_and_wildcard_bundle(self):
        self.assertEqual(module.signing_bundle("com.fixed.app", "com.original.app"), "com.fixed.app")
        self.assertEqual(module.signing_bundle("*", "com.original.app"), "com.original.app")
        self.assertEqual(module.signing_bundle("com.example.*", "com.example.app"), "com.example.app")
        with self.assertRaises(ValueError):
            module.signing_bundle("com.example.*", "com.other.app")

    def test_device_selection(self):
        self.assertEqual(module.choose_device(self.profile, ["other", "test-device"], None), "test-device")
        self.assertEqual(module.choose_device(self.profile, ["test-device"], "test-device"), "test-device")
        for connected, preferred in [([], None), (["test-device"], "other"), (["other"], None)]:
            with self.assertRaises(ValueError):
                module.choose_device(self.profile, connected, preferred)
        enterprise = {"ProvisionsAllDevices": True}
        with self.assertRaises(ValueError):
            module.choose_device(enterprise, ["one", "two"], None)
        self.assertEqual(module.choose_device(enterprise, ["one", "two"], "two"), "two")

    def test_windows_launchers_use_crlf(self):
        for name in ["初始化.cmd", "一键签名安装.cmd"]:
            data = (Path(__file__).parents[1] / name).read_bytes()
            self.assertIn(b"\r\n", data)
            self.assertNotIn(b"\n", data.replace(b"\r\n", b""))

    def test_actions_download_uses_exact_successful_run(self):
        run = {"databaseId": 42, "status": "completed", "conclusion": "success",
               "url": "https://github.com/owner/repo/actions/runs/42", "headSha": "fixture-sha"}
        config = {"ghPath": "gh.exe", "repository": "owner/private-repo"}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)

            def download(command, **kwargs):
                self.assertEqual(command[:4], ["gh.exe", "run", "download", "42"])
                self.assertIn("owner/private-repo", command)
                self.assertIn("SwiftSSH-unsigned", command)
                destination = Path(command[command.index("--dir") + 1])
                with zipfile.ZipFile(destination / "SwiftSSH-unsigned.ipa", "w") as archive:
                    archive.writestr("Payload/SwiftSSH.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.example.swiftssh"}))

            with patch.object(module, "OUTPUT", output), patch.object(
                module.subprocess, "check_output", return_value=module.json.dumps([run])
            ) as listing, patch.object(module.subprocess, "run", side_effect=download):
                ipa = module.download_ipa(config)
                self.assertEqual(ipa, output / "SwiftSSH-42-unsigned.ipa")
                self.assertTrue(ipa.is_file())
                command = listing.call_args.args[0]
                self.assertIn("main", command)
                self.assertIn("unsigned-ipa.yml", command)
                self.assertNotIn("--status", command)

    def test_latest_failed_or_pending_run_never_downloads_an_older_ipa(self):
        cases = [[], [{"databaseId": 42, "status": "in_progress", "conclusion": "", "url": "run-url"}],
                 [{"databaseId": 42, "status": "completed", "conclusion": "failure", "url": "run-url"}]]
        for runs in cases:
            with self.subTest(runs=runs), patch.object(module.subprocess, "check_output", return_value=module.json.dumps(runs)), patch.object(module.subprocess, "run") as download:
                with self.assertRaises(ValueError):
                    module.download_ipa({"ghPath": "gh", "repository": "owner/repo"})
                download.assert_not_called()

    def test_invalid_download_does_not_replace_a_previous_ipa(self):
        run = {"databaseId": 42, "status": "completed", "conclusion": "success", "url": "run-url", "headSha": "fixture"}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            old = output / "SwiftSSH-42-unsigned.ipa"
            old.write_bytes(b"previous IPA")

            def invalid_download(command, **kwargs):
                destination = Path(command[command.index("--dir") + 1])
                (destination / "bad.ipa").write_bytes(b"not a zip")

            with patch.object(module, "OUTPUT", output), patch.object(module.subprocess, "check_output", return_value=module.json.dumps([run])), patch.object(module.subprocess, "run", side_effect=invalid_download):
                with self.assertRaises(zipfile.BadZipFile):
                    module.download_ipa({"ghPath": "gh", "repository": "owner/repo"})
            self.assertEqual(old.read_bytes(), b"previous IPA")

    def test_missing_or_multiple_ipa_downloads_are_rejected(self):
        run = {"databaseId": 42, "status": "completed", "conclusion": "success", "url": "run-url", "headSha": "fixture"}
        for count in (0, 2):
            with self.subTest(count=count), tempfile.TemporaryDirectory() as directory:
                def ambiguous_download(command, **kwargs):
                    destination = Path(command[command.index("--dir") + 1])
                    for index in range(count):
                        (destination / f"app-{index}.ipa").write_bytes(b"fixture")

                with patch.object(module, "OUTPUT", Path(directory)), patch.object(module.subprocess, "check_output", return_value=module.json.dumps([run])), patch.object(module.subprocess, "run", side_effect=ambiguous_download):
                    with self.assertRaisesRegex(ValueError, "只包含一个 IPA"):
                        module.download_ipa({"ghPath": "gh", "repository": "owner/repo"})

    def test_local_ipa_skips_download_and_missing_path_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mine.ipa"
            path.write_bytes(b"fixture")
            with patch.object(module, "OUTPUT", Path(directory) / "out"), patch.object(module, "download_ipa") as download:
                self.assertEqual(module.resolve_ipa({}, str(path)), path)
                download.assert_not_called()
                with self.assertRaisesRegex(ValueError, "找不到 IPA"):
                    module.resolve_ipa({}, str(Path(directory) / "missing.ipa"))
                download.assert_not_called()

    def test_ipa_structure_and_extensions(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "test.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Payload/Test.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.example.app"}))
            info, root = module.ipa_info(path)
            self.assertEqual(info["CFBundleIdentifier"], "com.example.app")
            self.assertEqual(root, "Payload/Test.app")
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr("Payload/Test.app/PlugIns/Test.appex/Info.plist", b"test")
            with self.assertRaises(ValueError):
                module.ipa_info(path)


if __name__ == "__main__":
    unittest.main()
