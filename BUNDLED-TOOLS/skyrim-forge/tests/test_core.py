from __future__ import annotations

import ast
import json
import os
import stat
import struct
import tempfile
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

from skyrim_forge.config import ForgeConfig, ToolConfig, load_config
from skyrim_forge.frameworks import self_test as framework_self_test
from skyrim_forge.plugin_header import inspect_plugin_header
from skyrim_forge.plugin_writer import build_plugin, validate_plan
from skyrim_forge.records import query_records
from skyrim_forge.release import build_release, validate_release_tree
from skyrim_forge.safety import SafetyError, is_within, require_within
from skyrim_forge.strictjson import loads


class CoreTests(unittest.TestCase):
    def test_strict_json_rejects_duplicates_and_nonfinite(self):
        with self.assertRaises(Exception): loads('{"a":1,"a":2}')
        with self.assertRaises(Exception): loads('{"a":NaN}')

    def test_config_first_use_creates_workspace(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"
            with patch("pathlib.Path.home", return_value=home):
                config = load_config(root / "config.toml")
            self.assertTrue(config.workspace_root.is_dir())
            self.assertEqual(config.workspace_root, root / "Workspaces")
            self.assertEqual(config.audit_log, root / "audit.jsonl")
            self.assertEqual(config.tool_vault_root, root / "tool-vault")
            self.assertTrue(config.config_path.is_file())
            self.assertFalse(config.allow_external_processes)

    def test_user_workspace_follows_skyrim_forge_root_not_documents(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"
            install = root / "Skyrim Tools" / "Skyrim-Forge-5.2.0"
            install.mkdir(parents=True)
            default_config = home / ".skyrim-forge" / "config.toml"
            with patch("pathlib.Path.home", return_value=home), \
                 patch("skyrim_forge.config.DEFAULT_HOME", home / ".skyrim-forge"), \
                 patch("skyrim_forge.config.DEFAULT_CONFIG", default_config), \
                 patch.dict(os.environ, {"SKYRIM_FORGE_ROOT": str(install)}, clear=False):
                os.environ.pop("SKYRIM_FORGE_CONFIG", None)
                config = load_config()
            self.assertEqual(config.workspace_root, install / "Workspaces")
            self.assertNotIn("Documents", config.workspace_root.parts)
            self.assertNotIn("Skyrim Forge", config.workspace_root.parts)

    def test_empty_documents_workspace_migrates_to_install_root(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"
            install = root / "tools" / "Skyrim-Forge-5.2.0"
            install.mkdir(parents=True)
            legacy = home / "Documents" / "Skyrim Forge" / "Workspaces"
            legacy.mkdir(parents=True)
            cfg = home / ".skyrim-forge" / "config.toml"
            cfg.parent.mkdir(parents=True)
            cfg.write_text(
                '[paths]\nworkspace_root = "{0}"\n'.format(str(legacy).replace("\\", "\\\\")),
                encoding="utf-8",
            )
            with patch("pathlib.Path.home", return_value=home), \
                 patch("skyrim_forge.config.DEFAULT_HOME", home / ".skyrim-forge"), \
                 patch("skyrim_forge.config.DEFAULT_CONFIG", cfg), \
                 patch.dict(os.environ, {"SKYRIM_FORGE_ROOT": str(install)}, clear=False):
                os.environ.pop("SKYRIM_FORGE_CONFIG", None)
                config = load_config()
            self.assertEqual(config.workspace_root, install / "Workspaces")
            self.assertTrue(any("Documents\\Skyrim Forge" in warning or "Documents" in warning for warning in config.load_warnings))

    def test_configured_seven_zip_is_an_allowed_read_target(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            executable = root / "7-Zip" / "7z.exe"
            executable.parent.mkdir()
            executable.write_bytes(b"test")
            config = ForgeConfig(
                config_path=root / "config.toml",
                workspace_root=root / "work",
                audit_log=root / "audit.jsonl",
                seven_zip=executable,
            )
            self.assertTrue(is_within(executable, config.allowed_read_roots))

    def test_workspace_escape_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "work"; root.mkdir()
            outside = Path(td) / "outside"; outside.mkdir()
            with self.assertRaises(SafetyError): require_within(outside / "x", root)
            if hasattr(os, "symlink"):
                link = root / "link"
                try:
                    link.symlink_to(outside, target_is_directory=True)
                except OSError:
                    return
                with self.assertRaises(SafetyError): require_within(link / "x", root)

    def test_framework_regressions(self):
        report = framework_self_test()
        self.assertEqual(report["result"], "PASS", report)

    def test_native_module_parses_with_python_311_grammar(self):
        source = (Path(__file__).parents[1] / "skyrim_forge" / "native.py").read_text(encoding="utf-8")
        ast.parse(source, filename="skyrim_forge/native.py", feature_version=(3, 11))

    def test_plugin_build_and_query(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); output = root / "out"
            plan = root / "plan.json"
            plan.write_text(json.dumps({
                "schema":"skyrim-forge-plugin-plan/1", "output":"Test.esp", "plugin_type":"espfe", "masters":["Skyrim.esm"],
                "operations":[
                    {"record":"KYWD","editor_id":"TestKeyword"},
                    {"record":"GLOB","editor_id":"TestGlobal","value":2.5,"type":"f"},
                    {"record":"FLST","editor_id":"TestList","forms":[]},
                    {"record":"OTFT","editor_id":"TestOutfit","forms":[]}
                ]
            }))
            report = build_plugin(plan, output, approved=True)
            self.assertEqual(report["result"], "PASS")
            plugin = output / "Test.esp"
            header = inspect_plugin_header(plugin)
            self.assertTrue(header.is_light_flag)
            self.assertEqual(header.form_version, 44)
            self.assertAlmostEqual(header.header_version or 0, 1.71, places=2)
            query = query_records(plugin, editor_id="Test")
            self.assertEqual(len(query["matches"]), 4)
            self.assertTrue(all(item["identity_status"] == "local_record" for item in query["matches"]))

    def test_record_query_rejects_unbounded_limit(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); output = root / "out"
            plan = root / "plan.json"
            plan.write_text(json.dumps({"schema":"skyrim-forge-plugin-plan/1","output":"Test.esp","plugin_type":"esp","masters":[],"operations":[{"record":"KYWD","editor_id":"TestKeyword"}]}))
            build_plugin(plan, output, approved=True)
            with self.assertRaises(Exception):
                query_records(output / "Test.esp", limit=100001)

    def test_plugin_plan_rejects_unknown_record(self):
        with self.assertRaises(Exception):
            validate_plan({"schema":"skyrim-forge-plugin-plan/1","output":"X.esp","operations":[{"record":"NAVM","editor_id":"X"}]})

    def test_release_validation_and_determinism(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); release = root / "release"; workspace = root / "workspace"; release.mkdir(); workspace.mkdir()
            (release / "Data").mkdir(); (release / "Data" / "readme.txt").write_text("x")
            self.assertEqual(validate_release_tree(release)["result"], "PASS")
            first = workspace / "a.zip"; second = workspace / "b.zip"
            a = build_release(release, first, workspace, approved=True)
            b = build_release(release, second, workspace, approved=True)
            self.assertEqual(a["sha256"], b["sha256"])

    def test_release_rejects_private_windows_user_path(self):
        with tempfile.TemporaryDirectory() as td:
            release = Path(td) / "release"; release.mkdir()
            (release / "README.md").write_text("C:" + chr(92) + "Users" + chr(92) + "PrivateName" + chr(92) + "Desktop" + chr(92) + "secret.txt")
            report = validate_release_tree(release)
            self.assertEqual(report["result"], "FAIL")
            self.assertTrue(any("private Windows" in item for item in report["errors"]))

    def test_release_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); release = root / "release"; release.mkdir(); target = root / "target"; target.write_text("x")
            try: (release / "link").symlink_to(target)
            except OSError: return
            self.assertEqual(validate_release_tree(release)["result"], "FAIL")

    def test_legacy_papyrus_config_migrates_and_backs_up(self):
        from skyrim_forge.config import load_config
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            cfg = root / "config.toml"
            compiler = root / "PapyrusCompiler.exe"
            flags = root / "TESV_Papyrus_Flags.flg"
            imports = root / "Source"
            cfg.write_text(
                '[paths]\nworkspace_root = "' + (root / 'work').as_posix() + '"\n\n'
                '[papyrus]\ncompiler = "' + compiler.as_posix() + '"\n'
                'flags = "' + flags.as_posix() + '"\n'
                'imports = ["' + imports.as_posix() + '"]\n',
                encoding="utf-8",
            )
            loaded = load_config(cfg)
            self.assertEqual(loaded.tools["papyrus_compiler"].executable, compiler)
            self.assertEqual(loaded.papyrus_flags, flags)
            self.assertEqual(loaded.papyrus_imports, [imports])
            self.assertTrue(cfg.with_suffix(".toml.pre-3.0.1.bak").is_file())
            migrated = cfg.read_text(encoding="utf-8")
            self.assertIn("[papyrus]", migrated)
            self.assertIn("[tools.papyrus_compiler]", migrated)
            self.assertNotIn("compiler =", migrated.split("[papyrus]", 1)[1].split("[safety]", 1)[0])

    def test_current_papyrus_defaults_roundtrip_without_repeated_migration(self):
        from skyrim_forge.config import ForgeConfig, default_tools, load_config, save_config
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            cfg_path = root / "config.toml"
            value = ForgeConfig(
                config_path=cfg_path,
                workspace_root=root / "work",
                audit_log=root / "audit.jsonl",
                papyrus_flags=root / "flags.flg",
                papyrus_imports=[root / "Source"],
                tools=default_tools(),
            )
            save_config(value)
            loaded = load_config(cfg_path)
            self.assertEqual(loaded.load_warnings, [])
            self.assertFalse(cfg_path.with_suffix(".toml.pre-3.0.1.bak").exists())

    def test_version_and_self_test_do_not_load_broken_config(self):
        import subprocess, sys
        with tempfile.TemporaryDirectory() as td:
            cfg = Path(td) / "config.toml"
            cfg.write_text("[unknown]\nx = 1\n", encoding="utf-8")
            for command in ("version", "self-test"):
                completed = subprocess.run(
                    [sys.executable, "-m", "skyrim_forge", "--config", str(cfg), command],
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


    def test_private_release_can_never_claim_share_ready(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "release"
            root.mkdir()
            (root / "readme.txt").write_text("private", encoding="utf-8")
            report = validate_release_tree(root)
            self.assertEqual(report["result"], "PASS")
            self.assertFalse(report["share_ready"])
            self.assertEqual(report["publication_status"], "PRIVATE_ONLY")


if __name__ == "__main__": unittest.main()
