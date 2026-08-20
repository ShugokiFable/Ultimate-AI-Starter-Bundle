from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import forge_build_backend


class PackagingTests(unittest.TestCase):
    def test_no_external_build_requirements(self):
        self.assertEqual(forge_build_backend.get_requires_for_build_wheel(), [])

    def test_wheel_determinism_and_native_files(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            wa=Path(a)/forge_build_backend.build_wheel(a); wb=Path(b)/forge_build_backend.build_wheel(b)
            self.assertEqual(hashlib.sha256(wa.read_bytes()).hexdigest(),hashlib.sha256(wb.read_bytes()).hexdigest())
            with zipfile.ZipFile(wa) as archive:
                self.assertIsNone(archive.testzip())
                self.assertIn("skyrim_forge/bin/win-x64/SkyrimForge.Native.exe",archive.namelist())

    def test_runtime_installation_artifacts_are_never_packaged(self):
        excluded = forge_build_backend.EXCLUDED
        self.assertIn("INSTALLATION.json", excluded)
        self.assertIn("REPORTS", excluded)
        self.assertIn(".venv", excluded)
        self.assertIn(".go-cache", excluded)


ROOT = Path(__file__).resolve().parents[1]


class DistributedIntegrityTests(unittest.TestCase):
    """The shipped integrity evidence must verify where users actually get it.

    MANIFEST.json is published in the repository as well as in the release
    archive. It was generated from a tree whose PowerShell and batch files had
    LF endings, while `.gitattributes` declares `eol=crlf` for exactly those
    files, so a `git clone` materialised different bytes than the manifest
    recorded. Five files failed verification for anyone who cloned and checked.
    """

    def _declared_crlf_suffixes(self) -> set[str]:
        attributes = ROOT / ".gitattributes"
        if not attributes.exists():
            self.skipTest(".gitattributes is absent outside the repository")
        suffixes = set()
        for line in attributes.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[0].startswith("*.") and "eol=crlf" in parts:
                suffixes.add(parts[0][1:].lower())
        return suffixes

    def test_manifest_verifies_against_the_delivered_tree(self):
        manifest = json.loads((ROOT / "MANIFEST.json").read_text(encoding="utf-8"))
        mismatched = []
        for entry in manifest["files"]:
            path = ROOT / entry["path"]
            if not path.exists():
                mismatched.append(f"{entry['path']}: missing")
                continue
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                mismatched.append(f"{entry['path']}: recorded {entry['size']} bytes, found {len(data)}")
        self.assertEqual(mismatched, [], "MANIFEST.json does not verify against the tree it ships with")

    def test_line_endings_match_their_declared_attribute(self):
        suffixes = self._declared_crlf_suffixes()
        self.assertTrue(suffixes, ".gitattributes no longer declares any eol=crlf rule")
        offenders = []
        for path in ROOT.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in suffixes:
                continue
            if any(part in {".git", ".venv", "__pycache__", ".go-cache"} for part in path.parts):
                continue
            data = path.read_bytes()
            if data.count(b"\n") != data.count(b"\r\n"):
                offenders.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(sorted(offenders), [], "files declared eol=crlf contain bare LF endings")


if __name__ == "__main__": unittest.main()
