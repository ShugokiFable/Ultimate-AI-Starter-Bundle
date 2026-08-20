from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from skyrim_forge.config import ToolConfig, load_config
from skyrim_forge.errors import SafetyError
from skyrim_forge.mcp_server import TOOL_SPECS, handle
from skyrim_forge.papyrus import compile_scripts
from skyrim_forge.selftest import run_all
from skyrim_forge.service import ForgeService
from skyrim_forge.util import sha256_file


class V41CompletionTests(unittest.TestCase):
    def test_all_built_in_self_tests_are_integrated(self):
        report = run_all()
        self.assertEqual(report["result"], "PASS", report)
        self.assertEqual(set(report["checks"]), {"framework_lint", "framework_builder", "fomod", "papyrus", "native", "nexus", "capabilities", "toolchain"})

    def test_papyrus_compile_uses_pinned_python_mock_and_manifest(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with patch("pathlib.Path.home", return_value=root):
                config = load_config(root / "config.toml")
            config.allow_external_processes = True
            source = root / "Example.psc"
            source.write_text("ScriptName Example extends Quest\nEvent OnInit()\nEndEvent\n", encoding="utf-8")
            flags = root / "TESV_Papyrus_Flags.flg"; flags.write_text("flags\n", encoding="utf-8")
            imports = root / "imports"; imports.mkdir()
            worker = root / "mock_compiler.py"
            worker.write_text(
                "import pathlib,sys\n"
                "src=pathlib.Path(sys.argv[1])\n"
                "out=next(pathlib.Path(a[3:]) for a in sys.argv if a.startswith('-o='))\n"
                "out.mkdir(parents=True,exist_ok=True)\n"
                "(out/(src.stem+'.pex')).write_bytes(b'PEX-MOCK')\n",
                encoding="utf-8",
            )
            config.tools["papyrus_compiler"] = ToolConfig(executable=worker, sha256=sha256_file(worker), timeout_seconds=30)
            report = compile_scripts(config, [source], config.workspace_root / "pex", imports=[imports], flags_file=flags, approved=True)
            self.assertEqual(report["result"], "PASS", report)
            self.assertTrue((config.workspace_root / "pex" / "Example.pex").is_file())
            self.assertTrue((config.workspace_root / "pex" / "PAPYRUS-BUILD-MANIFEST.json").is_file())
            config.tools["papyrus_compiler"].sha256 = ""
            with self.assertRaises(SafetyError):
                compile_scripts(config, [source], config.workspace_root / "pex2", imports=[imports], flags_file=flags, approved=True)

    def test_v41_mcp_surface_is_complete(self):
        expected = {
            "forge_capabilities", "forge_framework_build", "forge_papyrus_analyze", "forge_papyrus_compile",
            "forge_native_plan_validate", "forge_native_scaffold", "forge_native_audit", "forge_native_binary_audit",
            "forge_native_build", "forge_nexus_audit", "forge_nexus_build", "forge_tool_scan", "forge_tool_import", "forge_tool_resolve", "forge_bsarch_pack",
        }
        self.assertTrue(expected.issubset(TOOL_SPECS))
        self.assertGreaterEqual(len(TOOL_SPECS), 40)
        with tempfile.TemporaryDirectory() as td:
            with patch("pathlib.Path.home", return_value=Path(td)):
                service = ForgeService(load_config(Path(td) / "config.toml"))
            resources = handle(service, {"jsonrpc":"2.0","id":1,"method":"resources/list","params":{}})
            uris = {item["uri"] for item in resources["result"]["resources"]}
            self.assertIn("forge://references/framework-source-lock", uris)
            self.assertIn("forge://references/native-source-lock", uris)


if __name__ == "__main__":
    unittest.main()
