from __future__ import annotations

import json
import os
import tempfile
import sys
import unittest
from pathlib import Path

from skyrim_forge.automation import run_job, validate_job
from skyrim_forge.config import ForgeConfig, ToolConfig, default_tools, save_config
from skyrim_forge.external_worker import run_external_worker
from skyrim_forge.loot import apply_plan, compare_plan
from skyrim_forge.mo2 import build_mo2_command
from skyrim_forge.profiles import snapshot_profile
from skyrim_forge.ui_automation import validate_ui_job
from skyrim_forge.xedit import check_errors, install_scripts, parse_check_output
from skyrim_forge.tools import build_process_command, run_process
from skyrim_forge.errors import ToolError
from skyrim_forge.util import sha256_file


def python_fixture(path: Path, body: str) -> Path:
    path = path.with_suffix(".py")
    path.write_text(body, encoding="utf-8")
    return path


def config(root: Path) -> ForgeConfig:
    tools = default_tools()
    value = ForgeConfig(
        config_path=root / "config.toml", workspace_root=root / "workspace", audit_log=root / "audit.jsonl",
        allow_external_processes=True, require_approval_for_writes=True, tools=tools,
    )
    value.workspace_root.mkdir()
    save_config(value)
    return value


class AutomationTests(unittest.TestCase):
    def test_xedit_command_and_marker(self):
        parsed = parse_check_output("x\nSKYRIM_FORGE_CHECK_ERRORS errors=0 records=10\n")
        self.assertEqual(parsed["status"], "PASS")
        self.assertTrue(parsed["marker_found"])

    def test_python_fixture_uses_current_interpreter(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            script = python_fixture(root / "worker", 'print("fixture-ok")\n')
            command, launcher = build_process_command(script, ["--flag"])
            self.assertEqual(command[:2], [sys.executable, str(script.resolve())])
            self.assertEqual(launcher, "python")

    def test_invalid_windows_exe_is_rejected_before_launch(self):
        if os.name != "nt":
            self.skipTest("Windows-specific executable validation")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            fake = root / "SSEEdit64.exe"
            fake.write_text("#!/usr/bin/env python3\nprint('not-pe')\n", encoding="utf-8")
            with self.assertRaisesRegex(ToolError, "not a Windows PE executable"):
                run_process(fake, [], cwd=root, timeout_seconds=5)

    def test_xedit_fixed_script_executes_without_user_input(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            xedit = python_fixture(root / "SSEEdit64", 'import sys\nprint("SKYRIM_FORGE_CHECK_ERRORS errors=0 records=42")\n')
            cfg.tools["xedit"].executable = xedit
            install_scripts(cfg, approved=True)
            report = check_errors(cfg, "Example.esp", cwd=cfg.workspace_root)
            self.assertEqual(report["check"]["status"], "PASS", report)
            self.assertIn("-autoexit", report["process"]["command"])

    def test_mo2_command_forbids_multiple(self):
        command = build_mo2_command("Profile", Path("Tool.exe"), ["-arg"])
        self.assertEqual(command[:3], ["-p", "Profile", "run"])
        with self.assertRaises(Exception): build_mo2_command("Profile", Path("Tool.exe"), ["--multiple"])

    def test_profile_snapshot(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); profile = root / "profile"; profile.mkdir(); (profile / "plugins.txt").write_text("*Skyrim.esm\n")
            report = snapshot_profile(profile, root / "snapshot")
            self.assertEqual(len(report["files"]), 1)

    def test_external_worker_contract(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            worker = python_fixture(root / "worker", '''import argparse,json\np=argparse.ArgumentParser();p.add_argument("--job");p.add_argument("--result");a=p.parse_args();j=json.load(open(a.job));json.dump({"job_id":j["job_id"],"status":"success","outputs":[]},open(a.result,"w"))\n''')
            cfg.tools["loot_worker"].executable = worker
            cfg.tools["loot_worker"].sha256 = sha256_file(worker)
            job = root / "job.json"; result = cfg.workspace_root / "result.json"
            job.write_text(json.dumps({"schema":"skyrim-forge-external-worker/1","job_id":"j","worker_type":"loot","operation":"analyze","inputs":{},"options":{}}))
            report = run_external_worker(cfg, job, result, cfg.workspace_root)
            self.assertEqual(report["worker_result"]["status"], "success")

    def test_external_worker_forces_output_root_and_rejects_escape(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); cfg = config(root)
            worker = python_fixture(root / "worker", '''import argparse,json,os
p=argparse.ArgumentParser();p.add_argument("--job");p.add_argument("--result");a=p.parse_args();j=json.load(open(a.job));json.dump({"job_id":j["job_id"],"status":"success","outputs":[os.path.join(os.path.dirname(j["output_dir"]),"escape.txt")]},open(a.result,"w"))
''')
            cfg.tools["loot_worker"].executable = worker
            cfg.tools["loot_worker"].sha256 = sha256_file(worker)
            job = root / "job.json"; result = cfg.workspace_root / "result.json"
            job.write_text(json.dumps({"schema":"skyrim-forge-external-worker/1","job_id":"escape","worker_type":"loot","operation":"analyze","inputs":{},"options":{},"output_dir":str(root / "outside")}))
            with self.assertRaises(Exception):
                run_external_worker(cfg, job, result, cfg.workspace_root)

    def test_loot_apply_only_allows_configured_profile_targets(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); cfg=config(root)
            profile=root/"profiles"/"Main"; profile.mkdir(parents=True)
            target=profile/"loadorder.txt"; target.write_text("A.esm\n", encoding="utf-8")
            cfg.mo2_profiles_root=root/"profiles"
            plan=root/"plan.json"; plan.write_text(json.dumps({"schema":"skyrim-forge-loot-plan/1","generated_by":"fake","profile":"Main","plugins":["A.esm","B.esp"],"messages":[],"bash_tags":{},"source_hashes":{}}))
            report=apply_plan(cfg, plan, target, approved=True)
            self.assertEqual(report["result"], "PASS")
            outside=root/"outside"; outside.mkdir(); forbidden=outside/"loadorder.txt"; forbidden.write_text("A.esm\n")
            with self.assertRaises(Exception):
                apply_plan(cfg, plan, forbidden, approved=True)

    def test_ui_job_rejects_coordinates_and_ocr(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ui.json"
            path.write_text(json.dumps({"schema":"skyrim-forge-ui/1","job_id":"x","application":"CK","expected_process":"CreationKit.exe","steps":[{"action":"invoke","window_title":"CK","name":"OK","x":1}]}))
            with self.assertRaises(Exception): validate_ui_job(path)

    def test_loot_plan_comparison(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); current=root/"loadorder.txt"; current.write_text("A.esm\nB.esp\n")
            plan=root/"plan.json"; plan.write_text(json.dumps({"schema":"skyrim-forge-loot-plan/1","generated_by":"fake","profile":"p","plugins":["B.esp","A.esm"],"messages":[],"bash_tags":{},"source_hashes":{}}))
            report=compare_plan(current,plan)
            self.assertEqual(report["result"],"DIFFERENT")
            self.assertEqual(len(report["changes"]),2)

    def test_automation_framework_job(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); cfg=config(root); mod=cfg.workspace_root/"mod";mod.mkdir();(mod/"a_DISTR.ini").write_text("Item = 0x1~A.esp||||||100\n")
            job=cfg.workspace_root/"job.json";job.write_text(json.dumps({"schema":"skyrim-forge-automation/1","job_id":"lint","operation":"framework_lint","inputs":{"paths":[str(mod)]},"options":{},"outputs":{}}))
            report=run_job(cfg,job)
            self.assertEqual(report["result"]["result"],"PASS",report)
            self.assertTrue(Path(report["receipt"]).is_file())

    def test_unknown_automation_fields_rejected(self):
        with self.assertRaises(Exception): validate_job({"schema":"skyrim-forge-automation/1","job_id":"x","operation":"framework_lint","shell":"rm"})


if __name__ == "__main__": unittest.main()
