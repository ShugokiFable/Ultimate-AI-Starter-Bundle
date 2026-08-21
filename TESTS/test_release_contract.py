"""Release-contract tests for the Ultimate AI Starter Bundle.

Version-agnostic on purpose. Naming the release in the FILENAME and in ~15
assertions meant every bump was a rename plus a find-and-replace, and a
missed one was a red gate on a correct tree. VERSION.txt is the source; this
suite reads it.

Runnable with the Python standard library only:
    python TESTS/test_release_contract.py
"""
from __future__ import annotations

import io
import json
import re
import subprocess
import sys
import zipfile
import ast
import hashlib
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANON = ROOT / "_V7-CANONICAL-SKILLS"
PROVIDERS = ("Claude", "Codex", "Grok", "Hermes", "Kimi")

VERSION = (ROOT / "VERSION.txt").read_text(encoding="utf-8-sig").strip()   # current bundle version
BARE = VERSION.lstrip("vV")                                               # 7.9.0


FORGE_SOURCE = ROOT / "BUNDLED-TOOLS" / "skyrim-forge"


def ps_code(path: Path) -> str:
    """A PowerShell file with its comments removed.

    A gate that asserts some token is GONE cannot tell code from the comment
    explaining why it is gone, and the explanation is the part that stops
    someone putting it back. Strip `<# ... #>` blocks and whole-line `#`
    comments, then assert against what actually executes.
    """
    text = re.sub(r"(?s)<#.*?#>", "", read(path))
    return "\n".join(l for l in text.split("\n") if not l.strip().startswith("#"))


def forge_version() -> str:
    """Forge's version, read from the one file that declares it.

    Forge used to arrive here as a released ZIP whose filename carried the
    version. It is source in this repository now, so the version is whatever
    this commit says -- there is no archive that can disagree with it.
    """
    text = read(FORGE_SOURCE / "VERSION.txt")
    found = re.search(r"(?m)^Skyrim Forge\s+(\d+\.\d+\.\d+)\s*$", text)
    assert found, "BUNDLED-TOOLS/skyrim-forge/VERSION.txt declares no version"
    return found.group(1)


def doctor_fields() -> set[str]:
    """Exactly the keys `forge doctor` returns, parsed from its source."""
    tree = ast.parse(read(FORGE_SOURCE / "skyrim_forge" / "environment.py"))
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "doctor":
            for statement in ast.walk(node):
                if isinstance(statement, ast.Return) and isinstance(statement.value, ast.Dict):
                    return {k.value for k in statement.value.keys if isinstance(k, ast.Constant)}
    raise AssertionError("no doctor() returning a dict literal in skyrim_forge/environment.py")

