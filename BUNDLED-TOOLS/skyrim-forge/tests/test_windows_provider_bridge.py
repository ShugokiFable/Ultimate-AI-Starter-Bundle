from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"


@unittest.skipUnless(os.name == "nt", "Windows provider bridge")
class WindowsProviderBridgeTests(unittest.TestCase):
    def run_script(self, script: Path, *arguments: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(POWERSHELL), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), *arguments],
            text=True,
            capture_output=True,
            env=env,
            timeout=60,
            check=False,
        )

    def test_hermes_skill_defaults_to_local_app_data(self):
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            fixture = temp / "forge"
            source = fixture / "integrations" / "skyrim-forge"
            source.mkdir(parents=True)
            shutil.copy2(ROOT / "Install-Forge-Skill.ps1", fixture / "Install-Forge-Skill.ps1")
            (source / "SKILL.md").write_text("---\nname: skyrim-forge\n---\n", encoding="utf-8")
            (fixture / "INSTALLATION.json").write_text(
                json.dumps({"root": str(fixture), "python": sys.executable}), encoding="utf-8"
            )
            profile = temp / "profile"
            local = temp / "local"
            profile.mkdir()
            local.mkdir()
            env = os.environ.copy()
            env.update({"USERPROFILE": str(profile), "LOCALAPPDATA": str(local), "HERMES_HOME": ""})
            result = self.run_script(fixture / "Install-Forge-Skill.ps1", "-Provider", "Hermes", env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((local / "hermes" / "skills" / "skyrim-forge" / "INSTALLATION.json").is_file())
            self.assertFalse((profile / ".hermes" / "skills" / "skyrim-forge").exists())

    def require_installed_test_runtime(self) -> Path:
        python = ROOT / ".venv" / "Scripts" / "python.exe"
        if not python.is_file():
            self.skipTest("Register-MCP integration requires the installed Forge test runtime")
        return python

    def test_kimi_registration_preserves_other_servers_and_writes_forge(self):
        python = self.require_installed_test_runtime()
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            kimi_home = temp / "kimi"
            kimi_home.mkdir()
            config = kimi_home / "mcp.json"
            config.write_text(json.dumps({"mcpServers": {"keep": {"command": "keep.exe", "args": []}}}), encoding="utf-8")
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            (fake_bin / "kimi.cmd").write_text("@exit /b 0\n", encoding="ascii")
            report = temp / "report.json"
            env = os.environ.copy()
            env.update({"KIMI_CODE_HOME": str(kimi_home), "PATH": str(fake_bin) + os.pathsep + env["PATH"]})
            result = self.run_script(
                ROOT / "Register-MCP.ps1", "-Provider", "Kimi", "-Yes", "-ReportPath", str(report), env=env
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            written = json.loads(config.read_text(encoding="utf-8-sig"))["mcpServers"]
            self.assertEqual(written["keep"], {"command": "keep.exe", "args": []})
            self.assertEqual(written["skyrim-forge"]["command"], str(python))
            self.assertEqual(written["skyrim-forge"]["args"], ["-m", "skyrim_forge", "mcp"])
            provider = json.loads(report.read_text(encoding="utf-8-sig"))["providers"][0]
            self.assertEqual((provider["mode"], provider["status"]), ("mcp", "READY"))

    def test_kimi_doctor_failure_restores_original_configuration(self):
        self.require_installed_test_runtime()
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            kimi_home = temp / "kimi"
            kimi_home.mkdir()
            config = kimi_home / "mcp.json"
            original = '{"mcpServers":{"keep":{"command":"keep.exe","args":[]}}}\n'
            config.write_text(original, encoding="utf-8")
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            (fake_bin / "kimi.cmd").write_text("@exit /b 7\n", encoding="ascii")
            report = temp / "report.json"
            env = os.environ.copy()
            env.update({"KIMI_CODE_HOME": str(kimi_home), "PATH": str(fake_bin) + os.pathsep + env["PATH"]})
            result = self.run_script(
                ROOT / "Register-MCP.ps1", "-Provider", "Kimi", "-Yes", "-ReportPath", str(report), env=env
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            provider = json.loads(report.read_text(encoding="utf-8-sig"))["providers"][0]
            self.assertEqual((provider["mode"], provider["status"]), ("mcp", "FAILED"))

    def test_kimi_rejects_array_shaped_server_map_without_overwriting(self):
        self.require_installed_test_runtime()
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            kimi_home = temp / "kimi"
            kimi_home.mkdir()
            config = kimi_home / "mcp.json"
            original = '{"mcpServers":[{"keep":{"command":"keep.exe","args":[]}}]}\n'
            config.write_text(original, encoding="utf-8")
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            (fake_bin / "kimi.cmd").write_text("@exit /b 0\n", encoding="ascii")
            report = temp / "report.json"
            env = os.environ.copy()
            env.update({"KIMI_CODE_HOME": str(kimi_home), "PATH": str(fake_bin) + os.pathsep + env["PATH"]})
            result = self.run_script(
                ROOT / "Register-MCP.ps1", "-Provider", "Kimi", "-Yes", "-ReportPath", str(report), env=env
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            provider = json.loads(report.read_text(encoding="utf-8-sig"))["providers"][0]
            self.assertEqual((provider["mode"], provider["status"]), ("mcp", "FAILED"))

    def test_hermes_registration_is_noninteractive_and_bounded(self):
        register = (ROOT / "Register-MCP.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("from hermes_cli.config import load_config, save_config", register)
        self.assertIn('"connect_timeout": 30', register)
        self.assertNotIn("'Y' | & $Executable mcp add skyrim-forge", register)
        # The probe runs Hermes' own interpreter against a helper script rather
        # than hermes.exe: full CLI startup registers shell hooks, and Hermes
        # prompts on first use of an unseen hook when stdin is a TTY, which hung
        # an unattended bundle install.
        self.assertIn("Start-Process -FilePath $HermesPython -ArgumentList @($HermesConfigHelper)", register)
        self.assertIn("Hermes direct MCP probe timed out after 45 seconds.", register)
        self.assertIn("direct Forge MCP probe still running", register)

    def test_hermes_failure_path_restores_original_configuration(self):
        register = (ROOT / "Register-MCP.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("$HermesOriginal = if (Test-Path -LiteralPath $HermesConfigPath", register)
        self.assertIn("[IO.File]::WriteAllBytes($HermesConfigPath, $HermesOriginal)", register)
        self.assertIn("Remove-Item -LiteralPath $HermesConfigPath -Force", register)
        self.assertIn("throw", register)


if __name__ == "__main__":
    unittest.main()
