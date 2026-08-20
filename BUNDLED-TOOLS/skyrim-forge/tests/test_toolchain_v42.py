from __future__ import annotations

import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from skyrim_forge.config import ForgeConfig, ToolConfig, default_tools, save_config
from skyrim_forge.tool_adapters import bsarch_pack
from skyrim_forge.toolchain import configure_existing_tool, import_all_tools, import_tool, load_catalog, resolve_capability, scan_tool_source
from skyrim_forge.util import sha256_file


def fake_pe(machine: int = 0x014C) -> bytes:
    data = bytearray(512)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<H", data, 0x84, machine)
    struct.pack_into("<H", data, 0x98, 0x10B if machine == 0x014C else 0x20B)
    return bytes(data)


def config(root: Path) -> ForgeConfig:
    tools = default_tools()
    value = ForgeConfig(
        config_path=root / "config.toml",
        workspace_root=root / "workspace",
        audit_log=root / "audit.jsonl",
        tool_vault_root=root / "vault",
        allow_external_processes=True,
        require_approval_for_writes=True,
        extra_read_roots=[root],
        tools=tools,
    )
    value.workspace_root.mkdir()
    value.tool_vault_root.mkdir()
    save_config(value)
    return value


class ToolchainV42Tests(unittest.TestCase):
    def test_nested_bsarch_is_discovered_and_imported_with_pin(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            archive = root / "tools.zip"
            payload = fake_pe()
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("ESLifier/ESLifier.exe", fake_pe(0x8664))
                z.writestr("ESLifier/bsarch/BSArch.exe", payload)
            report = scan_tool_source(archive)
            bsarch = [item for item in report["recognized"] if item["catalog_id"] == "bsarch"]
            self.assertEqual(len(bsarch), 1, report)
            self.assertEqual(bsarch[0]["pe"]["machine"], "x86")
            imported = import_tool(cfg, archive, "bsarch", approved=True)
            executable = Path(imported["executable"])
            self.assertTrue(executable.is_file())
            self.assertEqual(cfg.tools["bsarch"].sha256, sha256_file(executable))
            self.assertTrue(Path(imported["receipt"]).is_file())
            self.assertFalse(imported["public_bundle_allowed"])

    def test_synthesis_gui_is_never_resolved_as_cli(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            gui = root / "Synthesis.exe"; gui.write_bytes(fake_pe(0x8664))
            cfg.tools["synthesis_gui"] = ToolConfig(executable=gui, sha256=sha256_file(gui))
            result = resolve_capability(cfg, "synthesis.pipeline.run")
            self.assertEqual(result["result"], "INCOMPLETE", result)
            self.assertIsNone(result["selected"])

    def test_catalog_disables_public_third_party_binary_bundling(self):
        catalog = load_catalog()
        self.assertGreaterEqual(len(catalog["tools"]), 20)
        self.assertTrue(all(not item["public_bundle_allowed"] for item in catalog["tools"]))
        repository = Path(__file__).resolve().parents[1]
        forbidden = {name.casefold() for item in catalog["tools"] for name in item["names"]}
        bundled = [p for p in repository.rglob("*") if p.is_file() and p.name.casefold() in forbidden]
        self.assertEqual(bundled, [], bundled)

    def test_bsarch_adapter_uses_pinned_real_tool_contract_and_reopens(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            mock = root / "bsarch_mock.py"
            mock.write_text(
                "import pathlib,sys\n"
                "a=sys.argv[1:]\n"
                "if a and a[0]=='pack': pathlib.Path(a[2]).write_bytes(b'BSA-MOCK'); print('packed')\n"
                "elif a and '-list' in a: print('meshes/example.nif')\n"
                "else: print('ok')\n",
                encoding="utf-8",
            )
            cfg.tools["bsarch"] = ToolConfig(executable=mock, sha256=sha256_file(mock), timeout_seconds=30)
            source = cfg.workspace_root / "payload"; source.mkdir(); (source / "example.txt").write_text("x")
            output = cfg.workspace_root / "Example.bsa"
            report = bsarch_pack(cfg, source, output, approved=True)
            self.assertEqual(report["result"], "PASS", report)
            self.assertTrue(output.is_file())
            self.assertEqual(report["reopen"]["returncode"], 0)


    def test_bulk_import_is_idempotent_and_reconfigures_existing_vault_entry(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            archive = root / "tools.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("ESLifier/bsarch/BSArch.exe", fake_pe())
            first = import_all_tools(cfg, archive, approved=True)
            self.assertEqual(first["result"], "PASS", first)
            cfg.tools["bsarch"].executable = None
            cfg.tools["bsarch"].sha256 = ""
            second = import_all_tools(cfg, archive, approved=True)
            self.assertEqual(second["result"], "PASS", second)
            self.assertTrue(second["imported"][0]["reused"])
            self.assertTrue(cfg.tools["bsarch"].executable.is_file())
            self.assertTrue(cfg.tools["bsarch"].sha256)

    def test_configure_existing_rejects_gui_as_cli_by_name(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            gui = root / "Synthesis.exe"; gui.write_bytes(fake_pe(0x8664))
            with self.assertRaises(Exception):
                configure_existing_tool(cfg, "synthesis_cli", gui, approved=True)

    def test_scan_does_not_execute_candidates(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); marker = root / "executed.txt"
            exe = root / "BSArch.exe"; exe.write_bytes(fake_pe())
            report = scan_tool_source(root)
            self.assertEqual(report["result"], "PASS")
            self.assertFalse(marker.exists())
            self.assertIn("No discovered executable was launched", report["evidence"])


if __name__ == "__main__":
    unittest.main()