# Generic reliability/cognition coverage deliberately missing from 7.7.15.
SKILLS = {
    "ci-convergence": ("pushed sha", "required checks", "terminal"),
    "one-shot-completion": ("acceptance criteria", "implied deliverables", "verify"),
    "fresh-install-proof": ("empty", "unicode", "idempotent"),
    "artifact-proof": ("built artifact", "extract", "entrypoint"),
    "failure-recovery-loop": ("root cause", "smallest reproducer", "full gate"),
    "state-resumption": ("reconstruct", "actual files", "ledger"),
    "dependency-capability-check": ("version", "capability", "fallback"),
    "reasoning-economy": ("rework", "cache", "state ledger"),
    "assumption-audit": ("assumption", "verify", "unknown"),
    "regression-sweep": ("sibling", "regression", "changed boundary"),
    "config-preservation": ("backup", "merge", "round-trip"),
    "path-portability": ("spaces", "unicode", "absolute"),
    "version-sync": ("single source", "version", "drift"),
    "side-effect-safety": ("irreversible", "scope", "rollback"),
    "real-boundary-testing": ("real boundary", "mock", "integration"),
    "source-of-truth": ("authority", "derived", "drift"),
    "requirements-traceability": ("requirement", "evidence", "coverage"),
    "evidence-calibration": ("fact", "inference", "confidence"),
    "research-verification": ("primary source", "freshness", "corroborate"),
    "edge-case-matrix": ("boundary", "empty", "malformed"),
    "reproducible-builds": ("deterministic", "toolchain", "hash"),
    "migration-rollback": ("migration", "rollback", "backup"),
    "security-boundaries": ("trust boundary", "least privilege", "untrusted"),
    "secret-hygiene": ("secret", "credential", "redact"),
    "performance-evidence": ("profile", "baseline", "measure"),
    "automation-first": ("manual step", "automate", "fallback"),
    "api-compatibility": ("contract", "backward", "consumer"),
    "data-integrity": ("serialization", "atomic", "validate"),
    "concurrency-safety": ("race", "lock", "idempotent"),
    "observability-first": ("logs", "diagnostic", "correlation"),
    "prompt-cache-discipline": ("stable prefix", "session", "cached_tokens"),
    "context-compaction-fidelity": ("constraints", "identifiers", "unresolved"),
    "condition-based-waiting": ("poll", "terminal state", "timeout"),
    "failure-injection-testing": ("permission", "network", "partial"),
    "upgrade-path-testing": ("previous version", "fresh install", "preserve"),
    "process-lifecycle-cleanup": ("child process", "cleanup", "exit"),
    "shell-boundary-safety": ("quoting", "exit code", "powershell"),
    "ambiguity-resolution": ("ambiguity", "assumption", "material"),
    "contradiction-detection": ("conflict", "authority", "reconcile"),
    "invariant-driven-design": ("invariant", "boundary", "violation"),
    "adversarial-self-review": ("falsify", "counterexample", "evidence"),
    "minimal-reproducer": ("smallest", "reproduce", "variable"),
    "transactional-updates": ("atomic", "backup", "commit"),
    "partial-success-accounting": ("partial", "status", "failure"),
    "supply-chain-verification": ("provenance", "hash", "signature"),
    "artifact-provenance": ("commit", "toolchain", "provenance"),
    "numerical-sanity-check": ("units", "range", "magnitude"),
    "resource-budgeting": ("budget", "cost", "headroom"),
    "fallback-degradation": ("fallback", "capability", "silent"),
    "retry-idempotency": ("retry", "idempotent", "backoff"),
    "error-taxonomy": ("transient", "permanent", "configuration"),
    "user-intent-lock": ("user intent", "acceptance", "optimization"),
    "test-oracle-quality": ("oracle", "false positive", "mutation"),
    "deterministic-selection": ("order", "tie-break", "deterministic"),
    "compatibility-matrix": ("matrix", "platform", "version"),
    "environment-parity": ("environment", "ci", "production"),
    "schema-evolution": ("schema", "migration", "backward"),
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def frontmatter(text: str) -> tuple[str, str]:
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", text, re.S)
    assert m, "missing YAML frontmatter"
    return m.group(1), m.group(2)


def description_from_fm(fm: str) -> str:
    m = re.search(r"^description:\s*(.*?)(?=^\w+:|\Z)", fm, re.S | re.M)
    return " ".join((m.group(1) if m else "").split()).strip("'\"")


def test_skills() -> None:
    missing = []
    for name, tokens in SKILLS.items():
        p = CANON / name / "SKILL.md"
        if not p.is_file():
            missing.append(name)
            continue
        text = read(p)
        fm, body = frontmatter(text)
        desc = description_from_fm(fm)
        assert desc.startswith("Use when"), f"{name}: description must start 'Use when'"
        assert len(desc) <= 420, f"{name}: description too long ({len(desc)} chars)"
        words = len(body.split())
        assert 45 <= words <= 500, f"{name}: body should be concise/useful, got {words} words"
        low = body.lower()
        for token in tokens:
            assert token.lower() in low, f"{name}: missing contract term {token!r}"
        for provider in PROVIDERS:
            q = ROOT / "1-TAILORED-PROVIDER-TREES" / provider / "COPY-TO-SKILLS-DIRECTORY" / "skills" / name / "SKILL.md"
            assert q.is_file(), f"{provider}: missing {name}"
            assert q.read_bytes() == p.read_bytes(), f"{provider}: {name} drifted from canonical"
    assert not missing, "missing v7.8 reliability skills: " + ", ".join(missing)


def test_all_descriptions_under_budget() -> None:
    offenders = []
    for p in sorted(CANON.glob("*/SKILL.md")):
        fm, _ = frontmatter(read(p))
        desc = description_from_fm(fm)
        if len(desc) > 600:  # audit warning threshold ~=150 tokens
            offenders.append((p.parent.name, len(desc)))
    assert not offenders, "oversized always-loaded descriptions: %r" % offenders


def test_documented_skill_counts() -> None:
    actual = len(list(CANON.glob("*/SKILL.md")))
    # No pinned number here: the count is whatever the tree holds, and every
    # place that RESTATES it must agree. Pinning it meant a deliberate removal
    # failed this gate as if it were an accident.
    assert actual > 100, f"canonical tree looks truncated: {actual} skills"
    readme = read(ROOT / "README.md")
    changelog = read(ROOT / "CHANGELOG.md")
    history = read(ROOT / "docs" / "history" / f"V{BARE}-CHANGELOG.md")
    validation = json.loads(read(ROOT / "VALIDATION.json"))
    assert f"{actual} skills per AI" in readme, "README skill count drift"
    assert f"{actual} canonical skills total" in changelog, "CHANGELOG skill count drift"
    assert str(actual) in history, "release history does not state the shipped skill count"
    assert validation.get("canonical_skills") == actual, "VALIDATION canonical skill count drift"
    assert validation.get("registry_entries") == actual, "VALIDATION registry count drift"
    assert validation.get("provider_trees") == 5, "VALIDATION provider tree count drift"
    # Every provider tree must hold exactly what canonical holds. A skill
    # deleted from canonical but left in five provider trees is still shipped.
    for provider in PROVIDERS:
        tree = ROOT / "1-TAILORED-PROVIDER-TREES" / provider / "COPY-TO-SKILLS-DIRECTORY" / "skills"
        names = {p.parent.name for p in tree.glob("*/SKILL.md")}
        canon = {p.parent.name for p in CANON.glob("*/SKILL.md")}
        assert names == canon, (
            f"{provider} tree drifted from canonical: "
            f"extra={sorted(names - canon)} missing={sorted(canon - names)}"
        )


def test_bootstrap() -> None:
    start = ROOT / "START-HERE.bat"
    assert start.is_file(), "canonical START-HERE.bat missing"
    txt = read(start).lower()
    assert "install-v7-aio.ps1" in txt
    assert "set \"exitcode=%errorlevel%\"" in txt
    assert "exit /b %exitcode%" in txt

    compat = read(ROOT / "INSTALL-V7-AIO.bat").lower()
    assert 'call "%~dp0start-here.bat" %*' in compat
    assert "install-v7-aio.ps1" not in compat
    assert "exit /b %errorlevel%" in compat
    assert "skyrim ai v5" not in compat

    ps = read(ROOT / "INSTALL-V7-AIO.ps1")
    assert VERSION in ps
    doctor = "Test-Installed-State.ps1"
    assert doctor in ps, "final install-state doctor is not invoked"
    assert ps.index(doctor) < ps.index('INSTALL COMPLETE'), "doctor must run before success banner"
    assert "Optional Forge" not in ps, "Forge still presented as manual optional next step"
    assert "BUNDLED-TOOLS\\skyrim-forge\\VERSION.txt" in ps, "AIO no longer reads the in-tree Forge version"
    assert "-BundleVersion" not in ps_code(ROOT / "INSTALL-V7-AIO.ps1"), (
        "AIO still negotiates a bundle version with its own subtree"
    )
    assert "Microsoft.DotNet.SDK.8" in ps, ".NET 8 SDK is required for default Spooky component"




def test_release_checklist_exact_sha_contract() -> None:
    p = CANON / "release-checklist" / "SKILL.md"
    text = read(p).lower()
    assert "required sub-skill" in text and "ci-convergence" in text, "release checklist does not delegate CI convergence"
    assert "exact pushed sha" in text or "exact pushed commit" in text, "release checklist can still follow the wrong run"
    assert "--branch main --limit 1" not in text, "release checklist still polls latest-on-main instead of the pushed SHA"
    assert f"final_pack_version: {BARE}" in text, "release checklist metadata is version-stale"


def test_provider_bootstrap_contract() -> None:
    p = ROOT / "TOOLS" / "Ensure-Provider-CLIs.ps1"
    assert p.is_file(), "fresh-Windows provider bootstrap is missing"
    text = read(p)
    expected = {
        "Claude": "https://claude.ai/install.ps1",
        "Codex": "https://chatgpt.com/codex/install.ps1",
        "Grok": "https://x.ai/cli/install.ps1",
        "Kimi": "https://code.kimi.com/kimi-code/install.ps1",
        "Hermes": "https://hermes-agent.nousresearch.com/install.ps1",
    }
    for provider, url in expected.items():
        assert provider in text and url in text, f"{provider}: official Windows installer missing"
    for token in ("git --version", "claude --version", "codex --version", "grok --version", "kimi --version", "hermes --version"):
        assert token.lower() in text.lower(), f"provider bootstrap missing verification {token!r}"
    assert "Refresh-ProcessPath" in text, "provider installers can update User PATH without the current process seeing it"
    assert "AUTH_REQUIRED" in text, "unavoidable account/OAuth state must be reported explicitly"
    assert "CODEX_NON_INTERACTIVE" in text, "Codex official installer can still prompt during an AIO install"
    assert "Anthropic.ClaudeCode" in text, "Claude official WinGet fallback missing"
    assert "powershell.exe" in text.lower() and "'-File'" in text, "vendor installers are not isolated in a child PowerShell"
    vendor = text[text.index("function Invoke-VerifiedOfficialScript"):text.index("# Claude and Kimi require Git Bash")]
    assert "$LASTEXITCODE" in vendor and "throw" in vendor, "vendor installer child exit code is not fail-closed"


def test_gate_and_remote_fail_closed() -> None:
    gate = read(ROOT / "TOOLS" / "Install-Completeness-Gate.ps1")
    assert "-split ','" in gate or '-split ","' in gate, "comma-delimited child-process provider args are not normalized"
    assert "Codex   skill/native-plugin enforcement" in gate, "Codex zero-chore gate policy not present"
    assert "Codex will ask once" not in gate, "Codex still requires a manual trust prompt"
    assert "HERMES_ACCEPT_HOOKS" in gate, "Hermes one-time noninteractive hook consent missing"

    remote = read(ROOT / "INSTALL-REMOTE.ps1")
    assert "if ($LASTEXITCODE -ne 0) { Fail" in remote, "remote installer can still print DONE after installer failure"

    common = read(ROOT / "TOOLS" / "V7-Common.ps1")
    block = common[common.index("function Install-V5Winget"):]
    block = block[: block.index("function ", 10)]
    assert "$LASTEXITCODE" in block and ("return $false" in block or "throw" in block), "winget failures are not checked"


def test_hermes_cost_contract() -> None:
    parent = ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "config.yaml"
    installed = ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "COPY-TO-PROVIDER-HOME" / "config.yaml"
    for path in (parent, installed):
        cfg = read(path)
        # DeepSeek must actually execute/verify and long tasks must not die at an
        # arbitrary turn ceiling. OpenRouter already retries provider backends,
        # so keep Hermes' whole-request retry layer bounded.
        for token in (
            "max_turns: null",
            "reasoning_effort: max",
            "api_max_retries: 2",
            "tool_use_enforcement: true",
            "execution_guidance: true",
            "intent_ack_continuation: true",
            "stall_guards: true",
            "task_completion_guidance: true",
            "parallel_tool_call_guidance: true",
            "verify_on_stop: true",
            "abort_on_summary_failure: true",
            "auto_reload_on_config_change: false",
            "creation_nudge_interval: 0",
        ):
            assert token in cfg, f"{path}: missing Hermes quality/closure setting {token}"

        # Fixed 120k trigger on the 1M-window default, preserving ~36k of recent
        # tail and multiple true user turns. Avoid tiny rewrites that destroy a
        # warm provider cache prefix; prune only when the reclaim is material.
        assert re.search(r"(?m)^\s*threshold_tokens:\s*120000\s*$", cfg), path
        assert re.search(r"(?m)^\s*target_ratio:\s*0\.30\s*$", cfg), path
        assert re.search(r"(?m)^\s*protect_last_n:\s*20\s*$", cfg), path
        assert re.search(r"(?m)^\s*min_tail_user_messages:\s*3\s*$", cfg), path
        assert re.search(r"(?m)^\s*max_attempts:\s*4\s*$", cfg), path
        assert re.search(r"(?m)^\s*proactive_prune_tokens:\s*80000\s*$", cfg), path
        assert re.search(r"(?m)^\s*proactive_prune_min_reclaim_tokens:\s*32768\s*$", cfg), path
        assert re.search(r"(?m)^\s*micro_compact:\s*false\s*$", cfg), path
        assert re.search(r"(?m)^\s*idle_compact_after_seconds:\s*0\s*$", cfg), path

        assert re.search(r"(?m)^\s*transient_retries:\s*1\s*$", cfg), path
        assert re.search(r"(?m)^\s*cost_threshold_usd:\s*0\.01\s*$", cfg), path
        assert re.search(r"(?ms)^  background_review:\s*\n\s+enabled:\s*false\s*$", cfg), path

        # Context compression is important enough to use the strong paid main
        # model, but summarization itself is mechanical: disable reasoning tokens.
        aux_start = cfg.index("auxiliary:")
        aux_end = cfg.index("\ndisplay:", aux_start)
        aux = cfg[aux_start:aux_end]
        m = re.search(r"(?ms)^  compression:\n(.*?)(?=^  [a-z_]+:|\Z)", aux)
        assert m, f"{path}: Hermes auxiliary.compression block missing"
        compression = m.group(0)
        assert "model: deepseek/deepseek-v4-flash-0731" in compression, path
        assert "reasoning_effort: none" in compression, path

        assert re.search(r"(?m)^\s*cache_ttl:\s*1h\s*$", cfg), path
        assert "response_cache: true" in cfg, path
        assert "response_cache_ttl: 300" in cfg, path
        # Never globally auto-trust future third-party hooks.
        assert not re.search(r"(?m)^hooks_auto_accept:\s*true\s*$", cfg), path
    # At the current V4 Flash 0731 pricing, an extra 10K reasoning tokens are
    # cheaper than replaying a 120K uncached input once. Prefer maximum supported
    # reasoning to reduce repair turns, while keeping the summarizer non-thinking.
    assert parent.read_bytes() == installed.read_bytes(), "Hermes reference config and actual installer source drifted"

def test_forge_source_is_complete_and_buildable() -> None:
    """Forge ships as source in this repository, not as a released archive.

    The two-repo split is what let 7.8.0 ship an installer that called a
    contract field Forge never emitted: two files that had to agree, in two
    repositories, with no single commit that could test both.
    """
    assert FORGE_SOURCE.is_dir(), "BUNDLED-TOOLS/skyrim-forge is missing"
    for rel in ("VERSION.txt", "Install-or-Update.ps1", "Install-Forge-Skill.ps1",
                "Register-MCP.ps1", "START-HERE.bat", "pyproject.toml",
                "skyrim_forge/__init__.py", "skyrim_forge/version.py",
                "skyrim_forge/environment.py", "scripts/validate_repository.py",
                "integrations/skyrim-forge/SKILL.md",
                "writer/published/win-x64/SkyrimForge.Native.exe",
                "writer/published/linux-x64/SkyrimForge.Native"):
        assert (FORGE_SOURCE / rel).is_file(), f"Forge source is missing {rel}"

    version = forge_version()
    assert f'VERSION = "{version}"' in read(FORGE_SOURCE / "skyrim_forge" / "version.py"), (
        "Forge VERSION.txt and skyrim_forge/version.py disagree"
    )
    assert f'const version = "{version}"' in read(FORGE_SOURCE / "writer" / "native-go" / "main.go"), (
        "Forge VERSION.txt and the Go native constant disagree"
    )

    # GitHub reads .github/workflows only from a repository root, so workflows
    # here would look live and never run. Forge's jobs are in the root CI.
    assert not (FORGE_SOURCE / ".github").exists(), (
        "Forge subtree carries a .github directory GitHub will never read"
    )
    root_ci = read(ROOT / ".github" / "workflows" / "ci.yml")
    for job in ("forge-python", "forge-native", "forge-repository-validation",
                "forge-windows-installer", "forge-bundle-install"):
        assert f"  {job}:" in root_ci, f"root CI does not run the Forge job {job}"

    # And no separately released Forge archive may come back: an archive is a
    # second source of truth for a version, which is the whole defect.
    assert not sorted((ROOT / "BUNDLED-TOOLS" / "offline").glob("Skyrim-Forge-*.zip")), (
        "a Forge ZIP payload is back in BUNDLED-TOOLS/offline alongside the source"
    )



def test_offline_manifest_complete() -> None:
    m = json.loads(read(ROOT / "BUNDLED-TOOLS" / "OFFLINE-MANIFEST.json"))
    assert m.get("pack_version") == BARE, "offline manifest pack version drifted"
    declared = {a["file"] for a in m.get("assets", [])}
    actual = {p.name for p in (ROOT / "BUNDLED-TOOLS" / "offline").iterdir() if p.is_file()}
    assert declared == actual, f"offline manifest coverage mismatch declared-only={sorted(declared-actual)} actual-only={sorted(actual-declared)}"
    assert not [f for f in declared if f.startswith("Skyrim-Forge-")], (
        "offline inventory still declares a Forge payload; Forge is source now"
    )
    # A declared size/hash that does not match the bytes on disk is worse than
    # no manifest: the installer trusts it.
    for a in m.get("assets", []):
        blob = (ROOT / "BUNDLED-TOOLS" / "offline" / a["file"]).read_bytes()
        assert len(blob) == a["size"], f"{a['file']}: manifest size {a['size']} != actual {len(blob)}"
        assert hashlib.sha256(blob).hexdigest() == a["sha256"], f"{a['file']}: manifest sha256 does not match the bytes"



def test_manifest_generator_excludes_developer_state() -> None:
    text = read(ROOT / "TOOLS" / "generate_manifest.py")
    for token in (
        ".git", ".worktrees", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".tox", ".nox", "htmlcov", "node_modules", ".venv", "venv", "cache", "dist", "artifacts",
    ):
        assert repr(token) in text or f'"{token}"' in text, f"manifest generator can record developer state: {token}"
    assert "SKIP_NAMES" in text and "'.git'" in text, "linked-worktree .git control file can enter source manifest"

def test_release_builder_contract() -> None:
    b = ROOT / "TOOLS" / "build_release.py"
    assert b.is_file(), "portable deterministic release builder missing"
    text = read(b)
    for token in (
        ".git", ".worktrees", "__pycache__", ".venv", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".tox", ".nox", "htmlcov", ".coverage", "coverage.xml", "artifacts",
        "testzip", "unicode", "sha256",
    ):
        assert token.lower() in text.lower(), f"release builder missing {token} gate"
    assert "FORGE_SOURCE" in text, "Core builder no longer knows where the Forge source is"
    assert "_forge_version" in text, "release builder does not verify the extracted Forge version"

    # A Core archive intentionally omits most BUNDLED-TOOLS/offline payloads,
    # so it cannot ship the Full tree's MANIFEST.json unchanged. Prove the
    # builder rewrites the Core manifest to describe only what it actually
    # ships, and that it carries the Forge SOURCE even though it drops every
    # vendored payload.
    spec = importlib.util.spec_from_file_location("uabs_build_release", b)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="uabs-core-manifest-") as td:
        fake = Path(td) / "root"
        offline = fake / "BUNDLED-TOOLS" / "offline"
        offline.mkdir(parents=True)
        # Linked git worktrees use a root .git control FILE rather than a
        # .git directory. It must never enter the Core manifest.
        (fake / '.git').write_text('gitdir: C:/tmp/worktree\n', encoding='utf-8')
        # The offline inventory must be rewritten for Core too: shipping the
        # Full one made the Core archive declare six payloads it does not carry,
        # and the contract suite run FROM the extracted Core failed on it while
        # the same suite passed on Full.
        offline_inventory = {
            "pack_version": BARE,
            "assets": [
                {"file": "optional-tool.zip", "size": 8, "sha256": hashlib.sha256(b"optional").hexdigest()},
            ],
        }
        required = {
            "START-HERE.bat": b"@echo off\r\n",
            "INSTALL-V7-AIO.ps1": b"# aio\n",
            "BUNDLED-TOOLS/CATALOG.json": b"{}\n",
            "BUNDLED-TOOLS/OFFLINE-MANIFEST.json": (json.dumps(offline_inventory, indent=2) + "\n").encode("utf-8"),
            "VERSION.txt": VERSION.encode("utf-8") + b"\n",
            "BUNDLED-TOOLS/offline/optional-tool.zip": b"optional",
            # Source, not a payload: Core must carry it in full.
            "BUNDLED-TOOLS/skyrim-forge/VERSION.txt": b"Skyrim Forge 9.9.9\n",
            "BUNDLED-TOOLS/skyrim-forge/skyrim_forge/__init__.py": b"\n",
            "BUNDLED-TOOLS/skyrim-forge/writer/published/linux-x64/SkyrimForge.Native": b"binary",
        }
        rows = []
        for rel, data in required.items():
            path = fake / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            rows.append({"path": rel, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        (fake / "MANIFEST.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
        out = Path(td) / "Core.zip"
        module.build(fake, out, True)
        with zipfile.ZipFile(out) as z:
            prefix = f"Ultimate-AI-Starter-Bundle-{VERSION}/"
            core_manifest = json.loads(z.read(prefix + "MANIFEST.json"))
            core_paths = {row["path"] for row in core_manifest}
            assert "BUNDLED-TOOLS/skyrim-forge/VERSION.txt" in core_paths, "Core dropped the Forge source"
            assert prefix + "BUNDLED-TOOLS/skyrim-forge/skyrim_forge/__init__.py" in z.namelist()
            native_info = z.getinfo(prefix + "BUNDLED-TOOLS/skyrim-forge/writer/published/linux-x64/SkyrimForge.Native")
            native_mode = (native_info.external_attr >> 16) & 0o777
            assert native_mode & 0o111, "release ZIP strips executable mode from the Linux Forge native helper"
            assert "BUNDLED-TOOLS/offline/optional-tool.zip" not in core_paths, "Core ships a Full-only manifest row"
            assert prefix + "BUNDLED-TOOLS/offline/optional-tool.zip" not in z.namelist()

            core_offline = json.loads(z.read(prefix + "BUNDLED-TOOLS/OFFLINE-MANIFEST.json"))
            declared = {a["file"] for a in core_offline["assets"]}
            assert declared == set(), f"Core offline inventory describes files it does not ship: {declared}"
            assert core_offline.get("variant") == "Core", "Core offline inventory is not labelled as the Core variant"
            # And the rewritten bytes -- not the source tree's -- must be what
            # the Core MANIFEST.json records, or Core fails its own verifier.
            row = next(r for r in core_manifest if r["path"] == "BUNDLED-TOOLS/OFFLINE-MANIFEST.json")
            shipped = z.read(prefix + "BUNDLED-TOOLS/OFFLINE-MANIFEST.json")
            assert row["size"] == len(shipped) and row["sha256"] == hashlib.sha256(shipped).hexdigest(), (
                "Core MANIFEST.json records the source offline inventory, not the rewritten one"
            )

    ps = read(ROOT / "TOOLS" / "Build-Release.ps1")
    assert "build_release.py" in ps, "PowerShell release path can drift from deterministic Python builder"
    assert "git archive" not in ps.lower(), "legacy release builder still has conflicting git-archive implementation"

    remote = read(ROOT / "INSTALL-REMOTE.ps1")
    assert "*-Full-Offline.zip" in remote, "remote installer does not explicitly prefer Full-Offline artifact"


def test_current_forge_docs_contract() -> None:
    current = [
        ROOT / "README.md",
        ROOT / "TOOLS" / "RECOMMENDED-INSTALLS.md",
        ROOT / "_V7-CANONICAL-SKILLS" / "skyrim-forge" / "SKILL.md",
    ]
    for p in current:
        text = read(p)
        assert "extract it as" not in text.lower(), f"{p}: still tells fresh users to install Forge manually"
        assert "5.1.5+" not in text, f"{p}: stale pre-bundle Forge floor"
    readme = read(ROOT / "README.md").lower()
    shipped = forge_version()
    assert shipped in readme and "bundle" in readme, f"README does not describe bundle-managed Forge {shipped}"
    for stale in ("skyrim forge** is not redistributed", "install it yourself", "### not bundled"):
        assert stale not in readme, f"README contradicts bundle-managed Forge with stale instruction: {stale}"
    current_launch_docs = [
        read(ROOT / "TOOLS" / "RECOMMENDED-INSTALLS.md"),
        read(ROOT / "BUNDLED-TOOLS" / "skyrim-forge" / "README.md"),
    ]
    for doc in current_launch_docs:
        assert ".\\INSTALL-V7-AIO.bat" not in doc, "current docs still recommend the legacy V7 BAT instead of START-HERE"
        assert "Run the bundle's `INSTALL-V7-AIO.bat`" not in doc, "embedded Forge README points at the legacy launcher"



def test_ps51_utf8_reads_are_explicit() -> None:
    roots = [CANON, ROOT / "1-TAILORED-PROVIDER-TREES"]
    offenders = []
    for base in roots:
        for ps in base.rglob("*.ps1"):
            for lineno, line in enumerate(read(ps).splitlines(), 1):
                low = line.lower()
                if line.lstrip().startswith("#") or "ansi-intentional" in low:
                    continue
                if "get-content" in low and "-raw" in low and "-encoding" not in low:
                    offenders.append(f"{ps.relative_to(ROOT)}:{lineno}: {line.strip()}")
    assert not offenders, "Windows PowerShell 5.1 ANSI-decoding reads remain:\n" + "\n".join(offenders)
    # The two legacy skill scripts intentionally carry a UTF-8 BOM so Windows
    # PowerShell 5.1 recognizes UTF-8 source containing non-ASCII characters.
    for base in roots:
        for rel in (
            Path("housecarl/scripts/Setup-HouseCarl.ps1"),
            Path("tool-discovery/scripts/discover_tools.ps1"),
        ):
            for ps in base.rglob(rel.as_posix()):
                assert ps.read_bytes().startswith(b"\xef\xbb\xbf"), f"PS5.1 UTF-8 BOM lost: {ps}"

def test_windows_ci_and_ps51_static_contract() -> None:
    common = read(ROOT / 'TOOLS' / 'V7-Common.ps1')
    assert "$text -split '\\r?\\n'" in common, 'Hermes config line split must be a valid one-line regex'
    remote = read(ROOT / 'INSTALL-REMOTE.ps1')
    assert remote.count("*-Full-Offline.zip") == 1, 'remote installer Full preference block duplicated'
    assert remote.count("*-Core.zip") == 1, 'remote installer Core fallback block duplicated'
    assert "if ($LASTEXITCODE -ne 0) { Fail" in remote, 'remote installer must fail closed on child installer error'
    ci = read(ROOT / ".github" / "workflows" / "ci.yml")
    for cmd in (
        "python TESTS/test_release_contract.py",
        "python TESTS/test_hermes_bootstrap.py",
        "python TOOLS/build_release.py",
    ):
        assert cmd in ci, f"Windows CI does not execute release contract: {cmd}"

    doctor = read(ROOT / "TOOLS" / "Test-Installed-State.ps1")
    assert "System.Collections.Generic.List[string]" in doctor, "doctor uses an ambiguous abbreviated generic type"
    assert "result=if(" not in doctor.replace(" ", ""), "doctor relies on ambiguous inline if syntax in hashtable value"
    assert "System.Text.UTF8Encoding" in doctor, "doctor should use an explicit System.Text encoder type"
    assert "COPY-TO-SKILLS-DIRECTORY\\skills" in doctor, "doctor still checks only a handpicked skill subset"
    assert "Get-FileHash" in doctor and "SHA256" in doctor, "doctor does not prove installed skills match provider-tailored bytes"
    assert "$critical=@(" not in doctor.replace(" ", ""), "partial critical-skill doctor can still pass an incomplete install"
    assert not re.search(r"(?mi)^\s*\$home\s*=", doctor), "doctor assigns PowerShell read-only $HOME (case-insensitive variable names)"
    assert re.search(r"(?mi)^\s*\$providerHome\s*=", doctor), "doctor provider-home assignment is missing or accidentally commented out"
    assert "\\n    $providerHome" not in doctor, "doctor contains literal \\n edit debris that comments out provider-home setup"
    assert "bundle-contract" not in doctor, "final doctor still calls Forge 5.x bundle-contract removed in Forge 6.0.0"
    assert "-m skyrim_forge doctor" in doctor, "final doctor does not use the merged Forge 6 health check"
    aio = read(ROOT / "INSTALL-V7-AIO.ps1")
    assert "$doctorOutput" in aio and "2>&1" in aio and "Select-Object -Last" in aio, "AIO does not persist/replay final-doctor diagnostics before throwing"

    provider = read(ROOT / "TOOLS" / "Ensure-Provider-CLIs.ps1")
    assert "System.Text.UTF8Encoding" in provider, "provider bootstrap should use an explicit System.Text encoder type"



def test_release_contains_no_accidental_next_major_version_surface() -> None:
    """The bundle release is 7.9.1; the accidentally chosen next-major label must not ship."""
    forbidden = "8.0" + ".0"
    text_exts = {".md", ".txt", ".ps1", ".psm1", ".py", ".json", ".yaml", ".yml", ".toml", ".bat", ".cmd"}
    offenders = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in text_exts or path.name == "MANIFEST.json":
            continue
        body = path.read_text(encoding="utf-8", errors="replace")
        if forbidden in body.lower():
            offenders.append(path.relative_to(ROOT).as_posix())
    for path in ROOT.rglob("*"):
        if forbidden in path.name.lower():
            offenders.append(path.relative_to(ROOT).as_posix())
    assert not offenders, f"next-major version contamination remains in v7.9.1 release: {offenders}"


def test_hermes_mcp_registration_is_noninteractive_and_bounded() -> None:
    register = read(FORGE_SOURCE / "Register-MCP.ps1")
    assert "'Y' | & $Executable mcp add" not in register, "Forge Hermes registration still hides an interactive mcp-add prompt"
    assert "hard limit 45s" in register and "Start-Process" in register, "Hermes Forge verification is not visibly time-bounded"
    assert "connect_timeout" in register, "Hermes Forge MCP config lacks a bounded connection timeout"
    reasoning = read(ROOT / "TOOLS" / "Add-Reasoning-MCPs.ps1")
    assert "'y' | & $hx mcp add" not in reasoning, "reasoning-MCP wiring still hides Hermes interactive prompts"

def test_linux_helpers_keep_their_execute_bit() -> None:
    """Every shipped Linux ELF must be executable in git AND in the archives.

    CI found this the hard way: `forge-repository-validation` runs the helper
    straight from a fresh checkout and died with PermissionError, because the
    tree is authored on Windows where `core.filemode` is false and git recorded
    100644. The release builder had the mirror-image bug -- it named one path
    instead of sweeping, so the sibling under `skyrim_forge/bin` shipped 0644.
    """
    helpers = sorted(
        p.relative_to(ROOT).as_posix()
        for p in ROOT.rglob("linux-x64/SkyrimForge.Native")
        if p.is_file()
    )
    assert helpers, "no Linux native helper found; this gate is aimed at nothing"

    spec = importlib.util.spec_from_file_location(
        "uabs_build_release_modes", ROOT / "TOOLS" / "build_release.py"
    )
    assert spec and spec.loader
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    wrong = [h for h in helpers if builder._archive_mode(Path(h)) != 0o100755]
    assert not wrong, f"release archives would ship these Linux helpers non-executable: {wrong}"

    # The git index is the other half. Absent in an extracted release, which is
    # exactly when there is no index to be wrong about.
    if not (ROOT / ".git").exists():
        return
    listing = subprocess.run(
        ["git", "ls-files", "-s", "--", *helpers],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    modes = {row[1]: row[0].split()[0] for row in (line.split("\t", 1) for line in listing) if len(row) == 2}
    missing = [h for h in helpers if h not in modes]
    assert not missing, f"Linux helper is not tracked by git: {missing}"
    not_exec = sorted(path for path, mode in modes.items() if mode != "100755")
    assert not not_exec, (
        f"git records these Linux helpers as non-executable: {not_exec}. "
        "Fix with: git update-index --chmod=+x <path>"
    )


def test_version_sources() -> None:
    assert VERSION.startswith("v") and BARE.count(".") == 2, f"VERSION.txt is not vX.Y.Z: {VERSION!r}"
    assert VERSION.lower() in read(ROOT / "README.md").splitlines()[0].lower()
    assert VERSION.upper() in read(ROOT / "START-HERE.txt").splitlines()[0].upper()
    for rel in ("START-HERE.bat", "INSTALL-V7-AIO.bat"):
        # Not covered by check_versions.py before 7.9.0: both title lines sat
        # at v7.8.0 through the whole release.
        assert VERSION.lower() in read(ROOT / rel).lower(), f"{rel} title is version-stale"
    cat = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    assert cat["pack_version"] in (BARE, VERSION)
    assert cat.get("catalog_version") == BARE, "catalog schema/release version drift"
    forge = next(c for c in cat["components"] if c["id"] == "skyrim-forge")
    assert forge.get("offline_asset") is None, "catalog still points Forge at a released payload"
    assert forge.get("source_dir") == "BUNDLED-TOOLS/skyrim-forge"
    assert forge.get("version") == forge_version(), "catalog Forge version drifted from the source tree"
    readme = read(ROOT / "README.md")
    assert f"Skyrim Forge {forge_version()}" in readme, "README Forge version drifted from embedded source"
    assert "bundle-managed and contract-checked" not in readme, "README still documents the removed cross-repo Forge contract"
    assert f"## Version\n\n**{VERSION}**" in readme, "README Version section does not lead with the current release"
    assert forge.get("install") not in ("manual-user-product", None)


def test_forge_install_directory_is_never_version_stamped() -> None:
    """The bug that kept coming back.

    Every provider stores the MCP command as a hard absolute path, so a
    version-stamped install directory disconnects whichever configs were not
    rewritten on upgrade -- silently, because a provider that cannot spawn its
    server just shows no tools. Live 7.8.0 state: SKYRIM_FORGE_ROOT pointed at
    Skyrim-Forge-5.1.6 (deleted), five configs pointed at Skyrim-Forge (absent),
    and disk held Skyrim-Forge-5.2.0 with no venv.
    """
    text = read(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    code = ps_code(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    assert not re.search(r"Skyrim-Forge-\d+\.\d+", code), "installer code restates a Forge version"
    assert "Refusing a version-stamped Forge install directory" in code, "installer does not refuse a stamped root"
    assert "-ResolveOnly" in text, "install root resolution is not independently testable"
    assert (ROOT / "TESTS" / "Test-ForgeRootResolution.ps1").is_file(), "root resolution gate is missing"


def test_same_version_forge_hotfix_refreshes_shipped_content() -> None:
    """A Forge hotfix must deploy even when VERSION.txt stays at 6.0.0.

    The live failure this protects against: bundle v7.9.1 shipped a corrected
    Register-MCP.ps1 several times while embedded Forge intentionally remained
    6.0.0. The installer compared only VERSION.txt, skipped the source refresh,
    and then executed the stale live Register-MCP.ps1 from the existing Forge
    root. The user therefore kept seeing the old Hermes stdin prompt even though
    the archive contained the fix. Content integrity, not semantic version alone,
    must decide whether shipped Forge files are refreshed.
    """
    code = ps_code(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    assert "Test-ForgeShippedContentCurrent" in code, "Forge refresh still has no content-integrity decision"
    assert "MANIFEST.json" in code, "Forge refresh does not anchor itself to the shipped Forge manifest"
    assert "Get-FileHash" in code, "Forge refresh does not verify installed shipped-file content"
    assert re.search(r"\$refreshRequired\s*=\s*-not\s*\(Test-ForgeShippedContentCurrent", code), (
        "same-version refresh is not driven by shipped-content integrity"
    )
    assert not re.search(r"if\s*\(\$installedVersion\s+-ne\s+\$forgeVersion\)\s*\{", code), (
        "Forge staging is still gated only by VERSION.txt; same-version hotfixes will remain stale"
    )


def test_forge_health_check_reads_fields_forge_emits() -> None:
    """The gate that would have caught the bug that shipped.

    7.8.0 ended the installer with `if (-not $contract.compatible)`. Forge has
    never emitted a `compatible` field, `-not $null` is always true, so it threw
    on every run and the AIO aborted the whole install on the non-zero exit. A
    fresh Windows install of 7.8.0 could not complete. Nothing caught it because
    no test read the installer and the responding source together.

    The handshake is gone -- one repository cannot usefully negotiate a version
    with itself -- so the installer asks `forge doctor`, which can still fail
    for a real reason. This reads every field the installer inspects and proves
    doctor() actually returns it.
    """
    installer = read(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    code = ps_code(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    assert "$contract" not in code, "installer still speaks the retired bundle contract"
    assert "bundle-contract" not in code, "installer still calls the removed bundle-contract command"
    checked = set(re.findall(r"\$doctor\.([A-Za-z_][A-Za-z0-9_]*)", code))
    assert checked, "installer no longer inspects the doctor report at all"
    emitted = doctor_fields()
    unknown = sorted(f for f in checked if f not in emitted)
    assert not unknown, f"installer reads doctor field(s) Forge never emits: {unknown} (emitted: {sorted(emitted)})"

    # And the command it is gone from must really be gone, or a stale install
    # could keep answering an interface nothing maintains.
    assert not (FORGE_SOURCE / "skyrim_forge" / "bundle_contract.py").exists(), (
        "bundle_contract.py is back; the handshake it implements cannot fail for a real reason"
    )
    assert "bundle-contract" not in read(FORGE_SOURCE / "skyrim_forge" / "cli.py"), (
        "forge CLI still exposes bundle-contract"
    )


def test_no_skill_documents_an_unshipped_product() -> None:
    """skyrim-forge-bridge described a 0.2.x product that no longer exists.

    It told the agent Forge cannot write ESP records -- false for the shipped
    5.2 -- and shipped a script hardcoded to a personal Documents\\Apps path.
    A skill that contradicts the tool actually installed is worse than no
    skill: the agent believes it.
    """
    forge_skill = read(CANON / "skyrim-forge" / "SKILL.md")
    assert "bundle-contract" not in forge_skill, "current Forge skill still instructs the removed 5.x handshake"
    assert "# Skyrim Forge 6.0" in forge_skill, "current Forge skill still presents the merged 6.0.0 product as an older series"
    assert "Skyrim-Forge-<version>" not in forge_skill, "current Forge skill still teaches the removed version-stamped install layout"
    assert not (CANON / "skyrim-forge-bridge").exists(), "skyrim-forge-bridge is back"
    dead = ("SKYRIM_FORGE_BRIDGE_ROOT", "skyrim-forge-bridge", "Forge Bridge")
    offenders = []
    for p in CANON.rglob("*"):
        if p.suffix.lower() not in (".md", ".ps1", ".py", ".json") or not p.is_file():
            continue
        body = p.read_text(encoding="utf-8", errors="replace")
        for token in dead:
            if token in body:
                offenders.append(f"{p.relative_to(CANON).as_posix()} -> {token}")
    assert not offenders, f"skills still reference the removed Forge Bridge: {offenders}"


def test_no_skill_script_hardcodes_a_machine_path() -> None:
    """A skill script with someone else's drive letter in it cannot run."""
    bad = []
    for p in CANON.rglob("*"):
        if p.suffix.lower() not in (".ps1", ".py", ".sh") or not p.is_file():
            continue
        for number, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if re.search(r"\$HOME\\\\?Documents", line) or re.search(r"[C-Zc-z]:\\\\Users\\\\[A-Za-z]", line):
                bad.append(f"{p.relative_to(CANON).as_posix()}:{number}")
    assert not bad, f"skill scripts hardcode a machine-specific path: {bad}"


def test_every_v5_helper_called_actually_exists() -> None:
    """A PowerShell call to a function that is not defined is a runtime death.

    7.8.0 dropped Get-V5ClaudeMarketplaceName from TOOLS/V7-Common.ps1 and left
    TESTS/Test-HarnessRealization.ps1 calling it, so that gate died on its first
    check with CommandNotFoundException. It is not in CI -- it inspects a live
    machine -- so nothing noticed for a release. PowerShell has no import-time
    resolution to catch this; a static check is the only thing that can.
    """
    # Two shared modules now, not one. Naming a single file here meant a call
    # into the other read as undefined, and a script that sources only the other
    # was never scanned at all.
    modules = ["V7-Common.ps1", "V7-Mcp-Write.ps1"]
    defined: set = set()
    for module in modules:
        body = read(ROOT / "TOOLS" / module)
        defined |= set(re.findall(r"^function\s+([A-Za-z][A-Za-z0-9-]*)", body, re.M))
    assert "Get-V5PackRoot" in defined, "V7-Common.ps1 no longer parses as expected"
    assert "Add-V5McpJson" in defined, "V7-Mcp-Write.ps1 no longer parses as expected"

    verbs = ("Get|Set|New|Add|Remove|Test|Install|Restore|Repair|Invoke|Update"
             "|Copy|Save|Expand|Resolve|Find|Write|Convert|Import|Export")
    # Call position only. A helper name inside a comment or a quoted string is
    # prose or a pattern, not an invocation: Test-V7-Pack.ps1 legitimately
    # asserts that the AIO does NOT contain "Invoke-V5SkillDedupe -Provider
    # 'Grok'", and V7-Common.ps1 names a retired helper in a comment. Flagging
    # those would make the gate lie, and a lying gate gets switched off.
    call = re.compile(r"(?<![\w\"'`-])((?:" + verbs + r")-V5[A-Za-z0-9]*)(?![\w\"'-])")

    missing = []
    callers = list(sorted(ROOT.glob("*.ps1")))
    for folder in ("TOOLS", "TESTS"):
        callers.extend(sorted((ROOT / folder).glob("*.ps1")))
    for p in callers:
        text = read(p)
        if not any(module in text for module in modules):
            continue
        code = re.sub(r"(?s)<#.*?#>", "", text)          # <# block comments #>
        code = "\n".join(re.sub(r"#.*$", "", line) for line in code.split("\n"))
        local = set(re.findall(r"^\s*function\s+([A-Za-z][A-Za-z0-9-]*)", text, re.M))
        for name in sorted(set(call.findall(code))):
            if name not in defined and name not in local:
                missing.append(f"{p.relative_to(ROOT).as_posix()} calls {name}")
    assert not missing, "undefined shared helper(s): " + "; ".join(sorted(missing))


def test_local_launcher_failure_is_persistent_and_diagnosable() -> None:
    start = read(ROOT / "START-HERE.bat").lower()
    compat = read(ROOT / "INSTALL-V7-AIO.bat").lower()
    ps = read(ROOT / "INSTALL-V7-AIO.ps1")

    # START-HERE is the one canonical local launcher. The legacy V7 BAT is an alias.
    assert 'install-v7-aio.ps1' in start
    assert 'call "%~dp0start-here.bat" %*' in compat
    assert 'install-v7-aio.ps1' not in compat

    # A double-click failure must remain visible, while CI/automation can opt out.
    assert 'pause' in start
    assert 'uabs_no_pause' in start
    assert 'if not "%exitcode%"=="0"' in start
    assert 'exit /b %exitcode%' in start

    # The PowerShell layer keeps durable evidence even when the console vanishes.
    for needle in (
        "Start-Transcript",
        "INSTALL-FAILED.txt",
        "INSTALL-LAST.log",
        "trap {",
        "Stop-Transcript",
    ):
        assert needle in ps, f"installer missing durable failure evidence: {needle}"
    assert "$installLogRoot = Join-Path $env:LOCALAPPDATA" not in ps, "logging path dereferences LOCALAPPDATA before fallback"
    assert "$installLogBase = $env:LOCALAPPDATA" in ps and "$installLogBase = $env:TEMP" in ps, (
        "installer diagnostics need a safe LOCALAPPDATA -> TEMP fallback"
    )


def test_provider_skill_sync_is_content_authoritative() -> None:
    common = read(ROOT / "TOOLS" / "V7-Common.ps1")
    installer = read(ROOT / "INSTALL-V7-AIO.ps1")

    assert "function Sync-V5ProviderSkills" in common, (
        "provider skill installation still has no content-authoritative sync primitive"
    )
    sync_body = common.split("function Sync-V5ProviderSkills", 1)[1].split("function Copy-V5RoboSafe", 1)[0]
    assert "robocopy" not in sync_body.lower(), (
        "provider skill sync still depends on Robocopy metadata classification instead of content-authoritative replacement"
    )
    for needle in ("Get-FileHash", "Move-Item", ".uabs-skill-stage-", ".uabs-skill-backup-"):
        assert needle in sync_body, f"provider skill sync missing {needle} stage/verify/swap contract"
    assert "Sync-V5ProviderSkills -From $srcSkills -To $destSkills" in installer, (
        "AIO does not use content-authoritative provider skill sync"
    )
    assert "Copy-V5Robo -From $srcSkills -To $destSkills" not in installer, (
        "AIO still uses metadata-only whole-tree Robocopy for provider skills"
    )


def test_bundle_forge_install_has_single_skill_writer() -> None:
    wrapper = read(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    installer = read(ROOT / "INSTALL-V7-AIO.ps1")
    assert "[switch]$BundleOwnsProviderSkills" in wrapper, (
        "bundle Forge wrapper has no mode that prevents Forge from replacing bundle-owned provider skills"
    )
    assert "-BundleOwnsProviderSkills" in installer, (
        "AIO does not tell the Forge wrapper that provider skills are already bundle-owned"
    )
    assert "INSTALLATION.json" in wrapper and "bundle-owned Forge skill" in wrapper, (
        "bundle-owned Forge path must add only the per-machine descriptor without replacing SKILL.md"
    )


def test_forge_skill_has_one_canonical_source() -> None:
    canonical = ROOT / "_V7-CANONICAL-SKILLS" / "skyrim-forge" / "SKILL.md"
    embedded = ROOT / "BUNDLED-TOOLS" / "skyrim-forge" / "integrations" / "skyrim-forge" / "SKILL.md"
    assert canonical.read_bytes() == embedded.read_bytes(), (
        "Forge's provider installer overwrites the bundle canonical skyrim-forge skill with divergent content"
    )


def test_forge_install_checked_commands_are_quiet_but_diagnostic() -> None:
    ps = read(ROOT / "BUNDLED-TOOLS" / "skyrim-forge" / "Install-or-Update.ps1")
    head = ps.split("function Find-Python", 1)[0]
    assert "2>&1 | Out-String" in head, (
        "Forge Install-or-Update still streams huge JSON command output directly to the installer console"
    )
    assert "if ($ExitCode -ne 0)" in head and "$Output" in head, (
        "Forge checked-command wrapper must retain child output for failure diagnostics"
    )
    assert "Write-Host" in head and "$Label" in head, (
        "Forge checked-command wrapper must emit a concise progress/result marker"
    )
    assert "[Diagnostics.Stopwatch]::StartNew()" in head and "elapsed" in head.lower(), (
        "Forge checked-command wrapper must show elapsed-time progress instead of appearing to hang"
    )
    assert "..  " in head, "Forge checked-command wrapper must print a start marker before long-running checks"


def test_hermes_forge_probe_bypasses_cli_startup_and_hook_prompts() -> None:
    register = read(FORGE_SOURCE / "Register-MCP.ps1")
    hermes = register.split("'Hermes' {", 1)[1].split("\n            }", 1)[0]
    assert "_probe_single_server" in hermes, (
        "Hermes Forge verification must use the direct MCP probe instead of starting the full Hermes CLI"
    )
    assert "& $Executable" not in hermes and "Start-Process -FilePath $Executable" not in hermes, (
        "Hermes Forge registration still starts hermes.exe, which can trigger first-use shell-hook consent prompts"
    )
    assert "mcp list" not in hermes.lower() and "mcp','test" not in hermes.lower(), (
        "Hermes Forge registration still routes through interactive-capable CLI MCP commands"
    )
    assert ".WaitForExit(" in hermes and "$HermesProcess.WaitForExit()" in hermes, (
        "Hermes probe process must explicitly finalize the child before reading ExitCode/output on Windows PowerShell 5.1"
    )
    assert ".HasExited" not in hermes, (
        "Hermes probe still polls HasExited; PS5.1 can expose an unfinalized/blank ExitCode with redirected streams"
    )


def test_double_click_launcher_keeps_success_visible() -> None:
    start = read(ROOT / "START-HERE.bat").lower()
    assert "installation complete" in start, "START-HERE does not print an explicit success conclusion"
    assert 'if /i not "%uabs_no_pause%"=="1" pause' in start, (
        "successful double-click installs still close immediately instead of keeping the conclusion visible"
    )
    assert start.count('if /i not "%uabs_no_pause%"=="1" pause') >= 2, (
        "pause contract must cover both failure and success paths"
    )


def test_grok_forge_wiring_does_not_warn_before_bundled_forge_install() -> None:
    installer = read(ROOT / "INSTALL-V7-AIO.ps1")
    assert "Skyrim Forge MCP deferred to bundled Forge installer" in installer, (
        "Grok wiring still emits a false 'Skyrim Forge not configured' warning before the bundled Forge component runs"
    )

def main() -> int:
    tests = [
        test_skills,
        test_all_descriptions_under_budget,
        test_documented_skill_counts,
        test_bootstrap,
        test_release_checklist_exact_sha_contract,
        test_provider_bootstrap_contract,
        test_gate_and_remote_fail_closed,
        test_hermes_cost_contract,
        test_forge_source_is_complete_and_buildable,
        test_offline_manifest_complete,
        test_capability_profiles_are_not_registered_globally,
        test_project_scope_is_implemented_not_just_declared,
        test_upgrading_moves_a_globally_registered_profile,
        test_docs_do_not_contradict_the_profile_scope,
        test_extras_never_overwrite_a_skill_the_bundle_vendors,
        test_mcp_config_writing_has_exactly_one_implementation,
        test_npx_pin_reaches_machines_that_already_have_the_entry,
        test_manifest_generator_excludes_developer_state,
        test_release_builder_contract,
        test_current_forge_docs_contract,
        test_ps51_utf8_reads_are_explicit,
        test_windows_ci_and_ps51_static_contract,
        test_release_contains_no_accidental_next_major_version_surface,
        test_hermes_mcp_registration_is_noninteractive_and_bounded,
        test_linux_helpers_keep_their_execute_bit,
        test_version_sources,
        test_forge_install_directory_is_never_version_stamped,
        test_forge_health_check_reads_fields_forge_emits,
        test_no_skill_documents_an_unshipped_product,
        test_no_skill_script_hardcodes_a_machine_path,
        test_every_v5_helper_called_actually_exists,
        test_provider_skill_sync_is_content_authoritative,
        test_bundle_forge_install_has_single_skill_writer,
        test_forge_skill_has_one_canonical_source,
        test_forge_install_checked_commands_are_quiet_but_diagnostic,
        test_local_launcher_failure_is_persistent_and_diagnosable,
        test_hermes_forge_probe_bypasses_cli_startup_and_hook_prompts,
        test_double_click_launcher_keeps_success_visible,
        test_grok_forge_wiring_does_not_warn_before_bundled_forge_install,
    ]
    failed = []
    for fn in tests:
        try:
            fn()
            print("PASS", fn.__name__)
        except Exception as exc:
            failed.append((fn.__name__, exc))
            print("FAIL", fn.__name__, "-", exc)
    print("\n%d passed, %d failed" % (len(tests) - len(failed), len(failed)))
    return 1 if failed else 0


def test_capability_profiles_are_not_registered_globally() -> None:
    """The whole point of the profile catalog.

    MCP tool schemas are in context on every turn of every session, so a
    globally registered server is a permanent cost paid by every unrelated task.
    A profile server that leaked into the always-on list would be exactly the
    regression this release exists to avoid -- and it would be invisible, since
    both lists are just names in different files.
    """
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    reasoning = read(ROOT / "TOOLS" / "Add-Reasoning-MCPs.ps1")

    profile_servers = [s for p in profiles["profiles"] for s in p["servers"]]
    assert profile_servers, "PROFILES.json declares no servers"

    # The half this test used to miss. "Not in the always-on list" is one way to
    # avoid a global registration; declaring scope "global" and being written
    # into every provider's machine-wide config the moment the profile is
    # enabled is the other, and that is what 7.9.5 shipped -- under a `why`
    # paragraph in this same file explaining why it must not.
    for prof in profiles["profiles"]:
        assert prof.get("scope") == "project", (
            f"profile {prof['id']} is not project-scoped: {prof.get('scope')!r}. "
            "A capability server useful in every project belongs in the always-on "
            "core, not here."
        )
        for server in prof["servers"]:
            assert server.get("scope", "project") == "project", (
                f"{prof['id']}/{server['id']} widens its profile's scope to "
                f"{server.get('scope')!r}"
            )

    for server in profile_servers:
        assert f"id      = '{server['id']}'" not in reasoning, (
            f"{server['id']} is a profile server but is also wired globally"
        )
        # An unpinned npx server can change its tool surface mid-session, and
        # npx will happily reuse a broken cache.
        for arg in server["args"]:
            assert not arg.endswith("@latest"), f"{server['id']} pins @latest: {arg}"
        if server["command"] == "npx":
            pkg = next((a for a in server["args"] if not a.startswith("-")), None)
            assert pkg and re.search(r"@[0-9]", pkg), (
                f"{server['id']} npx package is not version-pinned: {pkg}"
            )
            # Without -y, npx blocks on an install prompt for a package that is
            # not cached, and the server never answers initialize. Observed live
            # on Codex with @playwright/mcp@latest.
            assert "-y" in server["args"], f"{server['id']} runs npx without -y"

    # Sweep, do not enumerate. The same two rules apply to every npx server the
    # catalog declares, and CATALOG.json shipped playwright-mcp with no -y while
    # this test only looked at the new profile entries.
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    for comp in catalog["components"]:
        if comp.get("npx_command") != "npx":
            continue
        args = comp.get("npx_args") or []
        assert "-y" in args, f"{comp['id']} runs npx without -y: {args}"
        pkg = next((a for a in args if not a.startswith("-")), None)
        assert pkg and re.search(r"@[0-9]", pkg), (
            f"{comp['id']} npx package is not version-pinned: {pkg}"
        )
        assert not pkg.endswith("@latest"), f"{comp['id']} pins @latest"

    ids = [s["id"] for s in profile_servers]
    assert len(ids) == len(set(ids)), f"duplicate profile server ids: {ids}"

    # A capability declined on purpose is a decision; one declined silently is a
    # gap nobody knows about.
    for entry in profiles.get("evaluated_not_shipped", []):
        assert entry.get("reason"), f"{entry.get('id')} was excluded with no reason"

    # The renamed profile. code-deep held one server and promised depth.
    ids = [p["id"] for p in profiles["profiles"]]
    assert "code-intel" in ids, "the code-intel profile is missing"
    assert "code-deep" not in ids, "the old profile id is still declared"

    # Serena has to be told which project, and told it in the form that can be
    # true where the entry lands: an absolute path for a registration written
    # for one project, and --project-from-cwd for a machine-wide one, since one
    # baked path would activate that project in every unrelated session.
    serena = next(s for s in profile_servers if s["id"] == "serena")
    assert serena.get("project_args") == ["--project", "{project}"], (
        f"Serena is not told its project: {serena.get('project_args')!r}"
    )
    assert serena.get("global_args") == ["--project-from-cwd"], (
        f"a machine-wide Serena would bake one project path: {serena.get('global_args')!r}"
    )


def test_project_scope_is_implemented_not_just_declared() -> None:
    """A scope field nothing reads is worse than no scope field.

    7.9.5 carried one -- `Get-V5ProfileScope` existed and the only thing the
    writer did with the answer was swap Claude's config path. Every other
    provider got the machine-wide file whatever the field said, which is how
    "project-scoped" came to mean "global, with a comment".
    """
    writer = read(ROOT / "TOOLS" / "V7-Mcp-Write.ps1")
    front = read(ROOT / "TOOLS" / "Set-McpProfile.ps1")

    for func in ("Get-V5ProviderProjectTarget", "Get-V5ProviderNoProjectScope",
                 "Get-V5JsonScopeContainer", "Test-V5ServerIsProjectBound",
                 "Test-V5ServerDeclared"):
        assert f"function {func}" in writer, f"{func} missing from the shared writer"

    assert "Get-V5ProviderProjectTarget" in front, (
        "the profile router does not ask where a provider keeps project-scoped servers"
    )
    # Claude Code's own local scope, not the project's .mcp.json: no file in the
    # user's repository and no trust prompt.
    assert "ProjectKey" in writer and "projects" in writer, (
        "the JSON writer cannot address a project-scoped section"
    )
    # A provider that cannot be scoped must be skipped with a reason, never
    # written machine-wide behind a comment claiming otherwise.
    assert "not written: {1}" in front, (
        "a provider without project scope is skipped without saying why"
    )

    # A diagnostic that reads only the machine-wide config cannot see the
    # servers this release moved, and reports a cost no real session pays.
    probe = read(ROOT / "TOOLS" / "Test-McpHandshake.ps1")
    assert "[string]$Path," in probe, "the handshake probe cannot be pointed at a project"
    assert "Get-V5ProviderProjectTarget" in probe, (
        "the handshake probe does not read project-scoped servers"
    )

    # GetFolderPath returns the empty string for a folder that does not exist.
    # Join-Path on that throws and takes the run down inside a helper whose only
    # job is to answer "is Claude Desktop installed".
    assert "function Get-V5AppDataRoot" in writer, (
        "AppData roots are resolved without a guard against an empty result"
    )

    # A native command writing to stderr is not a failure. `uv tool install`
    # prints "already installed" there and exits 0.
    assert "$ErrorActionPreference = 'Continue'" in front, (
        "the auto-install still treats a native command's stderr as fatal"
    )


def test_upgrading_moves_a_globally_registered_profile() -> None:
    """Renaming a profile in a state file does not un-register a server.

    A machine upgrading from 7.9.5 has Serena in the machine-wide config of
    every provider. Migration has to remove those entries and re-register for
    the project the state recorded; a state-only migration would leave the cost
    in place while the state file claimed the profile was project-scoped.
    """
    front = read(ROOT / "TOOLS" / "Set-McpProfile.ps1")
    assert "V5ProfileAliases" in front, "the old profile id no longer resolves"
    assert "'code-deep' = 'code-intel'" in front, "code-deep does not map to code-intel"
    assert "function Convert-V5ProfileState" in front, "there is no state migration"
    assert "function Invoke-V5StaleGlobalMigration" in front, (
        "nothing removes the machine-wide registrations an earlier version wrote"
    )
    gate = read(ROOT / "TESTS" / "Test-McpProfiles.ps1")
    for needle in ("the upgrade drops the machine-wide Claude registration",
                   "an unrelated project has no Serena entry",
                   "a clean install leaves Serena unregistered machine-wide"):
        assert needle in gate, f"the profile gate does not prove: {needle}"


def test_docs_do_not_contradict_the_profile_scope() -> None:
    """7.9.5 shipped both halves of a contradiction in the same commit.

    CATALOG.json's Serena entry said "NOT registered globally". PROFILES.json
    gave every profile scope "global". Whichever a reader found first, the other
    was wrong. Assert the prose and the field agree.
    """
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    assert all(p.get("scope") == "project" for p in profiles["profiles"])

    for comp in catalog["components"]:
        if not comp.get("profile"):
            continue
        assert comp.get("auto_register") is False, (
            f"{comp['id']} carries a profile and is still auto-registered"
        )
        note = comp.get("scope_note") or ""
        assert note, f"{comp['id']} carries a profile with no scope_note"

    declared = {p["id"] for p in profiles["profiles"]}
    for comp in catalog["components"]:
        if comp.get("profile"):
            assert comp["profile"] in declared, (
                f"{comp['id']} names profile {comp['profile']}, which PROFILES.json does not declare"
            )

    skill = read(ROOT / "_V7-CANONICAL-SKILLS" / "capability-profiles" / "SKILL.md")
    assert "code-intel" in skill, "the skill still teaches the old profile id as current"
    assert "Installed is not enabled" in skill, (
        "the skill does not distinguish an installed tool from a registered server"
    )


def test_mcp_config_writing_has_exactly_one_implementation() -> None:
    """Four providers, three config shapes, one writer.

    Every config bug this pack has shipped was a bug in one shape the other two
    did not have: a TOML matcher that stopped at the '[' inside `args = [...]`,
    a Hermes check that read `mcp list` output for a command string, a backslash
    escaped four times instead of two. Two scripts writing configs meant each
    one had to be found twice.
    """
    writer = ROOT / "TOOLS" / "V7-Mcp-Write.ps1"
    assert writer.is_file(), "shared MCP writer missing"
    body = read(writer)
    for func in ("Add-V5McpJson", "Add-V5McpToml", "Add-V5McpHermes",
                 "Remove-V5McpJson", "Remove-V5McpToml", "Remove-V5McpHermes"):
        assert f"function {func}" in body, f"{func} missing from the shared writer"

    for rel in ("TOOLS/Add-Reasoning-MCPs.ps1", "TOOLS/Set-McpProfile.ps1"):
        text = read(ROOT / rel)
        assert "V7-Mcp-Write.ps1" in text, f"{rel} does not dot-source the shared writer"
        assert "function Add-ToJsonMcp" not in text, f"{rel} kept a private JSON writer"

    # PowerShell unrolls a pipeline on `return`, so a one-argument server came
    # back as a bare string and was written as "args": "blender-mcp".
    assert "return ,@(" in body, "argument resolution can unroll a single-element array again"

    gate = ROOT / "TESTS" / "Test-McpProfiles.ps1"
    assert gate.is_file(), "TESTS/Test-McpProfiles.ps1 missing"
    assert "Test-McpProfiles.ps1" in read(ROOT / "TESTS" / "Test-V7-Pack.ps1"), (
        "the MCP profile gate is not chained into the pack gate"
    )


def test_npx_pin_reaches_machines_that_already_have_the_entry() -> None:
    """A fix that cannot reach the machines that need it is not a fix.

    -SkipIfPresent compared only the command. Every npx server has the same
    command, so the comparison always matched and a drifted pin in the args
    survived every upgrade: v7.9.2 pinned Playwright to 0.0.79 and Codex was
    still running @playwright/mcp@latest with no -y, blocking npx on an install
    prompt so the server never answered initialize.
    """
    common = read(ROOT / "TOOLS" / "V7-Common.ps1")
    assert "$argNorm" in common, "Update-V5GrokMcpBlock no longer normalises args for comparison"
    assert "args drifted, rewriting" in common, "a drifted pin is not rewritten or not reported"
    probe = ROOT / "TOOLS" / "Test-McpHandshake.ps1"
    assert probe.is_file(), "TOOLS/Test-McpHandshake.ps1 missing"
    probe_body = read(probe)
    assert "tools/list" in probe_body and "notifications/initialized" in probe_body, (
        "the handshake probe does not run a real MCP exchange"
    )
    # Codex writes its own entries as TOML literal strings; reading only basic
    # strings dropped two real servers from the first report.
    assert "Get-TomlString" in probe_body, "the probe cannot read TOML literal strings"
    assert "$psi.ArgumentList" not in probe_body, (
        "ProcessStartInfo.ArgumentList is .NET Core only; Windows PowerShell 5.1 cannot use it"
    )


def test_extras_never_overwrite_a_skill_the_bundle_vendors() -> None:
    """-WithExtras and the bundled-skill integrity check must not disagree.

    The canonical tree vendors code-review-skill, defuddle, json-canvas,
    obsidian-bases, obsidian-cli and obsidian-markdown. The `skills-git`
    components fetched the same skills from upstream and copied them over the
    top, so the final doctor -- which verifies every provider skill against what
    the bundle shipped -- reported six skills stale/modified on five providers
    and failed the install. Thirty errors, from a switch the installer documents
    and offers. Two writers, one directory: the same defect v7.9.2 fixed for the
    Forge skill, in a different place.
    """
    aio = read(ROOT / "INSTALL-V7-AIO.ps1")
    assert "_V7-CANONICAL-SKILLS" in aio, "the installer no longer knows what canonical owns"
    assert "$ownedByCanonical" in aio, "skills-git does not filter against the canonical tree"
    assert "already vendored by this pack, not overwritten" in aio, (
        "a skipped skill is not reported, so the skip is indistinguishable from a silent failure"
    )

    # The overlap has to be real, or the filter is aimed at nothing. These are
    # the skills both the catalog's skills-git components and the canonical tree
    # claim, confirmed by the doctor failing on exactly these six.
    canonical = {p.parent.name for p in CANON.glob("*/SKILL.md")}
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    git_components = [c for c in catalog["components"] if c.get("install") == "skills-git"]
    assert git_components, "no skills-git components left; this gate is aimed at nothing"
    for comp in git_components:
        folder = comp.get("skill_folder")
        if folder:
            assert folder in canonical or comp.get("skills_subdir"), (
                f"{comp['id']} installs {folder}, which canonical neither vendors nor sources"
            )


if __name__ == "__main__":
    raise SystemExit(main())
