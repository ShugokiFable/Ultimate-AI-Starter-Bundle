from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

from _workflows import workflows_dir


def owned_powershell_scripts(root: Path) -> list[Path]:
    scripts = [*root.glob('*.ps1')]
    workers = root / 'workers'
    if workers.is_dir():
        scripts.extend(workers.glob('*.ps1'))
    return sorted(set(scripts))


class PowerShellReleaseTests(unittest.TestCase):
    def test_no_expandable_string_has_ambiguous_variable_before_colon(self):
        bad = re.compile(r'(?<!`)\$(?!\{|\(|(?:env|global|script|local|private|using):)[A-Za-z_][A-Za-z0-9_]*:')
        # Scan only Forge-owned source scripts. Runtime-created environments such as
        # .venv contain upstream activation scripts with valid scoped variables like
        # $Env:PATH and are not part of the release source under test.
        findings = []
        for path in owned_powershell_scripts(ROOT):
            text = path.read_text(encoding='utf-8-sig')
            for line_number, line in enumerate(text.splitlines(), 1):
                # Disjoint alternatives; see validate_repository.py.
                for match in re.finditer(r'"(?:`[^\r\n]|[^"`\r\n])*"', line):
                    invalid = bad.search(match.group(0))
                    if invalid:
                        findings.append(f'{path.relative_to(ROOT)}:{line_number}:{invalid.group(0)}')
        self.assertEqual(findings, [])

    def test_runtime_virtualenv_scripts_are_not_release_sources(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'Top.ps1').write_text('Write-Host ok', encoding='utf-8')
            workers = root / 'workers'; workers.mkdir()
            (workers / 'Worker.ps1').write_text('Write-Host ok', encoding='utf-8')
            venv = root / '.venv' / 'Scripts'; venv.mkdir(parents=True)
            (venv / 'Activate.ps1').write_text('$Env:PATH', encoding='utf-8')
            relative = [path.relative_to(root).as_posix() for path in owned_powershell_scripts(root)]
            self.assertEqual(relative, ['Top.ps1', 'workers/Worker.ps1'])

    def test_skill_installer_is_transactional_and_uses_safe_formatting(self):
        text = (ROOT / 'Install-Forge-Skill.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("Write-Host ('{0}: {1}' -f $Name, $Target)", text)
        self.assertIn('.skyrim-forge.stage-', text)
        self.assertIn('.skyrim-forge.backup-', text)
        self.assertIn('Staged Forge skill validation failed', text)
        self.assertNotIn('"$Name: $Target"', text)

    def test_batch_files_never_pass_quoted_dp0_as_a_standalone_external_argument(self):
        bad = re.compile(r'"%~dp0"(?=\s|$)', re.I)
        findings = []
        for path in sorted([*ROOT.glob('*.bat'), *ROOT.glob('*.cmd')]):
            for line_number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
                stripped = line.strip()
                if bad.search(line) and not re.match(r'(?i)^(?:cd|pushd)\b', stripped):
                    findings.append(f'{path.name}:{line_number}:{line}')
        self.assertEqual(findings, [])

    def test_start_menu_uses_gate_default_root_and_has_noninteractive_ci_probe(self):
        start = (ROOT / 'START-HERE.bat').read_text(encoding='utf-8-sig')
        tests = (ROOT / 'Run Tests.bat').read_text(encoding='utf-8-sig')
        self.assertIn('-File "%FORGE_PS_GATE%"', start)
        self.assertNotIn('-Root "%~dp0"', start)
        self.assertNotIn('-Root "%~dp0"', tests)
        self.assertIn('if /I "%~1"=="--validate-only" exit /b 0', start)
        self.assertIn('PowerShell-Parse-Gate.ps1', tests)
        self.assertIn('Install-AI-Bridge.ps1', start)
        self.assertIn('-BootstrapPython -Yes', start)

    def test_parser_gate_defaults_to_its_own_directory_and_sanitizes_legacy_quote(self):
        gate = (ROOT / 'PowerShell-Parse-Gate.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("[string]$Root = ''", gate)
        self.assertIn('$PSScriptRoot', gate)
        self.assertIn("$Root.Trim().Trim([char]34)", gate)
        self.assertIn('Resolve-Path -LiteralPath $CandidateRoot', gate)

    def test_python_bootstrap_is_pinned_and_verified(self):
        installer = (ROOT / 'Install-or-Update.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('https://www.python.org/ftp/python/3.13.14/', installer)
        self.assertIn('C54D9B9BBB8A36E6489363DDD01139707FD781D72F1F9E90C7EC65D0061368E0', installer)
        self.assertIn('Get-AuthenticodeSignature', installer)
        self.assertIn('Python Software Foundation', installer)
        self.assertIn("'existing-forge-venv'", installer)
        self.assertIn('$VenvHealthy = $false', installer)
        self.assertIn('Existing Forge virtual environment is unusable', installer)
        self.assertIn('[IO.FileAttributes]::ReparsePoint', installer)
        self.assertIn('Remove-Item -LiteralPath $ResolvedVenv -Recurse -Force', installer)
        self.assertIn("HKCU:\\SOFTWARE\\Python\\PythonCore", installer)
        self.assertIn("SetEnvironmentVariable('SKYRIM_FORGE_ROOT'", installer)
        self.assertLess(installer.find("$env:SKYRIM_FORGE_ROOT = $Root"), installer.find("config-show"))
        self.assertIn("GetFolderPath('MyDocuments')", installer)
        self.assertIn("'INSTALLATION.json'", installer)
        self.assertIn("'workers\\SkyrimForge.UIWorker.ps1'", installer)
        self.assertIn("'tools.ui_worker.worker_sha256'", installer)

    def test_windows_ci_exercises_broken_virtualenv_repair(self):
        # Not skippable. A Forge subtree with no CI above it would mean the
        # bundle stopped running the Windows installer job, and this repair
        # path is the one that has actually shipped broken.
        workflows = workflows_dir()
        self.assertIsNotNone(workflows, 'no .github/workflows above the Forge subtree')
        workflow = (workflows / 'ci.yml').read_text(encoding='utf-8')
        self.assertIn("[IO.File]::WriteAllBytes((Join-Path $PWD '.venv/Scripts/python.exe')", workflow)
        self.assertIn('Broken virtual environment was not repaired.', workflow)

    def test_provider_bridge_uses_exact_shared_runtime(self):
        register = (ROOT / 'Register-MCP.ps1').read_text(encoding='utf-8-sig')
        skill_installer = (ROOT / 'Install-Forge-Skill.ps1').read_text(encoding='utf-8-sig')
        skill = (ROOT / 'integrations' / 'skyrim-forge' / 'SKILL.md').read_text(encoding='utf-8-sig')
        self.assertIn("Join-Path $Root '.venv\\Scripts\\python.exe'", register)
        self.assertIn('mcp add skyrim-forge -- $Python -m skyrim_forge mcp', register)
        self.assertIn("'mcp', 'add', '--scope', 'user', 'skyrim-forge', '--'", register)
        self.assertIn("Start-Process -FilePath $Executable -ArgumentList $GrokArguments", register)
        self.assertIn("'.grok\\bin\\grok.exe'", register)
        self.assertIn("Grok MCP verification did not return the exact enabled Forge command.", register)
        self.assertIn('function Test-GrokForgeRegistrationAllowed', register)
        self.assertIn('8 running MCP servers wedge Grok', register)
        self.assertIn('disabled_mcp_servers', register)
        self.assertIn('mcp_servers\\.skyrim-forge', register)
        self.assertIn('mcp | Out-Null', register)
        self.assertNotIn("mode = 'skill-cli'", register)
        self.assertIn("'Kimi'", register)
        self.assertIn("'Hermes'", register)
        self.assertIn("Join-Path $KimiHome 'mcp.json'", register)
        self.assertNotIn("Start-Process -FilePath $Executable -ArgumentList @('mcp','test','skyrim-forge')", register)
        self.assertNotIn("'Y' | & $Executable mcp add skyrim-forge", register)
        self.assertIn('from hermes_cli.config import load_config, save_config', register)
        self.assertIn('from hermes_cli.mcp_config import _probe_single_server', register)
        self.assertIn("Start-Process -FilePath $HermesPython", register)
        self.assertIn('\"connect_timeout\": 30', register)
        self.assertIn('hard limit 45s', register)
        self.assertIn('$HermesProcess.WaitForExit(', register)
        self.assertIn('$HermesProcess.WaitForExit()', register)
        self.assertNotIn('$HermesProcess.HasExited', register)
        self.assertIn("$HermesProbe.connected", register)
        self.assertIn("'hermes-agent\\venv\\Scripts\\hermes.exe'", register)
        self.assertNotIn('$Name?', register)
        self.assertIn('${Name}?', register)
        self.assertIn("'INSTALLATION.json'", skill_installer)
        self.assertIn('Read `INSTALLATION.json` beside this skill', skill)


if __name__ == '__main__':
    unittest.main()
