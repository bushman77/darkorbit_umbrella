"""Offline guardrails for Space Nova option 9 (never contacts EC2)."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("space-nova")


class DeploymentOptionTest(unittest.TestCase):
    def test_shell_syntax_and_option_9_present(self):
        subprocess.run(["bash", "-n", str(SCRIPT)], check=True)
        result = subprocess.run(["bash", str(SCRIPT), "help"], capture_output=True,
                                text=True, check=True)
        self.assertIn("space-nova deploy", result.stdout)
        self.assertIn("Deploy verified Ubuntu server build", result.stdout)

    def run_mock_deploy(self, corrupt=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fakebin = root / "bin"
            fakebin.mkdir()
            (fakebin / "git").write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                '  *"branch --show-current"*) echo sbs ;;\n'
                '  *"rev-parse origin/sbs"*) printf "%040d\\n" 1 ;;\n'
                "esac\n"
            )
            (fakebin / "gh").write_text(
                "#!/bin/sh\n"
                'case "$1 $2" in\n'
                '  "auth status") exit 0 ;;\n'
                '  "run list") printf "123\\tcompleted\\tsuccess\\n" ;;\n'
                '  "run view") echo success ;;\n'
                '  "run download")\n'
                '    while [ "$#" -gt 0 ]; do\n'
                '      if [ "$1" = --dir ]; then shift; cp "$MOCK_DATA/release.tar.gz" "$1/space-nova-server-linux-x64.tar.gz"; cp "$MOCK_DATA/SHA256SUMS" "$1/SHA256SUMS"; break; fi\n'
                '      shift\n'
                '    done ;;\n'
                '  *) echo "Unexpected gh request: $*" >&2; exit 7 ;;\n'
                "esac\n"
            )
            for command in ("ssh", "scp"):
                (fakebin / command).write_text("#!/bin/sh\necho UNEXPECTED_REMOTE_ACCESS >&2\nexit 9\n")
            for path in fakebin.iterdir():
                path.chmod(0o755)
            data = root / "artifact"
            data.mkdir()
            release = data / "release.tar.gz"
            executable = root / "space_mmo" / "bin" / "space_mmo"
            executable.parent.mkdir(parents=True)
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
            subprocess.run(["tar", "-czf", str(release), "-C", str(root), "space_mmo"],
                           check=True)
            import hashlib
            digest = hashlib.sha256(release.read_bytes()).hexdigest()
            (data / "SHA256SUMS").write_text(
                f"{'0'*64 if corrupt else digest}  space-nova-server-linux-x64.tar.gz\n"
            )
            env = os.environ.copy()
            env["PATH"] = str(fakebin) + os.pathsep + env["PATH"]
            env["MOCK_DATA"] = str(data)
            env["SPACE_NOVA_DEPLOY_SSH_KEY"] = str(fakebin / "git")
            result = subprocess.run(["bash", str(SCRIPT), "deploy"],
                                    input="NO\n", text=True, capture_output=True,
                                    env=env)
            self.assertNotIn("UNEXPECTED_REMOTE_ACCESS", result.stderr)
            return result

    def test_operator_declines_after_valid_checksum(self):
        result = self.run_mock_deploy(corrupt=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cancelled", result.stderr)

    def test_remote_migration_does_not_consume_ssh_script_stdin(self):
        source = SCRIPT.read_text()
        self.assertIn(
            "\"$active/bin/space_mmo\" eval 'Darkorbit.Release.migrate()' </dev/null",
            source,
        )
        self.assertIn("--unit=\"space-nova-migrate-$(date +%s)-$RANDOM\"", source)
        self.assertIn('sudo -n systemctl start "$service"', source)
        self.assertIn("Space Nova updated successfully", source)

    def test_corrupted_artifact_never_reaches_ssh(self):
        result = self.run_mock_deploy(corrupt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr, f"exit={result.returncode} stdout={result.stdout!r} stderr={result.stderr!r}")


if __name__ == "__main__":
    unittest.main()
