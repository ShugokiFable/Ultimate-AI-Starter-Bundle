from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

from skyrim_forge.errors import ToolError
from skyrim_forge.tools import build_process_command, run_process


class ProcessLaunchTests(unittest.TestCase):
    def test_python_script_executes_through_current_interpreter(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            script = root / "fixture.py"
            script.write_text("import sys; print('fixture:' + sys.argv[1])\n", encoding="utf-8")
            report = run_process(script, ["ok"], cwd=root, timeout_seconds=10)
            self.assertEqual(report["returncode"], 0, report)
            self.assertEqual(report["launcher"], "python")
            self.assertEqual(report["command"][0], sys.executable)
            self.assertIn("fixture:ok", report["stdout"])

    def test_windows_rejects_text_disguised_as_exe_without_launching(self):
        if os.name != "nt":
            self.skipTest("Windows-specific PE guard")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            fake = root / "fake.exe"
            fake.write_text("not a PE executable", encoding="utf-8")
            with self.assertRaisesRegex(ToolError, "not a Windows PE executable"):
                run_process(fake, [], cwd=root, timeout_seconds=10)


if __name__ == "__main__":
    unittest.main()
