from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class NativeReleaseIntegrityTests(unittest.TestCase):
    def test_packaged_native_helpers_match_published_helpers(self):
        pairs = [
            (ROOT / "writer/published/linux-x64/SkyrimForge.Native", ROOT / "skyrim_forge/bin/linux-x64/SkyrimForge.Native"),
            (ROOT / "writer/published/win-x64/SkyrimForge.Native.exe", ROOT / "skyrim_forge/bin/win-x64/SkyrimForge.Native.exe"),
        ]
        for published, packaged in pairs:
            self.assertTrue(published.is_file(), published)
            self.assertTrue(packaged.is_file(), packaged)
            self.assertEqual(sha256(published), sha256(packaged), f"Native helper copy drift: {published.name}")


if __name__ == "__main__":
    unittest.main()
