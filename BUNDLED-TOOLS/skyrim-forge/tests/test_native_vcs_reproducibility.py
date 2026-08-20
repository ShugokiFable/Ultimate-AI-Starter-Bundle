from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class NativeVCSReproducibilityTests(unittest.TestCase):
    def test_release_build_paths_disable_vcs_metadata(self):
        validator = (ROOT / "scripts" / "validate_repository.py").read_text(encoding="utf-8")
        rebuilder = (ROOT / "scripts" / "rebuild_native_helpers.py").read_text(encoding="utf-8")
        self.assertIn('"-buildvcs=false"', validator)
        self.assertIn('"-buildvcs=false"', rebuilder)
        self.assertIn('SKYRIM_FORGE_GO', validator)
        self.assertIn('SKYRIM_FORGE_GO', rebuilder)

    def test_git_checkout_build_matches_bundled_helper(self):
        go = os.environ.get("SKYRIM_FORGE_GO") or shutil.which("go")
        git = shutil.which("git")
        if not go or not git:
            self.skipTest("Go and Git are required")
        version = subprocess.run([go, "env", "GOVERSION"], text=True, capture_output=True, check=True).stdout.strip()
        if version != "go1.23.2":
            self.skipTest(f"Exact release toolchain unavailable: {version}")
        with tempfile.TemporaryDirectory() as td:
            checkout = Path(td) / "checkout"
            shutil.copytree(ROOT / "writer" / "native-go", checkout)
            subprocess.run([git, "init", "-q"], cwd=checkout, check=True)
            subprocess.run([git, "config", "user.email", "forge-test@example.invalid"], cwd=checkout, check=True)
            subprocess.run([git, "config", "user.name", "Forge Test"], cwd=checkout, check=True)
            subprocess.run([git, "add", "."], cwd=checkout, check=True)
            subprocess.run([git, "commit", "-qm", "fixture"], cwd=checkout, check=True)
            output = Path(td) / "SkyrimForge.Native"
            env = os.environ.copy(); env.update({"CGO_ENABLED":"0","GOOS":"linux","GOARCH":"amd64"})
            subprocess.run([go, "build", "-trimpath", "-buildvcs=false", "-ldflags=-s -w -buildid=", "-o", str(output), "."], cwd=checkout, env=env, check=True)
            bundled = ROOT / "writer" / "published" / "linux-x64" / "SkyrimForge.Native"
            self.assertEqual(sha256(output), sha256(bundled))


if __name__ == "__main__":
    unittest.main()
