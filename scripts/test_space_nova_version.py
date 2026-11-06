"""Offline regression tests for the authoritative umbrella release version."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("space-nova-version.py")
SPEC = importlib.util.spec_from_file_location("space_nova_version", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

class VersionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        client = self.root / "clients" / "tauri"
        (client / "src-tauri").mkdir(parents=True)
        (self.root / "mix.exs").write_text('def project do\n  [apps_path: "apps",\n    version: "0.3.1",\n  ]\nend\n')
        (client / "package.json").write_text('{"name":"space-nova-client","version":"0.3.1"}')
        (client / "package-lock.json").write_text(
            '{"name":"space-nova-client","version":"0.3.1","packages":{"":{"version":"0.3.1"}}}'
        )
        (client / "src-tauri" / "tauri.conf.json").write_text('{"version":"0.3.1"}')
        (client / "src-tauri" / "Cargo.toml").write_text(
            '[package]\nname = "space-nova-client"\nversion = "0.3.1"\n[dependencies]\nserde = "1"\n'
        )

    def test_root_is_the_only_version_to_edit(self):
        MODULE.set_version(self.root, "0.3.2")
        self.assertEqual(MODULE.umbrella_version(self.root), "0.3.2")
        client = self.root / "clients" / "tauri"
        self.assertEqual(json.loads((client / "package.json").read_text())["version"], "0.3.1")

    def test_sync_generates_consistent_build_metadata(self):
        MODULE.set_version(self.root, "0.4.0")
        MODULE.sync_client_metadata(self.root, MODULE.umbrella_version(self.root))
        client = self.root / "clients" / "tauri"
        for name in ("package.json", "package-lock.json", "src-tauri/tauri.conf.json"):
            self.assertEqual(json.loads((client / name).read_text())["version"], "0.4.0")
        lock = json.loads((client / "package-lock.json").read_text())
        self.assertEqual(lock["packages"][""]["version"], "0.4.0")
        self.assertIn('version = "0.4.0"', (client / "src-tauri" / "Cargo.toml").read_text())

    def test_rejects_downgrade_and_bad_version(self):
        with self.assertRaises(ValueError):
            MODULE.set_version(self.root, "0.3.0")
        with self.assertRaises(ValueError):
            MODULE.set_version(self.root, "release-0.4.0")

if __name__ == "__main__":
    unittest.main()
