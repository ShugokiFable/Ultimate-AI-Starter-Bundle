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
import sqlite3
import subprocess
import sys
import zipfile
import ast
import hashlib
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANON = ROOT / "_CANONICAL-SKILLS"
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


def shipped_files() -> list[Path]:
    """Tracked checkout files, or every file in an extracted release."""
    if not (ROOT / ".git").exists():
        return [path for path in ROOT.rglob("*") if path.is_file()]
    raw = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True
    ).stdout
    return [ROOT / rel for rel in raw.decode("utf-8").split("\0") if rel]


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
    raw = start.read_bytes()
    assert raw.startswith(b"@echo off"), (
        "START-HERE.bat must begin with ASCII @echo off. A UTF-8 BOM makes "
        "cmd.exe execute a mangled first token and print "
        "a command-not-found error before every install."
    )
    txt = read(start).lower()
    assert "install-aio.ps1" in txt
    assert "set \"exitcode=%errorlevel%\"" in txt
    assert "exit /b %exitcode%" in txt

    # START-HERE.bat is the ONLY local launcher. v8.1.0 deleted
    # INSTALL-V8-AIO.bat, which called it and nothing else: a second name for
    # one action, and a sixth place the version had to be restated by hand.
    assert not (ROOT / "INSTALL-V8-AIO.bat").exists(), (
        "the version-stamped launcher alias is back; one action needs one name"
    )

    ps = read(ROOT / "INSTALL-AIO.ps1")
    assert VERSION in ps
    doctor = "Test-Installed-State.ps1"
    assert doctor in ps, "final install-state doctor is not invoked"
    assert ps.index(doctor) < ps.index('INSTALL COMPLETE'), "doctor must run before success banner"
    assert "Optional Forge" not in ps, "Forge still presented as manual optional next step"
    assert "BUNDLED-TOOLS\\skyrim-forge\\VERSION.txt" in ps, "AIO no longer reads the in-tree Forge version"
    assert "-BundleVersion" not in ps_code(ROOT / "INSTALL-AIO.ps1"), (
        "AIO still negotiates a bundle version with its own subtree"
    )
    assert "Microsoft.DotNet.SDK.8" in ps, ".NET 8 SDK is required for default Spooky component"
    assert "Oven-sh.Bun" in ps and "Find-UabsBunExecutable" in ps, "default Claude plugin install does not provision Bun"
    assert "Microsoft\\WinGet\\Packages\\Oven-sh.Bun_" in ps, "current-process Bun discovery misses Winget's package directory"
    assert "claude-mem','telemetry','disable" in ps, "claude-mem telemetry is left on by the AIO"
    assert "claude-mem','start" in ps, "claude-mem install still leaves its worker as a manual step"




def test_release_checklist_exact_sha_contract() -> None:
    p = CANON / "release-checklist" / "SKILL.md"
    text = read(p).lower()
    assert "required sub-skill" in text and "ci-convergence" in text, "release checklist does not delegate CI convergence"
    assert "exact pushed sha" in text or "exact pushed commit" in text, "release checklist can still follow the wrong run"
    assert "--branch main --limit 1" not in text, "release checklist still polls latest-on-main instead of the pushed SHA"


def test_no_skill_restates_the_pack_version() -> None:
    """A skill that restates the release number is a drift point, not a fact.

    `final_pack_version` lived in 37 skills. Nothing read it at runtime; its only
    consumer was a contract asserting it stayed current, so the field existed to
    serve its own test. 36 of the 37 had drifted anyway -- 4.3.0, 5.0.0 and
    5.1.0 inside a 7.9.x pack -- which makes it worse than useless as a version
    signal. VERSION.txt is the single authority, and a file that does not
    restate a number cannot disagree with it.
    """
    offenders = [
        p.relative_to(ROOT).as_posix()
        for p in ROOT.rglob("SKILL.md")
        if "final_pack_version" in read(p)
    ]
    assert not offenders, (
        "skills restate the pack version again (drift point re-introduced): "
        + ", ".join(sorted(offenders)[:10])
    )


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
    assert "$args += '--approve'" in gate, "Hermes exact bundle-hook consent missing"
    assert "hooks_auto_accept=true" not in ps_code(ROOT / "TOOLS" / "Install-Completeness-Gate.ps1"), (
        "the installer blanket-approves future third-party Hermes hooks"
    )

    remote = read(ROOT / "INSTALL-REMOTE.ps1")
    assert "if ($LASTEXITCODE -ne 0) { Fail" in remote, "remote installer can still print DONE after installer failure"
    assert "Programs\\Ultimate-AI-Starter-Bundle" in remote, "remote installer still uses a version-stamped/state path"
    assert "$dest = $DestRoot" in remote and "$dest + '.previous'" in remote, (
        "remote installer lacks stable destination plus rollback"
    )
    assert "archive version $extractedVersion does not match requested tag $tag" in remote, (
        "remote installer does not validate extracted bytes against the requested release"
    )

    common = read(ROOT / "TOOLS" / "UABS-Common.ps1")
    block = common[common.index("function Install-UabsWinget"):]
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

        # Fixed 160k trigger on the 1M-window default (threshold_tokens is a CAP
        # on context_length * threshold -- agent_init.py passes it as
        # threshold_tokens_cap), preserving ~36k of recent tail and multiple
        # true user turns. Avoid tiny rewrites that destroy a warm provider
        # cache prefix; prune only when the reclaim is material.
        assert re.search(r"(?m)^\s*threshold_tokens:\s*160000\s*$", cfg), path
        assert re.search(r"(?m)^\s*target_ratio:\s*0\.25\s*$", cfg), path
        assert re.search(r"(?m)^\s*protect_last_n:\s*20\s*$", cfg), path
        assert re.search(r"(?m)^\s*min_tail_user_messages:\s*3\s*$", cfg), path
        assert re.search(r"(?m)^\s*max_attempts:\s*4\s*$", cfg), path
        # Proactive tool-result pruning must stay ON. It is the only mechanism
        # operating between 80k and the 160k full-compression trigger: it
        # replaces individual oversized tool results (>=12,000 chars) and
        # nothing else, gated on reclaiming >=32,768 tokens plus a regrowth
        # rearm so it fires episodically rather than every turn. Setting it to
        # 0 does not save prompt cache -- it defers the work to a FULL
        # compression, which rewrites the entire middle window (a strictly
        # larger cache invalidation) and summarizes reasoning, not just blobs.
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


def test_hermes_native_profile_migration_contract() -> None:
    body = read(ROOT / "TOOLS" / "Migrate-HermesProfiles.ps1")
    installer = read(ROOT / "INSTALL-AIO.ps1")

    for token in (
        "profile', 'create'",
        "'--clone-from', 'default'",
        "backup-manifest.json",
        "Get-FileHash",
        "Restore-UabsBackup",
        "Invoke-UabsHermesConfig",
        "if (-not $script:Plan.Count)",
        "Roblox\\mcp.bat",
        "command = 'cmd.exe'",
        "HOUSECARL_MCP",
        "SKYRIM_MO2_INSTANCE",
        "SPOOKY_AUTOMOD_ROOT",
        "WithForgeCompatibility",
        "unowned/user-specific",
    ):
        assert token in body, f"Hermes native-profile migration lost {token!r}"

    assert "default = @('context7', 'github', 'headroom')" in body
    assert "roblox = @('context7', 'github', 'headroom', 'Roblox_Studio')" in body
    assert "skyrim = @('context7', 'github', 'headroom', 'housecarl')" in body
    assert "Migrate-HermesProfiles.ps1" in installer, "the installer no longer runs the profile migration"
    assert "'-File', $hermesProfiles, '-Apply'" in installer, (
        "the installer no longer applies the migration; a dry run writes nothing "
        "and the profile topology never lands"
    )
    # The migrator refuses while Hermes.exe is up. The install closes the
    # desktop app inside the PLUGIN block, which -SkipNativePlugins skips, so
    # the migration call site has to close it too or the topology silently
    # never lands on those runs.
    call_site = installer[installer.index("$hermesProfiles = Join-Path"):]
    call_site = call_site[:call_site.index("'-File', $hermesProfiles, '-Apply'")]
    assert "Get-Process -Name 'Hermes'" in call_site, (
        "the Hermes profile migration no longer closes a running desktop app; "
        "it will degrade to a warning whenever the plugin block is skipped"
    )
    assert "$script:UabsHermesDesktopExe" in call_site, (
        "the migration closes Hermes without recording it for relaunch"
    )
    assert "config', 'set'" not in body, "PowerShell 5.1 corrupts nested Hermes JSON passed through config set"


def test_one_click_install_touches_only_installed_providers() -> None:
    """A plain double-click must not download provider CLIs nobody asked for.

    Through v8.0.4 -Providers defaulted to all five and Ensure-Provider-CLIs.ps1
    then fetched each missing one from its vendor script. Someone whose machine
    had only Claude finished a "one-click install" carrying Codex, Grok, Kimi
    and Hermes, and a provider they had deliberately uninstalled reappeared on
    the next run. Auto-detection is now the default; -AllProviders is the
    explicit way back.
    """
    aio = read(ROOT / "INSTALL-AIO.ps1")
    common = read(ROOT / "TOOLS" / "UABS-Common.ps1")

    assert re.search(r"(?m)^\s*\[string\[\]\]\$Providers\s*=\s*@\(\s*\)\s*,", aio), (
        "-Providers no longer defaults to empty; a hardcoded default list is "
        "what made the installer bootstrap providers the user does not use"
    )
    assert "Get-UabsInstalledProviders" in aio, "the installer no longer asks what is installed"
    assert "[switch]$AllProviders" in aio, "-AllProviders opt-in is gone"
    assert "none detected - bootstrapping all" in aio, (
        "an empty detection must fall back to all five, or a genuinely fresh "
        "machine installs nothing and the run still reports success"
    )
    # ValidateSet cannot survive `powershell -File`, which collapses
    # `-Providers Grok,Claude` into one string. START-HERE.bat forwards through
    # -File, so the comma form has to be split by hand before validating.
    assert "ValidateSet('Claude','Codex','Grok','Kimi','Hermes')]" not in aio.replace(" ", ""), (
        "ValidateSet is back on -Providers; it rejects the comma form that "
        "START-HERE.bat produces"
    )
    assert "$_ -split ','" in aio, "the comma form is no longer split before validation"

    assert "function Get-UabsInstalledProviders" in common
    assert "function Resolve-UabsProviderExe" in common
    # Executable presence only. A ~/.kimi-code or ~/.codex directory survives an
    # uninstall; treating it as an install re-wires a removed provider forever.
    detector = common[common.index("function Get-UabsInstalledProviders"):]
    assert "Resolve-UabsProviderExe" in detector, "the detector no longer resolves an executable"

    gate = ROOT / "TESTS" / "Test-ProviderDetection.ps1"
    assert gate.is_file(), "the provider-detection behavior gate is missing"
    assert "Test-ProviderDetection.ps1" in read(ROOT / "TESTS" / "Test-Pack.ps1"), (
        "the detection gate exists but the pack gate never runs it"
    )


def test_claude_mem_is_opt_in() -> None:
    """The one component that is not one-click must not ride the default path.

    claude-mem installs the Bun runtime, starts a background worker daemon and
    needs a Claude Code restart before its tools appear. Three surprises for
    someone who double-clicked one .bat, so it moved behind -WithClaudeMem.
    """
    aio = read(ROOT / "INSTALL-AIO.ps1")
    extras = aio[aio.index("if (-not $CoreOnly) {"):]
    extras = extras[:extras.index("}")]
    assert "claude-mem" not in extras, (
        "claude-mem is back in the default extras; it pulls in Bun and a "
        "background daemon, which is not a one-click install"
    )
    assert "[switch]$WithClaudeMem" in aio, "-WithClaudeMem opt-in is missing"
    assert "if ($WithClaudeMem)" in aio, "-WithClaudeMem is declared but never honoured"
    # Bun is only fetched for claude-mem, so the opt-out has to remove that too.
    bun = aio[aio.index("$Components -contains 'claude-mem'"):]
    assert "Oven-sh.Bun" in bun[:1200], (
        "the Bun install is no longer gated on claude-mem being requested"
    )


def test_every_defined_contract_is_actually_run() -> None:
    """A contract that is defined but not listed reports nothing, forever.

    CI runs this file as a script, and the script iterates an explicit
    `tests = [...]` list rather than collecting by name. Two contracts sat
    outside that list -- including the one written to guard the Hermes profile
    migration in the same change that added it. They passed under pytest and
    were invisible in CI, which is the worst of both: a green tick for a check
    nobody was running.

    Reading `globals()` is deliberate. Parsing the source for `def test_` would
    be a second opinion about what exists; the module namespace IS what exists.
    """
    module = globals()
    defined = {
        name for name, value in module.items()
        if name.startswith("test_") and callable(value)
        and getattr(value, "__module__", None) == __name__
        and name != "test_every_defined_contract_is_actually_run"
    }
    source = read(Path(__file__))
    # findall + [-1], not index(): the literal "    tests = [" also appears in
    # THIS function's own source, which is earlier in the file. Anchoring on
    # the first occurrence sliced the guard itself, found zero registered
    # names, and reported every contract in the suite as an orphan.
    blocks = re.findall(r"(?ms)^    tests = \[\n(.*?)^    \]", source)
    assert blocks, "the explicit `tests` list is gone; CI runs nothing"
    registered = set(re.findall(r"(test_\w+),", blocks[-1]))
    registered.discard("test_every_defined_contract_is_actually_run")

    orphans = sorted(defined - registered)
    assert not orphans, (
        "defined but never run by CI (add to the `tests` list): " + ", ".join(orphans)
    )
    ghosts = sorted(registered - defined)
    assert not ghosts, (
        "listed but not defined; the script run would crash: " + ", ".join(ghosts)
    )


def test_hermes_tool_budget_is_data_and_internally_consistent() -> None:
    """houseCARL is the most expensive server in the pack; its budget is data.

    45 tools, 167,072 bytes, ~41,768 tokens on EVERY turn -- about 21% of a 200k
    window before the first user message, and billed on a BYOK provider. Hermes
    can filter at the individual-tool level, so the skyrim profile registers a
    subset. The subsets live in CATALOG.json so the numbers can be re-measured
    and checked, and so the next oversized server is a data change.
    """
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    carl = next(c for c in catalog["components"] if c.get("id") == "housecarl")
    budget = carl.get("mcp_tool_budget")
    assert budget, "houseCARL no longer declares an mcp_tool_budget"

    all_tools = budget["all_tools"]
    assert budget["all_schema_bytes"] // 4 == budget["all_tokens_per_turn"], (
        "recorded token figure does not follow from the recorded byte figure"
    )

    # ONE basis for one measurement. Measure-McpSchemaCost reports both a
    # serialized-array total (167,118) and a set of per-tool byte counts that
    # sum to 46 bytes less (167,072). Subset costs can only be built from the
    # per-tool sum, so that is the basis everywhere -- and both figures were
    # briefly in flight, in the release that exists to stop restated numbers
    # drifting. The capability record and the catalog must agree.
    record = json.loads(read(ROOT / "BUNDLED-TOOLS" / "capability-records" / "game-mcp-schema-cost.json"))
    carl_record = next(s for s in record["servers"] if s["id"] == "housecarl")
    assert carl_record["schema_bytes"] == budget["all_schema_bytes"], (
        "the capability record says %s bytes and CATALOG.json says %s for the same "
        "measurement" % (carl_record["schema_bytes"], budget["all_schema_bytes"])
    )
    assert carl_record["approx_tokens_per_turn"] == budget["all_tokens_per_turn"], (
        "the capability record and the catalog disagree on houseCARL's per-turn cost"
    )
    assert carl_record["tools_total"] == all_tools

    sets = budget["sets"]
    for name in ("Full", "Lean", "ReadOnly"):
        assert name in sets, f"tool budget lost the {name!r} set"
        assert sets[name].get("why"), f"{name}: a set with no stated reason is a magic number"

    assert sets["Full"]["tools"] == all_tools
    assert not sets["Full"].get("include") and not sets["Full"].get("exclude"), (
        "Full must carry no filter; it means 'register everything'"
    )

    # Lean is exclusion-based on purpose: a houseCARL update that adds tools
    # keeps them, instead of silently dropping them from an allowlist.
    lean = sets["Lean"]
    assert lean.get("exclude") and not lean.get("include"), (
        "Lean must exclude rather than include, so new upstream tools are not "
        "silently dropped by a stale allowlist"
    )
    assert lean["tools"] == all_tools - len(lean["exclude"]), "Lean tool count does not follow from its exclude list"

    # ReadOnly is inclusion-based on purpose: a new WRITE tool must not appear
    # in a set whose whole promise is that nothing writes.
    ro = sets["ReadOnly"]
    assert ro.get("include") and not ro.get("exclude"), (
        "ReadOnly must be an allowlist, or an upstream update can add a write "
        "tool to the set that promises not to write"
    )
    assert ro["tools"] == len(ro["include"]), "ReadOnly tool count does not match its include list"
    assert len(set(ro["include"])) == len(ro["include"]), "duplicate entry in the ReadOnly allowlist"
    for banned in ("_create", "_bulk_apply", "_set_field", "_remove_", "_merge_", "_compact_"):
        offenders = [n for n in ro["include"] if banned in n]
        assert not offenders, f"ReadOnly includes a write tool: {offenders}"

    for name in ("Lean", "ReadOnly"):
        s = sets[name]
        assert s["tokens_per_turn"] < budget["all_tokens_per_turn"], f"{name} does not save anything"
        assert s["schema_bytes"] // 4 == s["tokens_per_turn"], f"{name}: tokens do not follow from bytes"
        expected_pct = round(100 * (budget["all_schema_bytes"] - s["schema_bytes"]) / budget["all_schema_bytes"])
        assert s["saving_pct"] == expected_pct, (
            f"{name}: stated saving {s['saving_pct']}% but the recorded bytes give {expected_pct}%"
        )


def test_tool_budget_is_applied_without_overwriting_a_user_choice() -> None:
    """The filter is the user's editing surface. Fill it; never replace it.

    `hermes mcp configure <server>` writes tools.include by hand. Re-normalizing
    it on every install is the "puts back what I removed" behavior that provider
    auto-detection exists to end.
    """
    mig = read(ROOT / "TOOLS" / "Migrate-HermesProfiles.ps1")
    aio = read(ROOT / "INSTALL-AIO.ps1")
    doctor = read(ROOT / "TOOLS" / "Test-Installed-State.ps1")

    assert "mcp_tool_budget" in mig, "the migrator no longer reads the budget from the catalog"
    assert "housecarl_bulk_create" not in mig, (
        "tool names are hardcoded in the migrator again; they belong in CATALOG.json "
        "next to the measurement that justifies them"
    )
    assert "$field -eq 'tools' -and $entry.ContainsKey($field)" in mig, (
        "the migrator no longer preserves an existing tool filter"
    )
    assert "$script:ForceToolset" in mig, "-SkyrimToolset no longer overrides the preserve rule"
    assert "$PSBoundParameters.ContainsKey('SkyrimToolset')" in mig, (
        "the override fires on the default value too, so every run overwrites a hand-edited filter"
    )
    # Full means register everything, which requires REMOVING the filter.
    # Ensure-UabsServer only writes fields present in the spec, so omitting
    # `tools` leaves the old filter installed and the run reports no changes.
    assert "RemoveLeaf" in mig, (
        "-SkyrimToolset Full no longer removes an installed filter; it would report "
        "'already matches' while the previous set is still in effect"
    )

    assert "if ($SkyrimToolset) { $profileArgs +=" in aio, (
        "the installer forwards -SkyrimToolset unconditionally; passing it on every "
        "run sets ForceToolset and replaces the user's own filter each install"
    )

    # A doctor that estimates is worse than one that says nothing: three of
    # houseCARL's 45 tools are a quarter of its bytes, so a per-tool average is
    # not an approximation, it is a wrong number in a confident format.
    assert "hermes_tool_budgets" in doctor, "the doctor no longer reports what a profile costs"
    assert "$budget.all_schema_bytes / $allTools" not in doctor, (
        "the doctor is averaging schema bytes across tools again; it reported "
        "~38,983 tok/turn for a set that measures 31,369"
    )
    assert "cost unmeasured" in doctor, (
        "the doctor no longer refuses to price a hand-picked selection"
    )


def test_retired_skills_are_declared_and_cannot_delete_a_live_skill() -> None:
    """The installer copied skills in and never removed what left the tree.

    Measured at v8.2.0 on a real machine: seven retired skills present in three
    provider trees, twenty-one directories, each offered to the agent NEXT TO
    the skill that replaced it. `skyrim-kid-distribution` and `kid-authoring`
    both claimed to own KID syntax and the retired one documented the older
    dialect -- so this is wrong answers, not clutter.
    """
    retired_path = ROOT / "BUNDLED-TOOLS" / "RETIRED-SKILLS.json"
    assert retired_path.is_file(), "RETIRED-SKILLS.json is missing; the installer cannot clean up after itself"
    data = json.loads(read(retired_path))
    entries = data["retired"]
    assert entries, "the retired list is empty; regenerate with TOOLS/generate_retired_skills.py"

    canonical_root = ROOT / "_CANONICAL-SKILLS"
    canonical = {p.name for p in canonical_root.iterdir() if p.is_dir()}
    live_root_entries = {p.name for p in canonical_root.iterdir()}
    names = [e["name"] for e in entries]
    assert len(names) == len(set(names)), "duplicate entry in the retired list"

    # The one failure that would be unrecoverable: a live skill on the delete
    # list. Every run of the installer would remove a skill it just installed.
    overlap = sorted(set(names) & canonical)
    assert not overlap, (
        f"these names are BOTH shipped and marked retired, so the cleanup would "
        f"delete skills the installer just wrote: {overlap}"
    )
    root_overlap = sorted(set(names) & live_root_entries)
    assert not root_overlap, (
        "retired cleanup targets collide with live canonical root entries: %s"
        % root_overlap
    )
    generator = read(ROOT / "TOOLS" / "generate_retired_skills.py")
    assert "len(parts) >= 3" in generator, (
        "the retired-skill generator can mistake canonical root files for skill directories"
    )
    assert data.get("current_skill_count") == len(canonical), (
        "RETIRED-SKILLS.json was generated against a different tree; "
        "re-run TOOLS/generate_retired_skills.py"
    )
    # A successor, where one exists, must actually exist.
    for entry in entries:
        successor = entry.get("superseded_by")
        if successor:
            assert successor in canonical, (
                f"{entry['name']} points at successor {successor!r}, which is not a shipped skill"
            )


def test_cleanup_is_dry_run_by_default_and_scoped_to_pack_files() -> None:
    """A tool that deletes must default to showing, and must only own its own mess."""
    body = read(ROOT / "TOOLS" / "Clean-StaleState.ps1")
    installer = read(ROOT / "INSTALL-AIO.ps1")

    assert "[switch]$Apply" in body, "the cleanup no longer has an -Apply switch"
    # Without this, running the script to LOOK at the plan deletes the files.
    assert "if (-not $Apply) {" in body, "the cleanup no longer short-circuits before deleting"
    assert "Re-run with -Apply" in body, "the dry run no longer says how to proceed"

    # Deletion targets must be pack-owned names, never a bare directory sweep.
    assert "RETIRED-SKILLS.json" in body, "the cleanup no longer reads the declared retired list"
    assert "$canonical.ContainsKey($name)" in body, (
        "the cleanup no longer refuses to delete a name that is in the canonical "
        "tree; a stale retired list could then remove a live skill"
    )
    assert "'SKILL.md'" in body, (
        "the cleanup no longer requires a SKILL.md before removing a directory, "
        "so an unrelated folder sharing a retired name would be deleted"
    )
    for pattern in ("config.toml.*bak*", "settings.json.bak*", "install-*.log", "'dedupe-*'"):
        assert pattern in body, f"the cleanup no longer prunes {pattern}"
    # By far the largest family and the one added last: the plugin dedupe wrote
    # a full skill-tree snapshot on EVERY install. Measured at 160 directories
    # and 52 MB, against 2.1 MB for every .bak file put together.
    assert "Group-Object { ($_.Name -split '-')[1] }" in body, (
        "dedupe snapshots are no longer grouped per provider, so keeping N "
        "would keep N across all providers instead of N for each"
    )

    # Retention must be bounded but never zero-by-accident.
    assert "$KeepBackups = 3" in body and "$KeepLogs = 5" in body, "retention defaults changed silently"
    assert "ValidateRange(1, 200)" in body, "log retention can be set to zero, deleting the evidence of the run that deleted it"

    # And the installer has to actually call it, or nothing self-maintains.
    assert "Clean-StaleState.ps1" in installer, "the installer never runs the cleanup"
    assert "'-Apply', '-PackRoot', $PackRoot" in installer, "the installer runs the cleanup as a dry run, so nothing is ever removed"
    assert "[switch]$SkipCleanup" in installer, "-SkipCleanup opt-out is gone"


def test_tool_routing_prefers_the_free_cli_over_the_expensive_mcp() -> None:
    """Capability-only routing treats a free CLI and a 41k-token MCP as equals.

    Every Skyrim Forge MCP tool has a CLI twin, and a CLI costs nothing until it
    runs. houseCARL has no CLI at all, so its schema is the price of the one
    thing nothing else can do: what wins in the LIVE load order.
    """
    skill = read(ROOT / "_CANONICAL-SKILLS" / "ai-tooling-stack" / "SKILL.md")

    assert "0 tokens" in skill, "the tool table no longer states that a CLI has no standing cost"
    assert "41,768" in skill and "4,372" in skill, "the measured costs left the routing skill"
    assert "MCP only -- no CLI" in skill, (
        "the skill no longer says houseCARL has no CLI, which is the entire "
        "reason its schema is worth paying for"
    )
    # The correction that makes the rest of it true.
    assert "Preferring a cheaper server you have" in skill, (
        "the skill no longer corrects 'prefer the cheaper MCP': preferring "
        "around a registered server saves nothing, because both schemas are in "
        "context every turn regardless of which one is called"
    )
    assert "not registering" in skill, "the skill no longer says where the saving actually comes from"


def _skill_descriptions() -> dict:
    """name -> description, for every shipped canonical skill."""
    out = {}
    for d in sorted(p for p in CANON.iterdir() if p.is_dir()):
        f = d / "SKILL.md"
        if not f.is_file():
            continue
        raw = f.read_bytes()
        assert not raw.startswith(b"\xef\xbb\xbf"), "%s: BOM before frontmatter" % d.name
        txt = raw.decode("utf-8")
        # \s* before the newline: part of the canonical tree is CRLF, and a
        # \n-anchored match would call every one of those skills unloadable.
        m = re.match(r"(?s)^---\s*\n(.*?)\n---\s*\n", txt)
        assert m, "%s: frontmatter block does not close -- not a loadable skill" % d.name
        dm = re.search(r"(?ms)^description:[ \t]*(.*?)(?=^[A-Za-z_-]+:|\Z)", m.group(1))
        assert dm, "%s: no description -- undiscoverable" % d.name
        out[d.name] = " ".join(dm.group(1).split()).strip("\"'")
    return out


def test_skill_index_entry_count_stays_inside_the_measured_budget() -> None:
    """Entry COUNT is the scarce resource, not description length.

    Codex renders its skills index into a fixed ~22.3 KB block split across
    every entry, and each entry costs ~77 chars of name + file path BEFORE it
    describes anything. Measured with `codex debug prompt-input`, one variable
    changed per run: 151 entries -> 80 visible chars, 181 -> 56, 196 -> 40,
    255 -> 16. At 16 chars a description reads "Use when buildin" and the agent
    is routing on skill NAMES alone -- and this pack routes by description.

    Codex also indexes its own system skills and one set per installed plugin,
    so a real machine carries roughly 35-40 entries this pack does not ship.
    The ceiling below leaves room for those.
    """
    skills = _skill_descriptions()
    # 175 canonical + ~40 foreign lands near the 223-entry measured point, where
    # descriptions are down to ~32 chars. Past that the index stops working.
    assert len(skills) <= 175, (
        "%d canonical skills. Codex splits a FIXED index budget across every "
        "entry, so past ~175 the descriptions this pack routes by collapse. "
        "Consolidate into a router with reference files instead of adding "
        "entries -- references are tier 3 and cost nothing." % len(skills)
    )


def test_new_skill_descriptions_are_front_loaded() -> None:
    """At ~40 visible chars the identifying clause has to come first.

    A description whose first 40 characters do not say what the skill is for is
    invisible: that is all the agent sees when the index is over budget.
    """
    skills = _skill_descriptions()
    added = [
        "game-modding", "minecraft-modding", "paradox-modding",
        "unity-mod-frameworks", "unreal-mod-frameworks", "bethesda-creation-modding",
        "github-fleet-maintenance", "mcp-server-diagnostics", "win64-native-builds",
        "windows-workspace-ops", "c-game-regression-testing",
    ]
    for name in added:
        assert name in skills, "%s is no longer shipped" % name
        head = skills[name][:40].lower()
        # The subject has to appear in the visible window, not after it.
        subject = name.split("-")[0].replace("bethesda", "fallout")
        assert subject in head or any(w in head for w in name.split("-")), (
            "%s: first 40 chars are %r, which never says what it is for. That is "
            "the entire visible description when the index is over budget."
            % (name, skills[name][:40])
        )


def test_megapack_consolidation_kept_every_game() -> None:
    """Consolidation is structural. Losing a game to it would be a silent regression.

    73 hand-installed skills became 8. 67 of them were single-file and 56% of the
    pack's 188 KB was byte-identical boilerplate, so the entries were nearly free
    to remove -- but the CONTENT was not, and it is carried verbatim into tier-3
    reference files that cost nothing in the index.
    """
    routers = {
        "game-modding": 19,          # one-off games (+ workflow refs + laws)
        "minecraft-modding": 11,
        "paradox-modding": 5,
        "unity-mod-frameworks": 9,
        "unreal-mod-frameworks": 3,
        "bethesda-creation-modding": 2,
    }
    for name, least in routers.items():
        d = CANON / name
        assert (d / "SKILL.md").is_file(), "%s router is missing" % name
        refs = list((d / "references").glob("*.md"))
        assert len(refs) >= least, (
            "%s has %d reference(s), expected at least %d -- a game or workflow "
            "reference was lost in consolidation" % (name, len(refs), least)
        )

    # Named games that must remain reachable, one per family, plus the auxiliary
    # payloads that are easy to drop when moving trees around.
    for rel in (
        "game-modding/references/factorio.md",
        "game-modding/references/cyberpunk2077.md",
        "game-modding/references/MODDING-LAWS.md",
        "game-modding/references/ERROR-REGISTRY.json",
        "game-modding/references/new_version.py",
        "minecraft-modding/references/PORTING-CHECKLIST.md",
        "unity-mod-frameworks/references/rimworld-harmony.md",
        "unreal-mod-frameworks/references/palworld.md",
        "bethesda-creation-modding/references/starfield.md",
        "roblox-game-development/references/api-docs-lookup.md",
        "release-checklist/references/docs-heavy-repo-sweep.md",
        "mcp-server-diagnostics/references/provider-cli-ops.md",
    ):
        assert (CANON / rel).is_file(), "%s went missing in consolidation" % rel

    # The laws were stated in 41 files and had drifted into two variants; the
    # single copy must be the SUPERSET, not whichever variant was picked up.
    laws = (CANON / "game-modding" / "references" / "MODDING-LAWS.md").read_text(encoding="utf-8")
    # Assert on the ladder's RUNGS, not on the phrase "Evidence ladder": the
    # file's own preamble explains that 20 of 41 source files dropped the
    # ladder, so a phrase match stayed satisfied by that explanation after the
    # section it describes had been deleted. Falsification caught this.
    for rung in ("user-confirmed-runtime", "runtime-evidenced", "tool-validated",
                 "assistant-claimed", "contradicted"):
        assert rung in laws, (
            "the consolidated laws lost the Evidence ladder (missing rung %r). "
            "That is the half 20 of the 41 source files had already silently "
            "dropped, so building the laws from the wrong variant restores the "
            "drift this release removed" % rung
        )


def test_absorbed_skills_are_declared_and_exclude_live_ones() -> None:
    """Derived history cannot see skills this repo never shipped.

    The mega-pack was installed by hand, so nothing in this repository's history
    records those names. Without a declared set the cleanup leaves the loose
    copies in place, competing with the routers that absorbed them -- the exact
    failure the derived list exists to prevent, arriving from the other side.
    """
    data = json.loads((ROOT / "BUNDLED-TOOLS" / "RETIRED-SKILLS.json").read_text(encoding="utf-8"))
    entries = data["retired"]
    names = {e["name"] for e in entries}
    canonical = {p.name for p in CANON.iterdir() if p.is_dir()}

    gen = (ROOT / "TOOLS" / "generate_retired_skills.py").read_text(encoding="utf-8")
    assert "ABSORBED = {" in gen, "the absorbed set is no longer declared"
    assert "(ever | set(ABSORBED)) - current" in gen, (
        "the generator no longer unions declared absorptions with derived history"
    )

    # A sample from each family; if consolidation is real these cannot be live.
    for name in ("factorio-modding", "minecraft-java-modding", "stellaris-modding",
                 "rimworld-harmony-modding", "palworld-modding", "starfield-modding",
                 "game-mod-tool-router", "roblox-docs"):
        assert name in names, "%s was absorbed but is not on the cleanup list" % name
        assert name not in canonical, "%s is both shipped and marked absorbed" % name

    # The three that must survive. Listing any of them deletes a live skill or
    # reaches into another product's directory.
    for name in ("saints-row-modding", "roblox-game-development"):
        assert name in canonical, "%s is no longer shipped" % name
        assert name not in names, (
            "%s is shipped canonically AND on the delete list; every install "
            "would remove a skill it just wrote" % name
        )
    assert "autonomous-ai-agents" not in names, (
        "autonomous-ai-agents is a Hermes CATEGORY directory holding Hermes' own "
        "documentation -- removing it is reaching into another product"
    )
    assert data["current_skill_count"] == len(canonical), (
        "RETIRED-SKILLS.json was generated against a different tree; re-run "
        "TOOLS/generate_retired_skills.py"
    )


def test_canonical_tree_carries_no_maintainer_identity() -> None:
    """This repository is public and skills were adopted from a live machine.

    The Hermes-only skills carried a Windows SID, account name, git email, host
    name and absolute profile paths. None of it is reusable by another user and
    all of it identifies one. The pack's own law is "never assume a drive letter,
    folder name, or username".
    """
    patterns = [
        (re.compile(r"\bS-1-5-21-[0-9]{5,}"), "a Windows SID"),
        (re.compile(r"[A-Za-z0-9_.+-]+@(?!example\.(?:com|org|net)\b)"
                    r"(?!\w*\.?(?:test|invalid|localhost)\b)[A-Za-z0-9-]+\.[A-Za-z]{2,}"),
         "a real email address"),
        (re.compile(r"\bkarlo\b", re.I), "the maintainer's account name"),
    ]
    leaks = []
    for p in CANON.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in (".md", ".txt", ".py", ".ps1", ".json", ".yml", ".yaml"):
            continue
        try:
            txt = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for pat, what in patterns:
            if pat.search(txt):
                leaks.append("%s contains %s" % (p.relative_to(ROOT), what))
                break
    assert not leaks, "identity would be published:\n  " + "\n  ".join(leaks)


def test_doctor_counts_every_skill_root_and_never_interpolates() -> None:
    """Counting one directory understated a 255-entry index as 219.

    Codex indexes its own system skills and one set per ENABLED plugin. The
    doctor first saw only this pack's directory (219 reported against a real
    255), then over-corrected into the whole plugin cache (319 reported
    against a real 197). Both numbers looked like measurements. The fallback
    below is the only branch still allowed to estimate, and it has to say so.
    """
    body = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")

    assert "plugins\\cache" in body or "plugins\\\\cache" in body, (
        "the doctor no longer counts plugin skill roots, so its entry count is "
        "lower than what Codex actually renders"
    )
    assert "$indexCount++" in body and "$packCount++" in body, (
        "the doctor no longer separates pack entries from foreign ones"
    )
    # Measured points only. An interpolated number in the shape of a measurement
    # is worse than no number -- that is how ~88 chars got reported as fine.
    for point in ("151", "196", "255"):
        assert point in body, "the measured curve lost its %s-entry point" % point
    assert "estimated from the nearest measured point" in body, (
        "the doctor's fallback no longer says its figure is estimated from the "
        "nearest MEASURED point, so a reader cannot tell a measurement from an "
        "interpolation"
    )
    # The curve is the fallback, never the headline. Asking Codex outranks it.
    assert body.index("debug' 'prompt-input") < body.index("$curve=@("), (
        "the doctor consults its interpolation curve before asking Codex for "
        "the index Codex actually renders"
    )
    # The old advice would now delete shipped skills.
    assert "OPTIONAL Other-Games mega-pack" not in body, (
        "the doctor still tells users to delete the Other-Games mega-pack, which "
        "as of v8.4.0 IS the canonical tree"
    )
    assert "Clean-StaleState.ps1" in body, (
        "the doctor no longer names the cleanup as the lever that removes "
        "absorbed skills automatically"
    )


# The chain the pack ships, in order. Named once so the three contracts below
# cannot drift apart from each other.
HERMES_FALLBACK_CHAIN = [
    "poolside/laguna-s-2.1:free",
    "thinkingmachines/inkling:free",
    "thinkingmachines/inkling-small:free",
    "poolside/laguna-xs-2.1:free",
]

HERMES_STARTER = ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "config.yaml"


def _yaml_list_of_models(text: str, key: str) -> list:
    """Model ids under a top-level `key:` block, without a YAML dependency.

    The suite is standard-library only; PyYAML is not guaranteed in CI.
    """
    m = re.search(r"(?ms)^%s:\n(.*?)(?=^[A-Za-z_]|\Z)" % re.escape(key), text)
    if not m:
        return []
    return re.findall(r"^\s*model:\s*(\S+)\s*$", m.group(1), re.M)


def test_hermes_starter_ships_a_verified_fallback_chain() -> None:
    """A fallback chain is only consulted when the primary is already failing.

    The starter had no `fallback_providers` at all -- only a commented-out
    example -- so a BYOK user had no failover until they wrote one by hand, and
    every profile cloned from it inherited that gap.
    """
    text = HERMES_STARTER.read_text(encoding="utf-8")
    got = _yaml_list_of_models(text, "fallback_providers")
    assert got == HERMES_FALLBACK_CHAIN, (
        "shipped Hermes fallback chain is %s, expected %s" % (got, HERMES_FALLBACK_CHAIN))

    # laguna-s is TEXT-ONLY on OpenRouter. Putting it first is deliberate (it is
    # the strongest free text model) but it silently drops images, so the
    # multimodal entry has to sit directly behind it, not at the bottom.
    assert got.index("thinkingmachines/inkling:free") == 1, (
        "the multimodal fallback must sit directly behind the text-only first "
        "entry, or a vision task that fails over loses its images with no other "
        "multimodal option nearby")
    assert "text-only" in text or "TEXT-ONLY" in text, (
        "the config no longer warns that the first fallback is text-only")

    # Vision cannot be pointed at a text-only model.
    vision_model = None
    in_vision = False
    for line in text.splitlines():
        if line == "  vision:":
            in_vision = True
            continue
        if in_vision and line and not line.startswith("    "):
            break
        if in_vision:
            model = re.match(r"^    model:\s*(\S+)", line)
            if model:
                vision_model = model.group(1)
                break
    assert vision_model, "auxiliary vision model not found in the starter"
    assert vision_model != "poolside/laguna-s-2.1:free", (
        "the vision auxiliary points at a text-only model; images would be dropped")


def test_hermes_starter_carries_no_machine_state() -> None:
    """The starter is copied into a stranger's Hermes home.

    It is generated by editing a live config, which is exactly how a local
    LM Studio endpoint, a hook path, or an MCP command with an absolute path
    gets published.
    """
    for rel in ("1-TAILORED-PROVIDER-TREES/Hermes/config.yaml",
                "1-TAILORED-PROVIDER-TREES/Hermes/COPY-TO-PROVIDER-HOME/config.yaml"):
        text = (ROOT / rel).read_text(encoding="utf-8")
        for pattern, what in (
            (r"[A-Za-z]:[\\/]Users[\\/]", "an absolute user profile path"),
            (r"localhost:\d+", "a local endpoint"),
            (r"huggingface\.co/", "a personally downloaded model"),
            (r"lm-studio", "a local LM Studio provider"),
            (r"\bkarlo\b", "the maintainer account name"),
        ):
            assert not re.search(pattern, text, re.I), "%s contains %s" % (rel, what)
        assert re.search(r"(?m)^mcp_servers:\s*\{\}\s*$", text), (
            "%s ships MCP servers; those are wired per-machine by the installer "
            "and would carry absolute paths" % rel)
        assert all(ord(c) < 128 for c in text), (
            "%s is a DEPLOYED artifact and must stay pure ASCII -- Hermes re-saves "
            "it with its own YAML writer" % rel)


def test_hermes_profile_prefs_converge_without_clobbering_user_choice() -> None:
    """`profile create --clone-from default` copies once and never re-converges.

    Measured at v8.4.0: default carried the current four-deep free chain while
    roblox and skyrim were still on the chain from the day they were cloned.
    The migration managed `mcp_servers` and nothing else.
    """
    body = ps_code(ROOT / "TOOLS" / "Migrate-HermesProfiles.ps1")

    for model in HERMES_FALLBACK_CHAIN:
        assert model in body, "the migration no longer knows the %r fallback" % model
    assert "UabsSupersededChains" in body, (
        "the migration no longer distinguishes a chain THIS PACK shipped from one "
        "the user chose, so it can only either clobber or do nothing")
    assert "dots-studio/dots-3-note-preview:free|openrouter/free" in body, (
        "the previously shipped chain is no longer declared, so profiles still on "
        "it are never migrated forward")

    # Aliases must be additive. setdefault is the whole guarantee.
    assert "setdefault(key, value)" in body, (
        "alias merge no longer uses setdefault; a user's own alias would be "
        "overwritten by the pack's value")

    # Planned BEFORE the no-op check, or correct MCP topology masks drifted prefs.
    prefs_at = body.index("Ensure-UabsProfilePrefs $profile")
    noop_at = body.index("already match the target architecture")
    assert prefs_at < noop_at, (
        "preferences are planned after the no-op check, so a profile with correct "
        "MCP servers and a stale fallback chain reports 'already match'")

    # And what was written has to be read back.
    assert "Verification failed: $profile fallback chain is" in body, (
        "the migration no longer verifies the fallback chain it just wrote")
    assert "Verification failed: $profile is missing alias" in body, (
        "the migration no longer verifies the aliases it just wrote")


def test_readme_model_guidance_matches_the_shipped_config() -> None:
    """Documented guidance and shipped defaults drift in opposite directions."""
    readme = read(ROOT / "README.md")
    starter = HERMES_STARTER.read_text(encoding="utf-8")

    for model in HERMES_FALLBACK_CHAIN:
        assert model in readme, (
            "README does not document the shipped fallback %r" % model)

    # Every alias the pack ships must be explained, and every alias the README
    # advertises must actually be shipped -- either direction is a lie.
    shipped = set(re.findall(r"^    ([a-z0-9-]+): openrouter/", starter, re.M))
    assert shipped, "the starter no longer ships model aliases"
    for alias in shipped:
        assert ("hermes model %s" % alias) in readme or alias in readme, (
            "alias %r is shipped but never documented" % alias)
    # `local` is the deliberate exception and must stay one: it names a model
    # that exists on one machine, behind a localhost endpoint. Shipping it in
    # the portable starter is exactly what test_hermes_starter_carries_no_
    # machine_state forbids, so the README documents it as something the
    # reader configures rather than something the pack hands them.
    MACHINE_LOCAL_ALIASES = {"local"}
    for alias in re.findall(r"hermes model ([a-z0-9-]+)", readme):
        if alias in MACHINE_LOCAL_ALIASES:
            assert alias not in shipped, (
                "the starter now ships the %r alias; that puts a localhost endpoint "
                "and one machine's model id into the portable config" % alias)
            continue
        assert alias in shipped, (
            "README advertises `hermes model %s` but the starter does not ship "
            "that alias" % alias)


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
    # Core zips ship without BUNDLED-TOOLS/offline; only reconcile when present.
    offline_dir = ROOT / "BUNDLED-TOOLS" / "offline"
    if not offline_dir.is_dir():
        return
    declared = {a["file"] for a in m.get("assets", [])}
    actual = {p.name for p in offline_dir.iterdir() if p.is_file()}
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
            "INSTALL-AIO.ps1": b"# aio\n",
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
        ROOT / "_CANONICAL-SKILLS" / "skyrim-forge" / "SKILL.md",
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
        assert ".\\INSTALL-V8-AIO.bat" not in doc, "current docs still recommend the legacy V7 BAT instead of START-HERE"
        assert "Run the bundle's `INSTALL-V8-AIO.bat`" not in doc, "embedded Forge README points at the legacy launcher"



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
    common = read(ROOT / 'TOOLS' / 'UABS-Common.ps1')
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
    aio = read(ROOT / "INSTALL-AIO.ps1")
    assert "$doctorOutput" in aio and "2>&1" in aio and "Select-Object -Last" in aio, "AIO does not persist/replay final-doctor diagnostics before throwing"

    provider = read(ROOT / "TOOLS" / "Ensure-Provider-CLIs.ps1")
    assert "System.Text.UTF8Encoding" in provider, "provider bootstrap should use an explicit System.Text encoder type"



def test_v8_active_surface_uses_versionless_names() -> None:
    """V8 keeps history intact but active install paths must not carry V5/V7 debt."""
    forbidden = (
        "_V7-CANONICAL-SKILLS", "INSTALL-V7-AIO", "V7-Common",
        "V7-Mcp-Write", "Skyrim-AI-V5",
    )
    text_exts = {".md", ".txt", ".ps1", ".psm1", ".py", ".json", ".yaml", ".yml", ".toml", ".bat", ".cmd"}
    offenders = []
    for path in shipped_files():
        if path.suffix.lower() not in text_exts or path.name == "MANIFEST.json":
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("docs/history/") or rel == "CHANGELOG.md" or rel in (
            "TOOLS/UABS-Common.ps1", "TESTS/test_release_contract.py",
            # Reads this repository's OWN history to derive which skills were
            # retired, so it must name the canonical roots those skills lived
            # under. Naming a historical path in order to search it is not the
            # same as depending on it at install time.
            "TOOLS/generate_retired_skills.py",
        ):
            continue
        body = path.read_text(encoding="utf-8", errors="replace")
        if any(token.lower() in body.lower() for token in forbidden):
            offenders.append(rel)
    assert not offenders, f"version-stamped active V5/V7 surface remains: {offenders}"


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
        for p in shipped_files()
        if p.as_posix().endswith("/linux-x64/SkyrimForge.Native")
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
    # Three or more dot-separated parts: 3-part normal releases, 4-part point
    # releases (7.9.8.5). check_versions.py accepts the same two shapes.
    assert VERSION.startswith("v") and BARE.count(".") >= 2 and all(
        p.isdigit() for p in BARE.split(".")), f"VERSION.txt is not vX.Y.Z(.W): {VERSION!r}"
    assert VERSION.lower() in read(ROOT / "README.md").splitlines()[0].lower()
    assert VERSION.upper() in read(ROOT / "START-HERE.txt").splitlines()[0].upper()
    # Not covered by check_versions.py before 7.9.0: the title line sat at
    # v7.8.0 through a whole release.
    assert VERSION.lower() in read(ROOT / "START-HERE.bat").lower(), "START-HERE.bat title is version-stale"
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

    7.8.0 dropped Get-UabsClaudeMarketplaceName from TOOLS/UABS-Common.ps1 and left
    TESTS/Test-HarnessRealization.ps1 calling it, so that gate died on its first
    check with CommandNotFoundException. It is not in CI -- it inspects a live
    machine -- so nothing noticed for a release. PowerShell has no import-time
    resolution to catch this; a static check is the only thing that can.
    """
    # Two shared modules now, not one. Naming a single file here meant a call
    # into the other read as undefined, and a script that sources only the other
    # was never scanned at all.
    modules = ["UABS-Common.ps1", "UABS-Mcp-Write.ps1"]
    defined: set = set()
    for module in modules:
        body = read(ROOT / "TOOLS" / module)
        defined |= set(re.findall(r"^function\s+([A-Za-z][A-Za-z0-9-]*)", body, re.M))
    assert "Get-UabsPackRoot" in defined, "UABS-Common.ps1 no longer parses as expected"
    assert "Add-UabsMcpJson" in defined, "UABS-Mcp-Write.ps1 no longer parses as expected"

    verbs = ("Get|Set|New|Add|Remove|Test|Install|Restore|Repair|Invoke|Update"
             "|Copy|Save|Expand|Resolve|Find|Write|Convert|Import|Export")
    # Call position only. A helper name inside a comment or a quoted string is
    # prose or a pattern, not an invocation: Test-Pack.ps1 legitimately
    # asserts that the AIO does NOT contain "Invoke-UabsSkillDedupe -Provider
    # 'Grok'", and UABS-Common.ps1 names a retired helper in a comment. Flagging
    # those would make the gate lie, and a lying gate gets switched off.
    call = re.compile(r"(?<![\w\"'`-])((?:" + verbs + r")-Uabs[A-Za-z0-9]*)(?![\w\"'-])")

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
        # A helper realized at runtime out of another shipped file --
        # [regex]::Match($src, '(?s)function Foo \{...') then
        # [scriptblock]::Create(...) -- is defined, just not by a literal
        # `function` statement in this file. Test-Pack does exactly this to
        # exercise the starter guard without executing the installer body.
        # Scoped to files that actually realize code, so a bare mention in
        # prose still counts as undefined.
        if "scriptblock]::Create" in text or "Invoke-Expression" in text:
            local |= set(re.findall(r"function\s+([A-Za-z][A-Za-z0-9-]*)\s*\\?\{", text))
        for name in sorted(set(call.findall(code))):
            if name not in defined and name not in local:
                missing.append(f"{p.relative_to(ROOT).as_posix()} calls {name}")
    assert not missing, "undefined shared helper(s): " + "; ".join(sorted(missing))


def test_local_launcher_failure_is_persistent_and_diagnosable() -> None:
    start = read(ROOT / "START-HERE.bat").lower()
    ps = read(ROOT / "INSTALL-AIO.ps1")

    # START-HERE is the one and only canonical local launcher.
    assert 'install-aio.ps1' in start
    assert 'install-v7-aio.ps1' not in start

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
    common = read(ROOT / "TOOLS" / "UABS-Common.ps1")
    common_code = ps_code(ROOT / "TOOLS" / "UABS-Common.ps1")
    installer = read(ROOT / "INSTALL-AIO.ps1")

    assert "function Sync-UabsProviderSkills" in common, (
        "provider skill installation still has no content-authoritative sync primitive"
    )
    sync_body = common.split("function Sync-UabsProviderSkills", 1)[1].split("function Copy-UabsRoboSafe", 1)[0]
    assert "robocopy" not in sync_body.lower(), (
        "provider skill sync still depends on Robocopy metadata classification instead of content-authoritative replacement"
    )
    for needle in ("Get-FileHash", "Move-Item", ".uabs-skill-stage-", ".uabs-skill-backup-"):
        assert needle in sync_body, f"provider skill sync missing {needle} stage/verify/swap contract"
    assert "Sync-UabsProviderSkills -From $srcSkills -To $destSkills -Provider $prov -ExcludeNames $codexBuiltins" in installer, (
        "AIO does not use content-authoritative provider skill sync"
    )
    assert "$codexBuiltins = @(Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome)" in installer, (
        "Codex built-ins are not dynamically excluded before provider skill sync"
    )
    assert "Copy-UabsRobo -From $srcSkills -To $destSkills" not in installer, (
        "AIO still uses metadata-only whole-tree Robocopy for provider skills"
    )
    for needle in ("managed-skills", "Get-UabsTreeDigest", "retired skill was modified; preserved"):
        assert needle in common, f"managed skill retirement contract missing {needle}"
    assert "existing instructions preserved" in installer, (
        "AIO can still overwrite an existing provider instruction file before merging its managed block"
    )
    assert "function Get-UabsProviderSkillsDir" in common_code, (
        "provider skill paths are inferred from provider homes again"
    )
    assert "Join-Path $env:USERPROFILE '.agents\\skills'" in common_code, (
        "Codex user skills no longer use its supported ~/.agents/skills root"
    )
    assert installer.count("Get-UabsProviderSkillsDir -Provider $prov") >= 3, (
        "one of the AIO skill writers still bypasses the canonical provider skill path"
    )
    for needle in ("managed-skills\\codex.json", "codex-legacy-skills-", "$oldSkill.Name -eq '.system'"):
        assert needle in installer, f"safe Codex legacy-root migration missing {needle}"
    for needle in ("$supportedCopy = Join-Path $destSkills $oldSkill.Name", "$supportedDigest = Get-UabsTreeDigest $supportedCopy"):
        assert needle in installer, f"exact Codex cross-root duplicate migration missing {needle}"


def test_codex_plugins_use_the_official_lifecycle() -> None:
    aio = ps_code(ROOT / "INSTALL-AIO.ps1")
    for command in (
        "'plugin','marketplace','add'", "'plugin','marketplace','upgrade'",
        "'plugin','add'", "'plugin','remove'",
    ):
        assert command in aio, f"Codex official lifecycle missing {command}"
    assert "codex-plugin-src" in aio and "'git'" in aio, (
        "offline Codex plugin source is not materialized as the Git source its CLI requires"
    )
    assert "[plugins.`\"superpowers@ultimate-bundle`\"]" not in aio, (
        "AIO still hand-writes the legacy Codex plugin TOML"
    )
    assert "pluginId" in aio, "Codex inventory parser reads the wrong JSON field"
    assert "$codexCli = Get-UabsCodexCli" in aio, (
        "AIO cannot prefer an independently updatable Codex CLI over Hermes' private shim"
    )
    common = read(ROOT / "TOOLS" / "UABS-Common.ps1")
    assert "\\\\WindowsApps\\\\OpenAI\\.Codex_" in common
    assert "https://github.com/obra/superpowers.git" in aio
    assert "migrated ' + $marketName + ' to its upgradeable upstream Git marketplace" in aio
    assert "existing ownership reconciled read-only" in aio, (
        "-SkipNativePlugins recreates copied skills but never reconciles them "
        "against plugins that are already enabled"
    )
    skipped = aio[aio.index('if (-not $ToolsOnly -and $SkipNativePlugins)'):]
    skipped = skipped[:skipped.index('if (-not $ToolsOnly -and -not $SkipPreamble)')]
    assert "Get-UabsCodexEnabledPluginIds" in skipped and "enabledPlugins" in skipped
    assert "Remove-UabsPluginOwnedSkillCopies" in skipped
    for mutator in ("'plugin','add'", "'plugin','remove'", "'plugin','marketplace'", "plugins install"):
        assert mutator not in skipped, (
            f"the read-only -SkipNativePlugins reconciliation still invokes {mutator}"
        )


def test_hermes_legacy_openrouter_extra_is_migrated_without_replacing_config() -> None:
    starter = read(ROOT / "TOOLS" / "Install-Provider-Starter-Settings.ps1")
    assert "function Remove-UabsHermesLegacyOpenRouterExtra" in starter
    assert "p.get(\"name\") == \"openrouter-extra\"" in starter
    assert 'for section in ("providers", "custom_providers")' in starter
    assert "cfg.pop(section, None)" in starter
    assert "Remove-UabsHermesLegacyOpenRouterExtra -Dest $dest" in starter
    assert "from ruamel.yaml import YAML" in starter
    assert "os.replace(tmp, path)" in starter
    assert "migrate_hermes_state_provider.py" in starter


def test_hermes_stale_session_provider_migration() -> None:
    migration = ROOT / "TOOLS" / "migrate_hermes_state_provider.py"
    assert migration.is_file(), "Hermes state.db provider migration is missing"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        db_path = root / "state.db"
        db = sqlite3.connect(db_path)
        db.execute(
            "create table sessions (id text primary key, model_config text, billing_provider text)"
        )
        db.executemany(
            "insert into sessions values (?, ?, ?)",
            (
                ("legacy", json.dumps({"model": "demo/model", "provider": "openrouter-extra"}), "openrouter-extra"),
                ("legacy-prefixed", json.dumps({"model": "demo/model", "provider": "custom:openrouter-extra"}), "custom"),
                ("current", json.dumps({"model": "demo/model", "provider": "openrouter"}), "openrouter"),
            ),
        )
        db.commit()
        db.close()

        first = subprocess.run(
            [sys.executable, str(migration), str(db_path)],
            text=True,
            capture_output=True,
            check=False,
        )
        assert first.returncode == 0, first.stderr or first.stdout
        db = sqlite3.connect(db_path)
        rows = {
            row[0]: (json.loads(row[1]), row[2])
            for row in db.execute("select id, model_config, billing_provider from sessions")
        }
        db.close()
        assert rows["legacy"] == ({"model": "demo/model", "provider": "openrouter"}, "openrouter")
        assert rows["legacy-prefixed"] == ({"model": "demo/model", "provider": "openrouter"}, "custom")
        assert rows["current"] == ({"model": "demo/model", "provider": "openrouter"}, "openrouter")
        backups = list(root.glob("state.db.uabs-openrouter-extra-*.json"))
        assert len(backups) == 1, "migration did not leave one targeted rollback record"
        rollback = json.loads(backups[0].read_text(encoding="utf-8"))
        assert all("model_config" not in row for row in rollback["rows"]), (
            "targeted rollback copied the whole session config instead of only the changed fields"
        )
        assert {row["provider"] for row in rollback["rows"]} == {
            "openrouter-extra", "custom:openrouter-extra"
        }

        second = subprocess.run(
            [sys.executable, str(migration), str(db_path)],
            text=True,
            capture_output=True,
            check=False,
        )
        assert second.returncode == 0, second.stderr or second.stdout
        assert "migrated=0" in second.stdout
        assert len(list(root.glob("state.db.uabs-openrouter-extra-*.json"))) == 1


def test_hermes_openrouter_picker_uses_the_live_tool_catalog() -> None:
    shim = ROOT / "TOOLS" / "uabs_hermes_openrouter_catalog.py"
    assert shim.is_file(), "Hermes full OpenRouter catalog shim is missing"
    spec = importlib.util.spec_from_file_location("uabs_hermes_openrouter_catalog_test", shim)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    rows = module._catalog_rows(
        [
            {"id": "curated/old", "supported_parameters": ["tools"], "pricing": {"prompt": "1"}},
            {
                "id": "dots-studio/dots-3-note-preview:free",
                "supported_parameters": ["tools"],
                "pricing": {"prompt": "0", "completion": "0"},
            },
            {"id": "image/only", "supported_parameters": ["images"], "pricing": {}},
        ],
        silent_default="curated/old",
    )
    assert [row[0] for row in rows] == [
        "curated/old",
        "dots-studio/dots-3-note-preview:free",
    ], "Hermes still gates OpenRouter discovery through a curated allowlist"
    assert rows[0][1] == "default"
    assert rows[1][1] == "free"

    starter = read(ROOT / "TOOLS" / "Install-Provider-Starter-Settings.ps1")
    assert "Install-UabsHermesOpenRouterCatalogShim" in starter
    assert "uabs_hermes_openrouter_catalog.pth" in starter
    assert "Install-UabsHermesOpenRouterCatalogShim -Dest $dest" in starter


def test_hermes_receives_the_combined_soul_and_aio_contract() -> None:
    installer = ps_code(ROOT / "INSTALL-AIO.ps1")
    assert "Install-UabsPreambleBlock -Path $hSoul -SoulFile $soulF -AioFile $aioF" in installer, (
        "Hermes still bypasses the shared SOUL + AIO preamble writer"
    )
    assert "Copy-Item -LiteralPath $soulF -Destination $hSoul" not in installer, (
        "Hermes still resets SOUL.md to the short base soul"
    )


def test_bundle_forge_install_has_single_skill_writer() -> None:
    wrapper = read(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    installer = read(ROOT / "INSTALL-AIO.ps1")
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
    canonical = ROOT / "_CANONICAL-SKILLS" / "skyrim-forge" / "SKILL.md"
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
    installer = read(ROOT / "INSTALL-AIO.ps1")
    assert "game-mcp-global-migration" in installer, (
        "AIO does not migrate old bundle-owned Skyrim MCP registrations out of global configs"
    )
    assert "Remove-UabsGlobalMcpRegistration -Ids @('skyrim-forge','housecarl','codebase-memory-mcp')" in installer
    assert "Update-UabsGrokMcpBlock -Name 'skyrim-forge'" not in installer, (
        "AIO still re-registers Skyrim Forge machine-wide after declaring it profile-only"
    )
    assert "Update-UabsGrokMcpBlock -Name 'codebase-memory-mcp'" not in installer, (
        "AIO still re-registers codebase-memory machine-wide after declaring it profile-only"
    )


def test_aio_prompt_cache_ci_and_game_profile_contract() -> None:
    prompt = read(ROOT / "0-UNRESTRAINT-PACKS" / "AIO-INSTRUCTION.md")
    for needle in ("prompt-cache locality", "cached-input tokens", "Installed is not enabled",
                   "exact commit SHA", "terminal successful state"):
        assert needle in prompt, f"AIO prompt lost its efficiency/release contract: {needle}"
    # NOTE: the wording inside AIO-INSTRUCTION.md is the operator's own edit;
    # no assertion polices its phrasing.

    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    by_id = {p["id"]: p for p in profiles["profiles"]}
    for pid in ("game-skyrim", "game-skyrim-load-order", "game-roblox", "game-saints-row"):
        assert pid in by_id, f"missing game-scoped profile {pid}"
        assert by_id[pid].get("scope") == "project"
    saints = by_id["game-saints-row"]["detect"]
    assert saints.get("json"), "Saints Row detection fell back to every generic project.json"
    router = read(ROOT / "TOOLS" / "Set-McpProfile.ps1")
    assert "$d.Contains('json')" in router and "ConvertFrom-Json" in router

    starter = read(ROOT / "TOOLS" / "Install-Provider-Starter-Settings.ps1")
    for needle in ("Merge-UabsHermesEfficiencyDefaults", "config get", "config set",
                   "prompt_caching.cache_ttl", "existing values preserved"):
        assert needle in starter, f"Hermes reset repair lost {needle}"



def test_no_shipped_config_carries_a_maintainer_path() -> None:
    """7.9.6 shipped this maintainer's own Steam drive in a profile requirement.

    `S:\\Steam\\steamapps\\common\\Blender\\blender.exe` cannot match on anybody
    else's machine, in a pack whose own rule is that a drive letter is never
    assumed. There was already a check for skill scripts; the data files it did
    not cover are exactly where it happened.
    """
    suspects = [
        ROOT / "BUNDLED-TOOLS" / "PROFILES.json",
        ROOT / "BUNDLED-TOOLS" / "CATALOG.json",
        ROOT / "TOOLS" / "Set-McpProfile.ps1",
        ROOT / "TOOLS" / "UABS-Mcp-Write.ps1",
        ROOT / "TOOLS" / "Test-McpHandshake.ps1",
    ]
    # A drive letter that is not the conventional C:, and any user profile path
    # with a literal name in it. %VARS% and {project} are the portable forms.
    drive = re.compile(r"(?<![A-Za-z0-9_%])([D-Zd-z]):[\\/]{1,2}[A-Za-z0-9]")
    userdir = re.compile(r"(?i)[\\/](?:Users|home)[\\/](?!%|<|\{)[A-Za-z0-9._-]+[\\/]")
    offenders = []
    for path in suspects:
        if not path.is_file():
            continue
        for i, line in enumerate(read(path).splitlines(), 1):
            stripped = line.strip()
            # Examples inside prose are how the rule gets taught; a value is a
            # different thing. Only flag lines that look like configuration.
            if stripped.startswith("#") or stripped.startswith("//"):
                continue
            for rx, what in ((drive, "drive letter"), (userdir, "user directory")):
                m = rx.search(line)
                if m:
                    offenders.append(f"{path.name}:{i} {what}: {stripped[:110]}")
    assert not offenders, "maintainer-specific paths in shipped config:\n  " + "\n  ".join(offenders)


def test_bundle_stays_free_and_accountless() -> None:
    """Supabase was withdrawn in 7.9.7 and must not come back, nor be replaced.

    It was the only profile that required an account and a personal access
    token, against this pack's default of free, local, keyless and no signup.
    """
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))

    ids = [p["id"] for p in profiles["profiles"]]
    assert "cloud" not in ids, "the withdrawn Supabase profile is back"
    for prof in profiles["profiles"]:
        for server in prof["servers"]:
            # Notes may explain why an endpoint is blocked. Only executable
            # configuration can bring the withdrawn account service back.
            live_surface = {
                key: server.get(key)
                for key in ("id", "command", "args", "editor_side", "requires", "key")
            }
            blob = json.dumps(live_surface).lower()
            assert "supabase" not in blob, f"{prof['id']}/{server['id']} references Supabase"
            # A profile gated on an API key is an account requirement by another
            # name. Any future one has to be argued for here deliberately.
            key = server.get("key")
            assert not key, (
                f"{prof['id']}/{server['id']} requires {key}. This pack's default is "
                "free, local and keyless; adding an account-dependent server needs "
                "this contract updated on purpose."
            )
    assert not any(c.get("id") == "supabase-mcp" for c in catalog["components"]), (
        "supabase-mcp is back in CATALOG.json"
    )
    # Withdrawing it from the catalog does not un-register it from a machine.
    front = read(ROOT / "TOOLS" / "Set-McpProfile.ps1")
    assert "UabsRetiredProfiles" in front and "'cloud'" in front, (
        "nothing un-registers a withdrawn profile from machines that enabled it"
    )


def test_visual_verification_ships_its_own_falsifiable_check() -> None:
    """A skill that says "look at the screenshot" is unfalsifiable on its own.

    The honest report and the fabricated one are the same sentence, so the skill
    ships a canary: an image whose contents are recorded only as a hash, and a
    checker that answers PASS or FAIL.
    """
    skill = ROOT / "_CANONICAL-SKILLS" / "visual-verification" / "SKILL.md"
    assert skill.is_file(), "the visual-verification skill is missing"
    body = read(skill)
    for needle in ("Test-VisionCanary", "visual verification unavailable"):
        assert needle in body, f"visual-verification does not mention {needle}"

    checker = ROOT / "TOOLS" / "Test-VisionCanary.ps1"
    assert checker.is_file(), "the vision canary checker is missing"
    canary_png = ROOT / "TOOLS" / "vision-canary" / "vision-canary.png"
    canary_meta = ROOT / "TOOLS" / "vision-canary" / "canary.json"
    assert canary_png.is_file(), "the canary image is missing"
    assert canary_meta.is_file(), "the canary metadata is missing"

    meta = json.loads(read(canary_meta))
    assert re.fullmatch(r"[0-9a-f]{64}", meta.get("answer_sha256", "")), (
        "the canary answer is not stored as a hash"
    )
    # The point of hashing it: reading the repository must not substitute for
    # looking at the image.
    for path in (canary_meta, checker, skill):
        text = read(path).lower()
        for word in ("marlowe", "triangle"):
            assert word not in text, (
                f"{path.name} leaks the canary answer in plain text, which makes "
                "the check bluffable"
            )


def test_always_on_core_is_three_servers_and_says_why() -> None:
    """sequential-thinking left the always-on set on a measurement.

    One tool, but a 4,587-byte schema: ~1,146 tokens on every turn of every
    session, as much as context7's two tools, for a structured scratchpad rather
    than a capability. It must not drift back without that being revisited.
    """
    reasoning_script = read(ROOT / "TOOLS" / "Add-Reasoning-MCPs.ps1")
    servers_block = reasoning_script.split("$servers = @(", 1)[1].split("\n)", 1)[0]
    assert "'context7'" in servers_block, "context7 left the always-on core"
    assert "github" in servers_block, "github left the always-on core"
    assert "'headroom'" in reasoning_script, "headroom is not registered across provider configs"
    assert "sequential-thinking" not in servers_block, (
        "sequential-thinking is back in the always-on core; if that is deliberate, "
        "re-measure its per-turn schema cost and update this contract"
    )
    # Told, not silently removed, on machines that already have it.
    assert "Show-UabsSequentialThinkingNotice" in reasoning_script, (
        "machines that already have sequential-thinking are never told it moved"
    )

    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    prof = next((p for p in profiles["profiles"] if p["id"] == "reasoning"), None)
    assert prof, "sequential-thinking was removed from always-on with nowhere to go"
    cost = prof["servers"][0].get("measured_cost") or {}
    assert cost.get("approx_tokens_per_turn"), (
        "the reasoning profile does not record what it costs"
    )


def test_blender_is_pinned_and_discovered() -> None:
    """`uvx blender-mcp` was the one unpinned invocation in the catalog."""
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    blender = next(
        s for p in profiles["profiles"] if p["id"] == "engine-blender" for s in p["servers"]
    )
    pkg = next((a for a in blender["args"] if not a.startswith("-")), None)
    assert pkg and re.search(r"@[0-9]", pkg), f"blender-mcp is not version-pinned: {pkg}"
    paths = blender["requires"]["any_path"]
    assert any("%APPDATA%" in p for p in paths), (
        "Blender is not discovered from the user directory it creates on first run"
    )
    # 'The MCP executable starts' and 'the addon is connected' are different
    # claims, and the profile has to say so.
    assert "editor_side_note" in blender and "different claims" in blender["editor_side_note"]
    assert blender.get("env_static", {}).get("BLENDER_MCP_DISABLE_TELEMETRY") == "true", (
        "blender-mcp sends a startup event before Blender connects; the profile "
        "must carry its supported environment opt-out"
    )
    assert blender.get("env_static", {}).get("BLENDER_MCP_SAFE_MODE") == "true", (
        "blender-mcp can validate generated Python before it reaches Blender; "
        "the optional profile must enable that boundary"
    )
    writer = read(ROOT / "TOOLS" / "UABS-Mcp-Write.ps1")
    assert "env_static" in writer and "Resolve-UabsServerEnv" in writer, (
        "the Blender telemetry opt-out is decorative; the shared provider writer "
        "does not carry static environment policy into provider configs"
    )


def test_profile_package_pins_follow_the_component_catalog() -> None:
    """Profile wiring must not keep a second, stale copy of a package pin."""
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    components = {c["id"]: c for c in catalog["components"]}
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    seen: set[str] = set()
    for profile in profiles["profiles"]:
        for server in profile.get("servers", []):
            component_id = server.get("catalog_component")
            if not component_id:
                continue
            seen.add(component_id)
            assert component_id in components, (
                f"profile {profile['id']} points at unknown catalog component {component_id}"
            )
            expected = str(components[component_id].get("version") or "")
            assert expected, f"catalog component {component_id} has no version to bind"
            executable_surface = " ".join(
                [str(x) for x in server.get("args", [])]
                + [str(server.get("editor_side") or "")]
            )
            pins = re.findall(r"@([0-9][0-9A-Za-z.-]*)", executable_surface)
            assert pins, (
                f"profile {profile['id']} declares catalog_component={component_id} "
                "but has no versioned package invocation"
            )
            assert set(pins) == {expected}, (
                f"profile {profile['id']} pins {component_id} at {sorted(set(pins))}, "
                f"catalog declares {expected}"
            )

    expected_links = {
        "playwright-mcp", "chrome-devtools-mcp", "shadcn-mcp", "blender-mcp",
        "godot-mcp", "unity-mcp", "windows-mcp",
    }
    assert expected_links <= seen, (
        "versioned profile components are not bound to the catalog: "
        + ", ".join(sorted(expected_links - seen))
    )


def test_local_security_boundaries_stay_hardened() -> None:
    """Bind the exact trust boundaries that produced actionable CodeQL alerts."""
    canonical_server = read(CANON / "brainstorming" / "scripts" / "server.cjs")
    canonical_helper = read(CANON / "brainstorming" / "scripts" / "helper.js")
    bundled = ROOT / "BUNDLED-TOOLS" / "plugins" / "superpowers"
    assert canonical_server == read(bundled / "skills" / "brainstorming" / "scripts" / "server.cjs")
    assert canonical_helper == read(bundled / "skills" / "brainstorming" / "scripts" / "helper.js")
    assert "sessionStorage" not in canonical_server + canonical_helper
    assert "encodeURIComponent(TOKEN)" in canonical_server
    assert "decodeURIComponent(value)" in canonical_server
    assert "new WebSocket(websocketUrl())" in canonical_helper
    auth_test = read(bundled / "tests" / "brainstorm-server" / "auth.test.js")
    assert "</script><script>alert(1)</script>" in auth_test
    assert "COOKIE_VALUE = encodeURIComponent(TOKEN)" in auth_test

    impeccable = CANON / "impeccable" / "scripts"
    live_server = read(impeccable / "live-server.mjs")
    assert "boundedPollDuration(url.searchParams.get('timeout')" in live_server
    assert "boundedPollDuration(url.searchParams.get('leaseMs')" in live_server
    live_browser = read(impeccable / "live-browser.js")
    assert ".replace(/^-ms-/, '-ms-')" not in live_browser
    assert "escapeRegExp(attrMatch)" in read(impeccable / "live-accept.mjs")
    regression = subprocess.run(
        ["node", str(ROOT / "TESTS" / "impeccable-security-regressions.mjs")],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert regression.returncode == 0, regression.stdout + regression.stderr
    assert "impeccable security regressions PASS" in regression.stdout

    ponytail = read(ROOT / "BUNDLED-TOOLS" / "plugins" / "ponytail" / "hooks" / "ponytail-instructions.js")
    assert r'^-\s*([^\s:][^:]*):[ \t]*"' in ponytail
    assert "100_000" in read(ROOT / "BUNDLED-TOOLS" / "plugins" / "ponytail" / "pi-extension" / "test" / "helpers.test.js")
    assert "Ultimate-AI-Starter-Bundle-AIO/8.0.0" not in read(ROOT / "TOOLS" / "UABS-Common.ps1")


def test_catalog_freshness_auditor_self_checks() -> None:
    result = subprocess.run(
        [sys.executable, str(ROOT / "TOOLS" / "audit_catalog_versions.py"), "--self-test"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "self-test PASS" in result.stdout


def main() -> int:
    tests = [
        # v7.9.8 -- the starter template is not a place to register MCP servers,
        # and the routing decision has to be measurable.
        test_starter_templates_declare_no_mcp_servers,
        test_no_unpinned_package_in_live_templates,
        test_retired_github_package_cannot_become_live_config,
        test_hermes_readme_matches_the_shipped_starter,
        test_both_hermes_config_copies_agree,
        test_starter_installer_refuses_the_shape_not_the_symptoms,
        test_capability_routing_owns_tool_selection,
        test_every_version_gate_accepts_the_shipped_version,
        test_capability_claims_match_the_measured_record,
        test_optional_key_server_is_not_registered_for_a_sliver_of_itself,
        test_full_default_owns_optional_servers_and_coreonly_opts_out,
        test_schema_cost_is_measurable_not_just_asserted,
        test_no_skill_restates_the_pack_version,
        test_skills,
        test_all_descriptions_under_budget,
        test_documented_skill_counts,
        test_bootstrap,
        test_release_checklist_exact_sha_contract,
        test_provider_bootstrap_contract,
        test_gate_and_remote_fail_closed,
        test_hermes_cost_contract,
        test_one_click_install_touches_only_installed_providers,
        test_claude_mem_is_opt_in,
        test_hermes_tool_budget_is_data_and_internally_consistent,
        test_tool_budget_is_applied_without_overwriting_a_user_choice,
        test_retired_skills_are_declared_and_cannot_delete_a_live_skill,
        test_cleanup_is_dry_run_by_default_and_scoped_to_pack_files,
        test_tool_routing_prefers_the_free_cli_over_the_expensive_mcp,
        # v8.4.0 -- entry COUNT is the scarce resource in a skills index.
        test_skill_index_entry_count_stays_inside_the_measured_budget,
        test_new_skill_descriptions_are_front_loaded,
        test_megapack_consolidation_kept_every_game,
        test_absorbed_skills_are_declared_and_exclude_live_ones,
        test_canonical_tree_carries_no_maintainer_identity,
        test_doctor_counts_every_skill_root_and_never_interpolates,
        # v8.5.0 -- a cloned Hermes profile drifts and nothing re-converged it.
        test_hermes_starter_ships_a_verified_fallback_chain,
        test_hermes_starter_carries_no_machine_state,
        test_hermes_profile_prefs_converge_without_clobbering_user_choice,
        test_readme_model_guidance_matches_the_shipped_config,
        test_every_defined_contract_is_actually_run,
        test_hermes_native_profile_migration_contract,
        test_same_version_forge_hotfix_refreshes_shipped_content,
        test_forge_source_is_complete_and_buildable,
        test_offline_manifest_complete,
        test_capability_profiles_are_not_registered_globally,
        test_project_scope_is_implemented_not_just_declared,
        test_upgrading_moves_a_globally_registered_profile,
        test_docs_do_not_contradict_the_profile_scope,
        test_no_shipped_config_carries_a_maintainer_path,
        test_bundle_stays_free_and_accountless,
        test_visual_verification_ships_its_own_falsifiable_check,
        test_always_on_core_is_three_servers_and_says_why,
        test_blender_is_pinned_and_discovered,
        test_profile_package_pins_follow_the_component_catalog,
        test_extras_never_overwrite_a_skill_the_bundle_vendors,
        test_mcp_config_writing_has_exactly_one_implementation,
        test_npx_pin_reaches_machines_that_already_have_the_entry,
        test_manifest_generator_excludes_developer_state,
        test_release_builder_contract,
        test_current_forge_docs_contract,
        test_ps51_utf8_reads_are_explicit,
        test_windows_ci_and_ps51_static_contract,
        test_batch_launchers_drop_incompatible_powershell_module_roots,
        test_pack_gate_does_not_write_persistent_environment,
        test_v8_active_surface_uses_versionless_names,
        test_hermes_mcp_registration_is_noninteractive_and_bounded,
        test_linux_helpers_keep_their_execute_bit,
        test_version_sources,
        test_forge_install_directory_is_never_version_stamped,
        test_forge_health_check_reads_fields_forge_emits,
        test_no_skill_documents_an_unshipped_product,
        test_no_skill_script_hardcodes_a_machine_path,
        test_every_v5_helper_called_actually_exists,
        test_provider_skill_sync_is_content_authoritative,
        test_codex_plugins_use_the_official_lifecycle,
        test_hermes_legacy_openrouter_extra_is_migrated_without_replacing_config,
        test_hermes_stale_session_provider_migration,
        test_hermes_openrouter_picker_uses_the_live_tool_catalog,
        test_hermes_receives_the_combined_soul_and_aio_contract,
        test_bundle_forge_install_has_single_skill_writer,
        test_forge_skill_has_one_canonical_source,
        test_forge_install_checked_commands_are_quiet_but_diagnostic,
        test_local_launcher_failure_is_persistent_and_diagnosable,
        test_hermes_forge_probe_bypasses_cli_startup_and_hook_prompts,
        test_double_click_launcher_keeps_success_visible,
        test_grok_forge_wiring_does_not_warn_before_bundled_forge_install,
        test_aio_prompt_cache_ci_and_game_profile_contract,
        # v8.6.0 -- local inference, free web search, and shell-output compression.
        test_no_shipped_text_file_carries_a_stray_control_character,
        test_local_model_ops_carries_what_actually_blocks_a_local_run,
        test_rtk_catalog_entry_keeps_its_windows_caveat,
        test_rtk_safe_hook_is_default_narrow_and_self_testing,
        test_migrator_converges_plugins_additively_and_proves_the_payload,
        test_doctor_reports_unreachable_plugins_and_unconsented_hooks,
        test_readme_does_not_promise_a_web_backend_the_pack_never_installs,
        # v8.6.2 -- the Codex skills index, counted instead of inferred.
        test_codex_index_is_measured_not_inferred_from_the_plugin_cache,
        test_codex_plugin_detection_survives_one_broken_marketplace,
        test_subset_install_keeps_the_other_providers_native_plugin_records,
        # v8.6.2 -- boot-time autostarts, reported but never ours to delete.
        test_dead_autostarts_are_reported_and_never_deleted,
        # v8.6.7 -- Codex ships skills of its own; adopting one by the same
        # name indexed it twice on Codex alone.
        test_codex_builtin_skills_are_discovered_not_hardcoded,
        # v8.6.9 -- a correct preset over four unloadable saved model configs.
        test_lmstudio_optimizer_writes_the_settings_that_actually_fit,
        # v8.6.11 -- the same three bytes that broke START-HERE.bat twice.
        test_no_shipped_json_carries_a_byte_order_mark,
        test_rtk_is_documented_as_a_git_tool_not_a_general_filter,
        # v8.6.12 -- instructions outliving the tools they name.
        test_doctor_reports_hooks_that_steer_at_unregistered_mcps,
        test_doctor_reports_pack_tools_shadowed_by_another_copy,
        test_retired_marketplaces_are_unregistered_not_just_undeployed,
        test_always_on_mcp_pins_come_from_the_catalog,
        test_manifest_covers_every_tracked_file,
        test_a_running_mcp_binary_cannot_fail_the_whole_install,
        test_an_unenabled_profile_is_never_reported_as_a_missing_tool,
        test_every_canonical_skill_reached_every_provider_tree,
        test_profile_detection_sees_a_workspace_of_projects,
        test_a_machine_controlling_server_is_never_swept_by_calling_its_tools,
        test_desktop_control_can_never_be_switched_on_by_detection,
        test_the_schema_cost_tool_does_not_send_a_byte_order_mark,
        test_mcp_proofs_do_not_require_a_python_path_alias,
        test_versioned_online_tools_pin_the_same_version_offline,
        test_github_auth_guidance_matches_the_official_oauth_binary,
        test_fresh_codex_home_exists_before_instruction_copy,
        test_profile_repair_and_frontend_detection_are_default,
        test_new_creative_skills_are_pinned_and_single_writer,
        test_skill_discovery_is_search_only,
        test_outdated_hermes_npm_duplicates_are_removed_only_after_current_install,
        test_local_security_boundaries_stay_hardened,
        test_catalog_freshness_auditor_self_checks,
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
        if prof.get("scope") == "global":
            # One profile is allowed to be machine-wide, on terms that make it
            # impossible to enable by accident: `reasoning` is a way of thinking
            # rather than a property of a project, so a project scope would be
            # meaningless. It must declare NO detection markers, so -Auto can
            # never turn it on, and it must say why it costs what it costs.
            detect = prof.get("detect") or {}
            assert not detect.get("files") and not detect.get("globs"), (
                f"profile {prof['id']} is machine-wide AND auto-detected. "
                "That combination registers a server on every session from a "
                "marker in one project."
            )
            assert prof.get("why"), f"global profile {prof['id']} does not justify itself"
            continue
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

    7.9.5 carried one -- `Get-UabsProfileScope` existed and the only thing the
    writer did with the answer was swap Claude's config path. Every other
    provider got the machine-wide file whatever the field said, which is how
    "project-scoped" came to mean "global, with a comment".
    """
    writer = read(ROOT / "TOOLS" / "UABS-Mcp-Write.ps1")
    front = read(ROOT / "TOOLS" / "Set-McpProfile.ps1")

    for func in ("Get-UabsProviderProjectTarget", "Get-UabsProviderNoProjectScope",
                 "Get-UabsJsonScopeContainer", "Test-UabsServerIsProjectBound",
                 "Test-UabsServerDeclared"):
        assert f"function {func}" in writer, f"{func} missing from the shared writer"

    assert "Get-UabsProviderProjectTarget" in front, (
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

    # Test-Path raises "Cannot find drive" for a path on an unmounted drive
    # rather than answering False, and every script here runs with
    # $ErrorActionPreference = 'Stop'. The tools on the development machine live
    # on S: and its projects on Z:; neither is guaranteed to be mounted.
    assert "function Test-UabsPath" in writer, "paths are tested without a guard for an unmounted drive"
    for rel in ("TOOLS/UABS-Mcp-Write.ps1", "TOOLS/Set-McpProfile.ps1", "TOOLS/Test-McpHandshake.ps1"):
        body = read(ROOT / rel)
        for i, line in enumerate(body.splitlines(), 1):
            if "Test-Path -LiteralPath" in line and "-ErrorAction SilentlyContinue" not in line:
                raise AssertionError(f"{rel}:{i} tests a path without the unmounted-drive guard: {line.strip()}")

    # Join-Path asks the provider to resolve the drive, so it raises the same
    # error for a base that is not mounted -- in a function whose whole job is
    # string concatenation.
    assert "function Join-UabsPath" in writer, "paths are joined without the unmounted-drive guard"
    for rel in ("TOOLS/UABS-Mcp-Write.ps1", "TOOLS/Set-McpProfile.ps1", "TOOLS/Test-McpHandshake.ps1"):
        body = read(ROOT / rel)
        for i, line in enumerate(body.splitlines(), 1):
            if "Join-Path " not in line or line.lstrip().startswith("#"):
                continue
            # The one legitimate use: sourcing the file the helper lives in.
            if "UABS-Mcp-Write.ps1" in line:
                continue
            raise AssertionError(f"{rel}:{i} joins a path without the unmounted-drive guard: {line.strip()}")

    # A diagnostic that reads only the machine-wide config cannot see the
    # servers this release moved, and reports a cost no real session pays.
    probe = read(ROOT / "TOOLS" / "Test-McpHandshake.ps1")
    assert "[string]$Path," in probe, "the handshake probe cannot be pointed at a project"
    assert "Get-UabsProviderProjectTarget" in probe, (
        "the handshake probe does not read project-scoped servers"
    )

    # GetFolderPath returns the empty string for a folder that does not exist.
    # Join-Path on that throws and takes the run down inside a helper whose only
    # job is to answer "is Claude Desktop installed".
    assert "function Get-UabsAppDataRoot" in writer, (
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
    assert "UabsProfileAliases" in front, "the old profile id no longer resolves"
    assert "'code-deep' = 'code-intel'" in front, "code-deep does not map to code-intel"
    assert "function Convert-UabsProfileState" in front, "there is no state migration"
    assert "function Invoke-UabsStaleGlobalMigration" in front, (
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
    for prof in profiles["profiles"]:
        scope = prof.get("scope")
        assert scope in ("project", "global"), f"{prof['id']} declares scope {scope!r}"
        if scope == "global":
            # Allowed for `reasoning` alone, and only because it can never be
            # auto-enabled: no detection markers means -Auto cannot reach it.
            detect = prof.get("detect") or {}
            assert not detect.get("files") and not detect.get("globs")

    for comp in catalog["components"]:
        if not comp.get("profile"):
            continue
        assert comp.get("auto_register") is False, (
            f"{comp['id']} carries a profile and is still auto-registered"
        )
        note = comp.get("scope_note") or ""
        assert note, f"{comp['id']} carries a profile with no scope_note"

    declared = {p["id"] for p in profiles["profiles"]}
    profile_servers = {p["id"]: {s["id"] for s in p["servers"]} for p in profiles["profiles"]}
    for comp in catalog["components"]:
        if comp.get("profile"):
            assert comp["profile"] in declared, (
                f"{comp['id']} names profile {comp['profile']}, which PROFILES.json does not declare"
            )
            server_id = comp.get("server_id") or comp["id"]
            aliases = {server_id, re.sub(r"-mcp$", "", server_id)}
            assert aliases & profile_servers[comp["profile"]], (
                f"{comp['id']} says it belongs to {comp['profile']}, but server {server_id} is wired elsewhere"
            )

    skill = read(ROOT / "_CANONICAL-SKILLS" / "capability-profiles" / "SKILL.md")
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
    writer = ROOT / "TOOLS" / "UABS-Mcp-Write.ps1"
    assert writer.is_file(), "shared MCP writer missing"
    body = read(writer)
    for func in ("Add-UabsMcpJson", "Add-UabsMcpToml", "Add-UabsMcpHermes",
                 "Remove-UabsMcpJson", "Remove-UabsMcpToml", "Remove-UabsMcpHermes"):
        assert f"function {func}" in body, f"{func} missing from the shared writer"

    for rel in ("TOOLS/Add-Reasoning-MCPs.ps1", "TOOLS/Set-McpProfile.ps1"):
        text = read(ROOT / rel)
        assert "UABS-Mcp-Write.ps1" in text, f"{rel} does not dot-source the shared writer"
        assert "function Add-ToJsonMcp" not in text, f"{rel} kept a private JSON writer"

    # PowerShell unrolls a pipeline on `return`, so a one-argument server came
    # back as a bare string and was written as "args": "blender-mcp".
    assert "return ,@(" in body, "argument resolution can unroll a single-element array again"

    gate = ROOT / "TESTS" / "Test-McpProfiles.ps1"
    assert gate.is_file(), "TESTS/Test-McpProfiles.ps1 missing"
    assert "Test-McpProfiles.ps1" in read(ROOT / "TESTS" / "Test-Pack.ps1"), (
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
    common = read(ROOT / "TOOLS" / "UABS-Common.ps1")
    assert "$argNorm" in common, "Update-UabsGrokMcpBlock no longer normalises args for comparison"
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
    aio = read(ROOT / "INSTALL-AIO.ps1")
    assert "_CANONICAL-SKILLS" in aio, "the installer no longer knows what canonical owns"
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


# --------------------------------------------------------------------------
# v7.9.8 -- the starter template is not a place to register MCP servers.
#
# Through 7.9.7 the Hermes starter carried five live servers and the pack gate
# passed. Because Install-Provider-Starter-Settings.ps1 copies the file whole
# onto a machine with no config.yaml, each was a fresh-install default that
# outranked the bundle's own decisions.
# --------------------------------------------------------------------------

STARTER_GLOB = "1-TAILORED-PROVIDER-TREES/*/COPY-TO-PROVIDER-HOME/*"


def _starter_templates():
    return sorted(ROOT.glob(STARTER_GLOB))


def config_code(path: Path) -> str:
    """A config template with its comments removed.

    Same reasoning as ps_code: the comment explaining why a package is banned
    names that package, and a gate that cannot tell code from commentary either
    fails on the explanation or forces the explanation to be deleted.
    """
    text = read(path)
    if path.suffix.lower() in (".json", ".md"):
        return text
    out = []
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        out.append(line)
    return "\n".join(out)


def test_starter_templates_declare_no_mcp_servers() -> None:
    shapes = {
        "YAML mcp_servers mapping": re.compile(r"(?m)^[ \t]*mcp_servers:[ \t]*\r?\n[ \t]+\S"),
        "TOML mcp_servers table": re.compile(r"(?m)^[ \t]*\[[ \t]*mcp[_.]servers\."),
        "JSON mcpServers object": re.compile(r'(?m)"mcpServers"[ \t]*:[ \t]*\{[ \t\r\n]*"'),
    }
    bad = []
    for p in _starter_templates():
        code = config_code(p)
        for label, rx in shapes.items():
            if rx.search(code):
                bad.append(f"{p.relative_to(ROOT).as_posix()} ({label})")
    assert not bad, (
        "starter templates declare live MCP servers; MCP is wired by the "
        "installer and Set-McpProfile from what is installed: " + ", ".join(bad)
    )


def test_no_unpinned_package_in_live_templates() -> None:
    """An unpinned server can change its tool surface mid-session.

    npx will also happily reuse a broken cache. The catalog pins everything it
    owns; 7.9.7's Hermes starter shipped @playwright/mcp@latest anyway.
    """
    bad = [
        p.relative_to(ROOT).as_posix()
        for p in _starter_templates()
        if "@latest" in config_code(p)
    ]
    assert not bad, "unpinned @latest package in a live provider template: " + ", ".join(bad)


def test_retired_github_package_cannot_become_live_config() -> None:
    """npm reports @modelcontextprotocol/server-github as no longer supported.

    v7.7.11 'fixed' it by pinning; the pin held and the package died anyway.
    The official server replaced it -- and 7.9.7 still shipped the dead one in
    the Hermes starter, where a fresh install would load it.
    """
    retired = "@modelcontextprotocol/server-github"
    bad = [
        p.relative_to(ROOT).as_posix()
        for p in _starter_templates()
        if retired in config_code(p)
    ]
    assert not bad, f"retired package {retired} in a live provider template: " + ", ".join(bad)
    for path in (
        ROOT / "TOOLS" / "MCP-CONFIG-EXAMPLES.toml.txt",
        CANON / "mcp-server-diagnostics" / "references" / "provider-cli-ops.md",
    ):
        assert retired not in read(path), f"retired GitHub npm server is still recommended by {path}"
    toolbelt = ps_code(ROOT / "TOOLS" / "Build-Toolbelt.ps1")
    assert "Test-UabsGrokInheritsClaudeMcp" in toolbelt, (
        "the toolbelt reports Claude MCPs as active in Grok even when the bundle disables that import"
    )


def test_hermes_readme_matches_the_shipped_starter() -> None:
    """Cross-source contract: docs that describe executable config must be true.

    The 7.9.7 Hermes README said 'Empty mcp_servers' while the starter shipped
    five, and said reasoning=high / max_turns=350 / 250K compression while the
    file said max / null / 120000. Four false claims, no test watching.
    """
    readme = read(ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "README.txt")
    cfg = read(ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "COPY-TO-PROVIDER-HOME" / "config.yaml")

    assert "mcp_servers: {}" in cfg, "the Hermes starter no longer has an empty mcp_servers"
    assert "mcp_servers: {}" in readme, "the Hermes README no longer states the empty mcp_servers"

    # Each claim in the README that names a config value must match the file.
    for key, claim in (
        ("reasoning_effort", "reasoning_effort: max"),
        ("max_turns", "max_turns: null"),
        ("threshold_tokens", "threshold_tokens: 160000"),
    ):
        assert claim in cfg, f"starter no longer sets {claim!r}"
        value = claim.split(": ", 1)[1]
        assert value in readme, (
            f"Hermes README does not state the shipped {key} ({value}); "
            "a README that describes executable config has to track it"
        )


def test_both_hermes_config_copies_agree() -> None:
    """The tree ships the starter twice; a fix to one is a bug in the other."""
    a = read(ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "config.yaml")
    b = read(ROOT / "1-TAILORED-PROVIDER-TREES" / "Hermes" / "COPY-TO-PROVIDER-HOME" / "config.yaml")
    assert a == b, "the two shipped Hermes config.yaml copies have diverged"
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    schema = catalog.get("provider_config_schemas", {}).get("Hermes")
    assert schema and f"_config_version: {schema}" in a, (
        "the Hermes starter schema drifted from CATALOG.json; a fresh install "
        "would immediately need a runtime migration"
    )


def test_starter_installer_refuses_the_shape_not_the_symptoms() -> None:
    """The guard has to live in the installer, not only in this suite.

    A contract catches it in CI; the installer catches it on a user's machine
    when someone drops a live config into the folder.
    """
    code = ps_code(ROOT / "TOOLS" / "Install-Provider-Starter-Settings.ps1")
    assert "mcp_servers" in code and "mcpServers" in code, (
        "Install-Provider-Starter-Settings no longer refuses templates with live MCP entries"
    )
    assert "@latest" in code, "the starter installer no longer refuses unpinned packages"


def test_capability_routing_owns_tool_selection() -> None:
    """One skill owns 'do not rebuild an installed capability with a weaker script'.

    Added in 7.9.8 only after auditing capability-profiles, tool-discovery,
    ai-tooling-stack, research-verification, tool-output-awareness and
    assumption-audit. The nearest owner, capability-profiles, triggers on
    enabling servers -- a model about to write a crawler does not match that
    description, and description routing is how these skills load at all.
    """
    p = CANON / "capability-routing" / "SKILL.md"
    assert p.is_file(), "capability-routing skill is missing"
    text = read(p)
    lower = text.lower()

    for cue in ("crawler", "parser", "browser", "shell/python/node", "failed twice"):
        assert cue in read(p).split("---")[1].lower(), (
            f"capability-routing description does not trigger on {cue!r}; "
            "it has to fire when an ad-hoc implementation is about to be written"
        )

    assert "hard part" in lower, "capability-routing lost its central question"
    assert "escalate" in lower, "capability-routing lost the escalation ladder"
    # The anti-dogma half matters as much as the routing half.
    assert "primitive" in lower and (
        "not a browser stack" in lower or "not code-intel" in lower
    ), "capability-routing does not say when the plain primitive wins"
    # The point is that the decision cites a REPRODUCIBLE source, not which one.
    # Naming a single tool made this fail when the skill switched to citing the
    # generated capability record -- a better source, not a missing one.
    cites = ("measure-mcpschemacost", "capability-records", "measure_mcp_capability",
             "36,321", "36,337")
    assert any(c in lower for c in cites), (
        "capability-routing states a routing decision without naming the measurement "
        "behind it (expected one of: %s)" % ", ".join(cites)
    )


def test_every_version_gate_accepts_the_shipped_version() -> None:
    """A version format is agreed by every gate that reads it, or by none.

    v7.9.8.5 was the first four-part version. check_versions.py and
    test_version_sources were widened for it; TOOLS/Test-Installed-State.ps1 was
    not, so the installed-state doctor failed the release that shipped it -- on
    a correct tree, after a clean install. Three gates, two of them updated.

    This asserts the actual VERSION.txt satisfies every gate's own pattern,
    whatever shape a future release picks.
    """
    bare = BARE
    # 1. The doctor's PowerShell guard.
    doctor = read(ROOT / "TOOLS" / "Test-Installed-State.ps1")
    m = re.search(r"if \(\$packBare -notmatch '([^']+)'\)", doctor)
    assert m, "the doctor no longer validates VERSION.txt at all"
    pattern = m.group(1).replace(r"\d", "[0-9]")
    assert re.match(pattern, bare), (
        f"the installed-state doctor rejects the shipped version {bare!r} "
        f"(pattern {m.group(1)!r}) -- it would fail a correct install"
    )
    # 2. The CI version checker -- run it, rather than pattern-match its source.
    #    The first version of this collected regexes with findall, never used
    #    them, and asserted a hardcoded pattern against BARE. Narrowing
    #    check_versions.py back to three parts made the findall return nothing,
    #    the loop body never ran, and the test passed: it failed open on the one
    #    regression it existed to catch.
    checker = ROOT / ".github" / "scripts" / "check_versions.py"
    assert checker.is_file(), "the CI version checker is missing"
    proc = subprocess.run([sys.executable, str(checker)], capture_output=True,
                          text=True, cwd=str(ROOT))
    assert proc.returncode == 0, (
        "check_versions.py rejects the shipped version %s:\n%s"
        % (bare, (proc.stdout + proc.stderr)[-600:])
    )
    # 3. Nothing may re-introduce a hard three-part assertion on the version.
    #    Matched as executable code, not as text: the first cut of this check
    #    searched for the literal and found its own guard string.
    contracts = read(Path(__file__))
    reintroduced = re.search(r"^\s*assert\s+BARE\.count\(", contracts, re.M)
    assert not reintroduced, (
        "a strict three-part version assertion is back; four-part releases exist"
    )


def test_capability_claims_match_the_measured_record() -> None:
    """A keyless claim in the catalog must match what the tools actually did.

    Through 7.9.8 the firecrawl entry read "scrape/search/interact work on the
    keyless hosted tier; crawl/map/agent/extract need a key". Two of those five
    claims were false -- interact answers "Unauthorized: API key is required",
    and extract is not key-gated but deprecated. Nobody had called the tools.

    The record is generated by TOOLS/measure_mcp_capability.py; this keeps the
    human-readable catalog honest about it.
    """
    records = ROOT / "BUNDLED-TOOLS" / "capability-records"
    assert records.is_dir(), "capability-records/ is missing"
    generator = ROOT / "TOOLS" / "measure_mcp_capability.py"
    assert generator.is_file(), "the capability-record generator is missing"

    gen = read(generator)
    # Assert the order the BRANCHES run in, not the order two constants happen
    # to be defined in. The first version of this check compared
    # gen.index("THROTTLE_MARKERS") < gen.index("AUTH_MARKERS = ") and then
    # wrote `or True` after it -- which is how it stayed green while being
    # false, and it would have passed either way if the branches were swapped.
    try:
        i_gone = gen.index('record["deprecated"].append')
        i_throttle = gen.index('record["rate_limited"].append')
        i_auth = gen.index('record["needs_key"].append')
        i_keyless = gen.index('record["keyless"].append')
    except ValueError as exc:
        raise AssertionError("the generator's classification buckets are gone: %s" % exc)
    assert i_throttle < i_auth, (
        "throttling is classified after auth: a rate-limited keyless tool would be "
        "recorded as needing a key. Firecrawl's daily-limit message recommends OAuth, "
        "which is exactly how a correct measurement got contradicted during 7.9.9."
    )
    assert i_gone < i_auth, "a deprecated tool would be reported as needing a key"
    assert i_keyless > i_auth, (
        "the keyless branch runs before the marker chain: a server that reports "
        "'Unauthorized' as plain text without isError would have every tool filed "
        "as keyless"
    )
    assert "unverified" in gen, "the generator no longer separates unverified from keyless"
    # A measurement tool must not be able to authenticate as the user.
    assert re.search(r"os\.environ\.items\(\)\s+if\s+k\.upper\(\)\s+in\s+ENV_ALLOW", gen), (
        "the generator no longer builds the child environment from an allowlist; "
        "a credential blacklist lets every unlisted token through to synthesized "
        "tool calls -- against github-mcp-server that is create/merge/delete"
    )
    assert "MUTATING_HINTS" in gen, (
        "the generator no longer skips state-changing tools; 'measure what this "
        "server can do' must not mean 'find out by doing it'"
    )

    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    entries = {c.get("id"): c for c in catalog.get("components", []) if isinstance(c, dict)}

    for record_path in sorted(records.glob("*.json")):
        record = json.loads(read(record_path))
        # The directory holds more than one record shape: keyless-capability
        # records from measure_mcp_capability.py carry "component", while
        # schema-cost records from Measure-McpSchemaCost.ps1 describe several
        # servers at once and have no single component. Select by shape rather
        # than assuming every file in the folder answers the same question.
        cid = record.get("component")
        if cid is None:
            assert record.get("record"), (
                f"{record_path.name}: neither a capability record (no 'component') "
                "nor a typed record (no 'record'); an untyped file here will be "
                "read as whichever shape the next reader assumes"
            )
            continue
        entry = entries.get(cid)
        if entry is None:
            continue
        claimed = entry.get("keyless_tools")
        assert claimed is not None, f"{cid}: catalog states no keyless_tools but a measured record exists"
        # keyless_capable, not keyless: a tool that answers "free daily limit
        # reached" was reached WITHOUT credentials, so being throttled proves
        # keyless access rather than disproving it. Comparing against `keyless`
        # alone made this contract depend on whether the sweep happened to run
        # inside a spent quota window.
        capable = record.get("keyless_capable")
        assert capable is not None, (
            f"{cid}: the record predates keyless_capable -- regenerate with "
            "TOOLS/measure_mcp_capability.py"
        )
        assert sorted(claimed) == sorted(capable), (
            f"{cid}: catalog keyless_tools {sorted(claimed)} disagree with the measured "
            f"record {sorted(capable)} -- regenerate with TOOLS/measure_mcp_capability.py"
        )
        # The record must be generator-shaped, or a hand-written file can satisfy
        # both sides of its own consistency check.
        assert record.get("provenance"), (
            f"{cid}: record carries no provenance line; it may have been written by hand"
        )
        # A tool the record proves needs a key must never be advertised as keyless.
        overlap = set(claimed) & set(record["needs_key"])
        assert not overlap, f"{cid}: catalog calls these keyless but they demand a key: {sorted(overlap)}"


def test_optional_key_server_is_not_registered_for_a_sliver_of_itself() -> None:
    """Installed is not registered, and -WithExtras must not conflate them.

    Through 7.9.8, -WithExtras registered firecrawl-mcp on a machine with no
    key, announcing it in one line. Measured, that bought 2 usable tools out of
    25 for ~9,080 tokens on every turn -- and those two duplicate the native web
    tools every provider already has. It is an npx server, so registering IS
    installing and nothing is cached either way; the entry waits for the key.
    """
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    entries = {c.get("id"): c for c in catalog.get("components", []) if isinstance(c, dict)}
    fc = entries.get("firecrawl-mcp")
    assert fc, "firecrawl-mcp left the catalog"
    assert fc.get("keyless_registration") == "skip", (
        "firecrawl-mcp would be registered keyless again; measured keyless surface is "
        "2 of 25 tools at ~9,080 tokens/turn"
    )
    assert fc.get("keyless_skip_reason"), "the skip has no stated reason, so a user cannot judge it"

    aio = ps_code(ROOT / "INSTALL-AIO.ps1")
    assert "RegisterKeylessExtras" in aio, "no explicit override for keyless registration"
    assert "keyless_registration" in aio, "the installer ignores the catalog's keyless_registration"
    assert "not-registered-no-key" in aio, (
        "the installer no longer records not-registered-without-a-key as its own state"
    )
    assert "installed-not-registered" not in aio, (
        "the installer claims the package is installed; mcp-npx installs nothing "
        "until npx resolves it on first launch, so registering IS installing"
    )


def test_full_default_owns_optional_servers_and_coreonly_opts_out() -> None:
    """V8 installs the full catalog by default; -CoreOnly is the opt-out.

    It did not, for Hermes: playwright and firecrawl were documented as extras
    and shipped enabled in the starter, so a default install got them anyway.
    Worse, the starter called it `playwright` while extras adds
    `playwright-mcp`, so a `-WithExtras` run produced two entries for one
    package -- the duplicate that Find-UabsServerByPackage exists to work around.

    The default side is guaranteed by test_starter_templates_declare_no_mcp_servers.
    This is the other half: the extras list must still own them.
    """
    aio = read(ROOT / "INSTALL-AIO.ps1")
    block = re.search(r"if \(-not \$CoreOnly\) \{(.*?)\}", aio, re.S)
    assert block, "the V8 full-default component block is gone"
    for comp in ("playwright-mcp", "firecrawl-mcp"):
        assert comp in block.group(1), f"{comp} is no longer owned by the full-default block"


def test_schema_cost_is_measurable_not_just_asserted() -> None:
    """7.9.7 demoted a server on a byte count it shipped no way to reproduce."""
    p = ROOT / "TOOLS" / "Measure-McpSchemaCost.ps1"
    assert p.is_file(), "TOOLS/Measure-McpSchemaCost.ps1 is missing"
    code = ps_code(p)
    assert "tools/list" in code and "initialize" in code, (
        "the schema-cost tool no longer speaks real MCP"
    )
    assert "GetByteCount" in code, "the schema-cost tool no longer measures bytes"


def test_no_shipped_text_file_carries_a_stray_control_character() -> None:
    """A doubled backslash that collapsed one level too many.

    Authoring files through a shell heredoc into Python during v8.6.0 turned
    ``\\venv`` into a vertical tab and ``\\rtk`` into a carriage return -- twice,
    in two separate files, silently. Both read correctly in a diff, because the
    corrupted byte is invisible. One of them was a command a user would paste.

    Nothing in this pack legitimately ships a control character other than tab
    and the line ending, so the whole shipped text tree is scanned for the rest.
    """
    exts = {".md", ".txt", ".json", ".ps1", ".py", ".psm1", ".yaml", ".yml", ".bat"}
    roots = [
        ROOT / "_CANONICAL-SKILLS",
        ROOT / "TOOLS",
        ROOT / "TESTS",
        ROOT / "1-TAILORED-PROVIDER-TREES",
        ROOT / "BUNDLED-TOOLS" / "CATALOG.json",
        ROOT / "README.md",
        ROOT / "CHANGELOG.md",
    ]
    offenders = []
    for root in roots:
        paths = [root] if root.is_file() else sorted(root.rglob("*"))
        for path in paths:
            if not path.is_file() or path.suffix.lower() not in exts:
                continue
            try:
                # newline="" is load-bearing: text mode translates a lone
                # CR into LF, which is precisely the corruption being hunted.
                with io.open(path, encoding="utf-8", newline="") as handle:
                    text = handle.read()
            except (UnicodeDecodeError, OSError):
                continue
            for index, char in enumerate(text):
                if ord(char) >= 32 or char in "\n\t":
                    continue
                # A carriage return is only ever legitimate as half of CRLF.
                if char == "\r" and text[index + 1:index + 2] == "\n":
                    continue
                rel = path.relative_to(ROOT).as_posix()
                offenders.append("%s: %r at offset %d" % (rel, char, index))
                break
    assert not offenders, "control characters in shipped text: " + "; ".join(offenders[:5])


def test_local_model_ops_carries_what_actually_blocks_a_local_run() -> None:
    """The skill exists to stop one specific wasted afternoon.

    Hermes refuses a model whose context window is under 64,000 tokens and
    raises before the first turn. LM Studio's saved default is commonly 32K,
    so the obvious setup fails at startup with no hint that the loader, not
    the config, is what has to change. A skill that omits that number is
    prose.
    """
    skill = ROOT / "_CANONICAL-SKILLS" / "local-model-ops" / "SKILL.md"
    assert skill.is_file(), "_CANONICAL-SKILLS/local-model-ops/SKILL.md is missing"
    body = read(skill)

    assert "64,000" in body or "64000" in body, (
        "local-model-ops no longer states the context floor that blocks a local run"
    )
    # The floor is the rule; 65,536 is the number a reader has to type. Stating
    # only "64,000" invites setting exactly 64,000 against a strict < comparison,
    # or 32,768 because it is the nearest power of two below it.
    assert "65,536" in body or "65536" in body, (
        "local-model-ops states the floor but not the setting that clears it"
    )
    assert "65,536" in read(ROOT / "README.md") or "65536" in read(ROOT / "README.md"), (
        "the README states the floor but never the value to set"
    )
    for key in ("model_aliases", "provider: lmstudio", "base_url"):
        assert key in body, "local-model-ops lost the alias schema element %r" % key
    # The placeholder-key fact is what stops someone pasting a real secret into
    # a config block that reaches a server with no authentication at all.
    assert "lmstudio" in body and "key" in body.lower(), (
        "local-model-ops no longer explains that lmstudio needs no credential"
    )
    assert "keyless" in body.lower() or "free" in body.lower(), (
        "local-model-ops no longer covers how a local model reaches the web"
    )

    # Two front-ends, one server, incompatible expectations: SillyTavern runs
    # fine at 32K while Hermes refuses it, and SillyTavern fails in two ways
    # that read as a dead connection instead of a setting.
    st = skill.parent / "references" / "sillytavern.md"
    assert st.is_file(), "local-model-ops lost its SillyTavern reference"
    st_body = read(st)
    assert "!apiKey" in st_body, (
        "the SillyTavern reference no longer shows the guard that empties the model list"
    )
    assert "reasoning" in st_body.lower(), (
        "the SillyTavern reference no longer warns that a small response budget "
        "returns an empty message from a reasoning model"
    )

    ref = skill.parent / "references" / "gguf-metadata.md"
    assert ref.is_file(), "local-model-ops lost its GGUF sizing reference"
    ref_body = read(ref)
    assert "head_count_kv" in ref_body and "block_count" in ref_body, (
        "the sizing reference no longer names the fields the KV budget depends on"
    )


def test_rtk_catalog_entry_keeps_its_windows_caveat() -> None:
    """The measured hook policy must win over mechanically valid setup syntax."""
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    entry = [c for c in catalog["components"] if c.get("id") == "rtk"]
    assert entry, "CATALOG.json no longer lists rtk"
    rtk = entry[0]

    assert rtk.get("kind") == "cli-optional", (
        "rtk is catalogued as %r; a CLI is the entire reason it costs no standing "
        "tokens, and any MCP-shaped kind would be a different tool" % rtk.get("kind")
    )
    assert rtk.get("license") == "Apache-2.0", "rtk license claim changed"

    note = rtk.get("scope_note", "")
    assert "hermes" in note.lower(), "the rtk note no longer names the one working integration"
    assert "windows" in note.lower(), "the rtk note lost its native-Windows caveat"
    assert "curl" in note, "the rtk note no longer pins the curl exclusion"
    assert rtk.get("hook_policy") == "off", (
        "rtk's measured rewrite table includes wrong-answer and mutating paths; "
        "the catalog must keep the broad upstream hook off"
    )
    safe = rtk.get("safe_hook_policy") or {}
    assert safe.get("enabled") is True and safe.get("broad_upstream_hook") is False, (
        "the catalog no longer distinguishes the bundle allowlist from RTK's "
        "broad upstream hook"
    )
    discouraged = (rtk.get("discouraged_provider_plugins") or {}).get("Hermes") or []
    assert "rtk-rewrite" in discouraged, (
        "the Hermes plugin that drives the same rewrite table is no longer tied "
        "to the catalog's off policy"
    )

    readme = read(ROOT / "README.md")
    live = readme.split("### rtk:", 1)[1].split("### claude-mem", 1)[0]
    assert "rtk init" not in live, (
        "the live README still gives a copy-paste hook command even though the "
        "catalog's measured policy is off"
    )
    for command in ("rtk git status", "rtk err <command>", "rtk test <test command>"):
        assert command in live, f"the README lost the deliberate-use example {command!r}"
    assert "rtk-rewrite" in live and "recommends neither" in live, (
        "the README no longer explains that the Hermes plugin is the same bad rewrite path"
    )
    assert "rtk gain" in live, (
        "the README no longer says how to verify rtk is running -- an agent reports "
        "the command it asked for, not the rewritten one, so self-report proves nothing"
    )
    installer = read(ROOT / "INSTALL-AIO.ps1")
    assert "rtk init" not in installer, (
        "the installer still prints provider init commands that contradict the catalog policy"
    )
    doctor = read(ROOT / "TOOLS" / "Test-Installed-State.ps1")
    assert "discouraged_provider_plugins" in doctor and "hermes_discouraged_plugin_issues" in doctor, (
        "the installed-state doctor cannot report the known-bad Hermes integration"
    )
    # The measured numbers must stay pinned. `HEAD~3` moves with every commit:
    # the 97% this table once advertised measures 82.5% today, and a claim that
    # decays silently is worse than no claim.
    #
    # Scoped to the LIVE rtk section. The release history further down quotes
    # the old figure while describing the release that made it, which is a
    # correct historical record, not a live claim.
    #
    # Narrowed to the measurement TABLE. The prose beside it names `HEAD~3`
    # deliberately, to say why the refs are pinned; banning the string outright
    # would delete the explanation along with the defect.
    assert "### rtk:" in readme, "the rtk section heading moved; this contract cannot find what it guards"
    rtk_section = readme.split("### rtk:", 1)[1].split("\n### ", 1)[0]
    rtk_rows = [ln for ln in rtk_section.splitlines() if ln.startswith("| `git")]
    assert rtk_rows, "the rtk measurement table is gone; the savings claim is now unsourced"
    assert not any("HEAD~" in ln for ln in rtk_rows), (
        "the rtk table measures against a MOVING git reference again; pin the refs "
        "or the number rots without anyone noticing (97%% became 82.5%% this way)"
    )
    assert "-g" in rtk_section, "the rtk section lost the global-install form"

    # Pinning the corpus is only half of it. `git log --stat -20` measured 95%
    # at rtk 0.45.0 and 0% at 0.46.0 -- the flag stopped being handled -- while
    # the other three rows reproduced to the byte across the same upgrade. A
    # measurement with no tool version on it cannot be re-checked, and rots
    # silently the next time the tool ships.
    #
    # Both assertions bind to the version CATALOG declares, and to the exact
    # phrase that stamps the measurement -- not to any mention of a version.
    # A looser check passed while the stamp was removed, because the paragraph
    # explaining the 0.45.0 -> 0.46.0 regression still named both versions.
    declared = rtk.get("version", "")
    assert declared, "CATALOG's rtk entry has no version field"
    assert ("**at rtk %s**" % declared) in rtk_section, (
        "the rtk table is not stamped '**at rtk %s**' -- the version CATALOG "
        "declares. `git log --stat -20` measured 95%% at 0.45.0 and 0%% at "
        "0.46.0, so a number with no tool version on it cannot be re-checked "
        "and rots the next time the tool ships." % declared
    )
    assert ("AT rtk %s" % declared) in note, (
        "CATALOG's rtk scope_note does not stamp its numbers 'AT rtk %s'" % declared
    )


def test_rtk_safe_hook_is_default_narrow_and_self_testing() -> None:
    """Default RTK must never mean enabling its broad rewrite table."""
    hook = ROOT / "TOOLS" / "hooks" / "rtk_safe_hook.py"
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    rtk_version = next(c["version"] for c in catalog["components"] if c.get("id") == "rtk")
    source = read(hook)
    assert f'EXPECTED_RTK_VERSION = "{rtk_version}"' in source, (
        "the safe hook is not pinned to the RTK rewrite table measured by CATALOG"
    )
    result = subprocess.run(
        [sys.executable, str(hook), "--selftest"],
        cwd=str(ROOT), capture_output=True, text=True, timeout=20,
    )
    assert result.returncode == 0 and "SELFTEST: PASS" in result.stdout, (
        "rtk_safe_hook.py rejected its allow/deny matrix:\n" +
        (result.stdout + result.stderr)
    )

    installer = read(ROOT / "INSTALL-AIO.ps1")
    default = re.search(r"\[string\[\]\]\$Components\s*=\s*@\((.*?)\),", installer, re.S)
    assert default and "'rtk'" in default.group(1), "rtk is no longer in the default install"
    assert "rtk init" not in installer, "the installer re-enabled RTK's broad upstream hook"

    wiring = read(ROOT / "TOOLS" / "Install-Completeness-Gate.ps1")
    assert "rtk_safe_hook.py" in wiring and "Stop = $false" in wiring, (
        "the narrow hook is missing or was accidentally wired as a Stop gate"
    )
    assert "--pre-only" in wiring and "--pre-only" in read(ROOT / "TOOLS" / "hooks" / "hermes_wire.py"), (
        "Hermes no longer keeps RTK routing out of pre_verify"
    )
    template = read(ROOT / "TOOLS" / "hooks" / "ultimate-bundle.json")
    assert "rtk_safe_hook.py" in template, "the shipped hook template lost safe RTK routing"

    preamble = read(ROOT / "0-UNRESTRAINT-PACKS" / "AIO-INSTRUCTION.md")
    for raw_surface in ("diff/show/log/find/search/read/curl/gh", "mutating Git", "machine-readable"):
        assert raw_surface in preamble, f"provider instructions no longer keep {raw_surface} raw"


def test_migrator_converges_plugins_additively_and_proves_the_payload() -> None:
    """`profile create --clone-from` copies the enabled list, not the payload.

    Measured on the maintainer's machine: two cloned profiles enabled ponytail
    and superpowers while having no plugins directory at all, so both had been
    inert since the day they were created. Nothing reported it -- an enabled
    plugin that cannot be resolved simply does nothing.

    Writing the list without checking reachability would recreate exactly that
    bug, so the migration has to do both.
    """
    code = ps_code(ROOT / "TOOLS" / "Migrate-HermesProfiles.ps1")

    assert "Get-UabsSharedPlugins" in code, "the migration no longer discovers installed plugins"
    assert "Ensure-UabsProfilePluginPayload" in code, (
        "the migration no longer ensures a profile can reach the plugin payload"
    )
    assert "LinkPlugins" in code and "New-Item -ItemType Junction" in code, (
        "the migration no longer links a profile's plugins directory to the shared root"
    )
    assert "cannot resolve its payload" in code, (
        "the migration writes plugins.enabled without proving the payload resolves -- "
        "that is the original bug"
    )
    assert "if name not in enabled" in code, (
        "the plugin write is no longer additive; it may now drop or reorder a user's own list"
    )
    assert "UabsDiscouragedPlugins" in code and "disable_plugins" in code, (
        "the migration does not consume catalog hook policy, so cloned profiles "
        "can retain a provider plugin the bundle has rejected"
    )
    assert 'plugins["disabled"] = disabled' in code and "did not disable catalog-rejected plugin" in code, (
        "the migration neither parks rejected plugins reversibly nor verifies the result"
    )
    assert "ConvertTo-UabsPlain ($json | ConvertFrom-Json) | ForEach-Object" not in code, (
        "a JSON plugin array is being cast as one object, which space-joins every "
        "name and makes enabled/disabled membership checks silently miss"
    )

    # Discovery must read the live default profile, never a list this pack
    # invents -- enabling a plugin the user does not have is the same failure
    # wearing different clothes.
    body = code[code.index("function Get-UabsSharedPlugins"):]
    body = body[:body.index("function Ensure-UabsProfilePluginPayload")]
    assert "Get-UabsProfilePrefs 'default'" in body, (
        "shared-plugin discovery no longer reads what the default profile actually runs"
    )
    assert "Test-Path" in body, "shared-plugin discovery no longer filters out missing payloads"


def test_doctor_reports_unreachable_plugins_and_unconsented_hooks() -> None:
    """Both failures report success from inside Hermes.

    An enabled-but-unreachable plugin loads nothing and says nothing. A shell
    hook that was never consented to is listed in config, passes every config
    check, and never fires -- `hermes hooks doctor` calls that out, but only if
    somebody thinks to run it. The pack's own doctor is where a user looks.
    """
    code = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")

    assert "payload is not reachable" in code, (
        "the doctor no longer reports plugins a profile cannot resolve"
    )
    assert "will NOT fire" in code, (
        "the doctor no longer reports shell hooks that were never consented to"
    )
    assert "hermes --accept-hooks" in code, (
        "the doctor reports unconsented hooks without giving the command that grants consent"
    )
    assert "Migrate-HermesProfiles.ps1 -Apply" in code, (
        "the doctor reports unreachable plugins without naming the fix"
    )
    assert "hermes_plugin_issues" in code and "hermes_hook_issues" in code, (
        "the doctor's JSON report no longer carries the new findings, so nothing "
        "downstream can read them"
    )


def test_readme_does_not_promise_a_web_backend_the_pack_never_installs() -> None:
    """ddgs is an optional dependency, not something the installer ships.

    Hermes carries the DuckDuckGo backend itself but gates it on the `ddgs`
    package being importable. Claiming it works out of the box would send a
    user to a backend that silently is not there, which is the same class of
    failure as an enabled plugin with no payload.
    """
    readme = read(ROOT / "README.md")
    assert "pip install ddgs" in readme, (
        "the README recommends the DuckDuckGo backend without the install step"
    )
    # The keyless ring is what actually works with no action at all; the README
    # must not tell people to pin a single backend and lose the rotation.
    assert "keyless" in readme.lower(), "the README no longer explains the free search ring"
    assert "web.search_backend" in readme, (
        "the README no longer names the key that pins a backend"
    )
    pin = readme[readme.index("web.search_backend"):][:400].lower()
    assert "only" in pin or "turns the rotation off" in pin, (
        "the README recommends pinning a backend without warning that it disables failover"
    )


def test_codex_index_is_measured_not_inferred_from_the_plugin_cache() -> None:
    """The old count walked plugins\\cache and was wrong by 122 entries.

    Codex indexes only the plugins config.toml ENABLES. The cache also holds
    marketplaces that were never enabled, backups of upgraded plugins, and
    payload directories meant for other tools. Counting all of it reported 319
    entries when Codex was indexing 197 -- and the report that came with it
    told the user their descriptions had collapsed to 16 characters when they
    were really at 42. A wrong number in the shape of a measurement is worse
    than no number, so the doctor now asks Codex and measures the real width.
    """
    code = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")

    assert "debug' 'prompt-input" in code, (
        "the doctor no longer asks Codex for the index it actually renders"
    )
    assert "### Available skills" in code, (
        "the doctor no longer parses the skills block out of Codex's own prompt"
    )
    assert r"(?:(?<desc>(?:(?!\\n).)*?) )?\(file:" in code, (
        "the doctor cannot measure a fully collapsed Codex index whose entries "
        "contain no description text"
    )
    # The recursive cache walk is the specific bug. Its return would restore
    # the 319-entry answer even with the new parser sitting next to it.
    assert "-Recurse -Filter 'skills'" not in code, (
        "the doctor is walking plugins\\cache recursively again; that counts "
        "plugins Codex never loads and inflates the reported index"
    )
    assert "Get-UabsCodexEnabledPluginIds" in code, (
        "the doctor's fallback no longer restricts itself to enabled plugins"
    )
    # Duplicates are the one lever the pack owns, so they must be named.
    assert "indexes $($dupes.Count) skill(s) twice" in code, (
        "the doctor no longer reports skills the pack copied that an enabled "
        "plugin already serves -- the only index cost the installer can fix"
    )
    assert "codex_skill_index" in code, (
        "the doctor's JSON report no longer carries the measured index, so "
        "nothing downstream can read it"
    )
    # An estimate must never be presented as a measurement.
    assert "$how='measured'" in code and "estimated from the nearest measured point" in code, (
        "the doctor no longer distinguishes a measured index from an estimated one"
    )


def test_codex_plugin_detection_survives_one_broken_marketplace() -> None:
    """An unreadable inventory is not an empty inventory.

    `codex plugin list --json` fails wholesale when ANY configured marketplace
    snapshot is unloadable, including one unrelated to the plugin being asked
    about. The installer read that empty result as "the native install failed",
    skipped the dedupe, and left 20 duplicate skills in the index -- measured
    on a machine whose only fault was a stale headroom-marketplace snapshot.
    """
    install = ps_code(ROOT / "INSTALL-AIO.ps1")
    common = ps_code(ROOT / "TOOLS" / "UABS-Common.ps1")

    assert "function Get-UabsCodexEnabledPluginIds" in common, (
        "the config.toml fallback for Codex's plugin registry is gone"
    )
    # Nested tables such as [plugins."browser@openai-bundled".ambient] carry
    # their own enabled keys. Matching them inverts the answer, so the section
    # pattern must be anchored to the top-level table.
    assert "'^\\[plugins\\.\"(?<id>[^\"]+)\"\\]$'" in common, (
        "the config.toml reader no longer anchors on the top-level plugins "
        "table; nested tables would be read as the plugin's own state"
    )
    assert "Get-UabsCodexEnabledPluginIds -CodexHome $providerHome" in install, (
        "the installer no longer falls back to Codex's own registry when the "
        "plugin inventory cannot be read"
    )
    # Silently degrading is how this went unnoticed for a release.
    assert "returned nothing usable" in install, (
        "the installer degrades to the config fallback without telling the user"
    )
    assert "codex plugin marketplace upgrade" in install, (
        "the installer reports a broken inventory without naming the repair"
    )


def test_subset_install_keeps_the_other_providers_native_plugin_records() -> None:
    """A narrow rerun updates its slice instead of replacing the full ledger.

    native_plugins records which skill copies a native plugin legitimately
    owns. The doctor treats a copy that is absent WITHOUT such a record as a
    fatal missing skill -- correctly, since that is what a half-finished
    install looks like. Writing the map wholesale after a single-provider run
    erased the record for the four providers that run never visited: measured,
    34 doctor errors on a machine where nothing was actually wrong.
    """
    install = ps_code(ROOT / "INSTALL-AIO.ps1")

    assert "$priorPlugins" in install, (
        "the installer no longer reads the previous native_plugins map, so a "
        "single-provider run erases every other provider's dedupe record"
    )
    merge = install[install.index("$priorPlugins"):][:900]
    assert "$nativePlugins.Contains($p.Name)" in merge, (
        "the carried-forward map is not keyed by provider, so this run's own "
        "results could be overwritten by the stale ones"
    )
    assert "-not $nativePlugins.Contains($p.Name)" in merge, (
        "the merge overwrites providers this run DID visit with their stale "
        "records, which is the opposite of the intended fix"
    )
    # The merge has to happen before the state is serialised, not after.
    assert install.index("$priorPlugins") < install.index("native_plugins = $nativePlugins"), (
        "the previous records are merged after the state object is built, so "
        "they never reach the file"
    )
    assert "$partialComponentRun = $SkillsOnly -or $PSBoundParameters.ContainsKey('Components')" in install, (
        "SkillsOnly or an explicit component repair can erase untouched tool records"
    )
    component_merge = install[install.index("$partialComponentRun"):][:700]
    assert "$priorState.components.PSObject.Properties" in component_merge
    assert "-not $installed.Contains($p.Name)" in component_merge, (
        "stale component records can overwrite results from the current partial run"
    )
    assert install.index("$partialComponentRun") < install.index("components = $installed"), (
        "untouched components are merged after the state object is already built"
    )
    assert "providers = $stateProviders" in install, (
        "a single-provider rerun still rewrites the installed provider inventory"
    )
    assert install.index("$stateProviders =") < install.index("providers = $stateProviders"), (
        "the provider union is computed after the state object is already built"
    )


def test_dead_autostarts_are_reported_and_never_deleted() -> None:
    """A boot-time launcher whose target is gone is a defect the user cannot see.

    Measured on the maintainer's machine 2026-08-26: three Startup entries
    written by past agent sessions, one of them (`cbm-dashboard-plus.vbs`)
    launching a script under a `Skyrim-AI-V5` tree that had been deleted
    entirely. It failed at every boot, silently, for a week.

    Two halves, and BOTH matter:

      * the doctor and the cleaner must NAME such an entry, and
      * neither may delete it. This pack has never written an autostart, so
        every one of them belongs to someone else. `Clean-StaleState.ps1`
        states that rule at the top of the file; a future edit that routes
        autostarts through `Add-CleanTarget` would break it.
    """
    common = ps_code(ROOT / "TOOLS" / "UABS-Common.ps1")
    doctor = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")
    cleaner = ps_code(ROOT / "TOOLS" / "Clean-StaleState.ps1")

    assert "function Get-UabsAiAutostartEntries" in common, (
        "the shared autostart reader is gone; the doctor and the cleaner would "
        "each have to grow their own copy"
    )
    # A .vbs launcher names the interpreter AND the script. It is normally the
    # second path that has gone missing, so scanning only the first misses the
    # exact case this was written for.
    assert "function Get-UabsAutostartTargetPaths" in common, (
        "autostart targets are no longer extracted, so 'dead' cannot be decided"
    )
    # The whole guarded line, not just the method name: UABS-Common calls
    # ExpandEnvironmentVariables elsewhere too, and a bare-name assertion
    # cannot tell that THIS one was deleted. Proven by falsification.
    assert (
        "try { $p = [Environment]::ExpandEnvironmentVariables($p) } catch { }"
        in common
    ), (
        "autostart target paths are no longer expanded; a launcher written with "
        "%LOCALAPPDATA% would always look missing"
    )
    # Both autostart surfaces. Dropping either one hides half the entries.
    assert r"Start Menu\Programs\Startup" in common, (
        "the Startup folder is no longer scanned"
    )
    assert r"CurrentVersion\Run" in common, (
        "the HKCU Run key is no longer scanned"
    )
    # PS 5.1 throws "Argument types do not match" for @() over a List[object]
    # whose items carry array-valued properties. ToArray() is not a style
    # preference here -- @($out) is a crash.
    assert "$out.ToArray()" in common, (
        "Get-UabsAiAutostartEntries no longer returns via ToArray(); on PS 5.1 "
        "wrapping this List[object] in @() throws"
    )
    # Bare 'chroma' matched Razer's RGB autostart. A false positive in a report
    # the user is meant to act on is a real cost.
    assert "|chroma-mcp|" in common, (
        "the autostart needle matches bare 'chroma' again; that hits Razer "
        "Synapse's --url-params=apps=synapse,chroma-app"
    )

    assert "Get-UabsAiAutostartEntries" in doctor, (
        "the doctor no longer reports AI autostarts"
    )
    assert "but its target is missing" in doctor, (
        "the doctor no longer distinguishes a dead autostart from a live one"
    )
    assert "ai_autostarts=@($autostartReport)" in doctor, (
        "the measured autostarts no longer reach the JSON report"
    )

    assert "Get-UabsAiAutostartEntries" in cleaner, (
        "Clean-StaleState no longer reports dead autostarts, so someone who "
        "runs the cleaner concludes they have none"
    )
    # The load-bearing assertion: reported, not planned for deletion.
    # Sliced on EXECUTABLE anchors: ps_code() strips comments, so the banner
    # comments that delimit this section for a human reader are not here.
    autostart_section = cleaner.split("$autostarts = @()")[-1]
    autostart_section = autostart_section.split("Write-UabsStep")[0]
    assert "Get-UabsAiAutostartEntries" in autostart_section, (
        "the autostart section could not be isolated; this contract is no "
        "longer checking what it claims to check"
    )
    assert "Add-CleanTarget" not in autostart_section, (
        "Clean-StaleState now plans autostarts for DELETION. This pack never "
        "created them; deletion is limited to what the pack created."
    )
    assert "$script:Reported.Add" in autostart_section, (
        "dead autostarts no longer go through the report-only channel"
    )


def test_codex_builtin_skills_are_discovered_not_hardcoded() -> None:
    """v8.6.6 adopted `skill-creator`; Codex already ships one of its own.

    The result was a skill indexed twice on Codex alone -- 184 entries at 48
    visible description chars against 183 at 50 without it. Codex's `.system`
    set also holds imagegen, openai-docs, plugin-creator, review-agent and
    skill-installer, so a future canonical skill taking any of those names
    collides the same way. The ownership must therefore be DISCOVERED from
    disk; a hardcoded name list would catch this one case and no other.
    """
    common = ps_code(ROOT / "TOOLS" / "UABS-Common.ps1")
    assert "function Get-UabsCodexBuiltinSkillNames" in common, (
        "the Codex built-in skill discovery is gone; a canonical skill sharing "
        "a name with one of Codex's own is indexed twice again"
    )
    body = common.split("function Get-UabsCodexBuiltinSkillNames", 1)[1]
    body = body.split("\nfunction ", 1)[0]
    assert "'.system'" in body or '".system"' in body, (
        "the discovery no longer reads Codex's .system root"
    )
    assert "'SKILL.md'" in body, (
        "a directory with no SKILL.md owns nothing; without this check an "
        "empty folder would evict the pack's working copy in favour of nothing"
    )
    # Discovered, never hardcoded: the collision that motivated this must not
    # appear as a literal anywhere in the discovery.
    assert "skill-creator" not in body, (
        "Codex built-ins are hardcoded again; only the one known collision "
        "would be caught and the other five names would not"
    )

    installer = ps_code(ROOT / "INSTALL-AIO.ps1")
    assert "Get-UabsCodexBuiltinSkillNames" in installer, (
        "the installer no longer dedupes copies Codex itself owns"
    )
    # It must reuse the verified remover, which backs up first and compares to
    # the provider-tailored source. That source may equal canonical today, but
    # it is the byte authority installed into this provider and is allowed to
    # diverge on the next fanout without being mislabeled as a user edit.
    tailored = (ROOT / "1-TAILORED-PROVIDER-TREES" / "Codex" /
                "COPY-TO-SKILLS-DIRECTORY" / "skills" / "skill-creator" / "SKILL.md")
    assert tailored.is_file(), "Codex's expected provider source is absent"
    codex_dedupe = installer.rsplit("Get-UabsCodexBuiltinSkillNames", 1)[1][:1100]
    assert "Remove-UabsPluginOwnedSkillCopies" in codex_dedupe, (
        "the built-in dedupe deletes directly instead of going through the "
        "remover that backs up and refuses user-modified copies"
    )
    assert "$expectedSkills" in codex_dedupe and "-ExpectedRoot $expectedSkills" in codex_dedupe, (
        "Codex built-in dedupe compares its tailored copy to canonical again"
    )
    remover = common.split("function Remove-UabsPluginOwnedSkillCopies", 1)[1].split("\nfunction ", 1)[0]
    assert "$ExpectedRoot" in remover and "$CanonicalRoot" not in remover, (
        "the shared deduper cannot distinguish bundle provider tailoring from a user edit"
    )

    doctor = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")
    assert "Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome" in doctor, (
        "the doctor does not verify Codex's live built-in ownership"
    )


def test_lmstudio_optimizer_writes_the_settings_that_actually_fit() -> None:
    """A good preset does not save you; the per-model settings win.

    Measured on the maintainer's machine: the `Hermes 16GB` preset was correct
    while four of five SAVED MODEL configs for the same family were unloadable
    -- q8_0 K/V, and one with three parallel sessions. The one in use asked for
    18.32 GiB on a card with ~14.5, so llama.cpp spilled to system RAM every
    session. LM Studio validates none of it.

    The three settings that cause it read as though they are free:
    cache quantisation, numParallelSessions (a MULTIPLIER on the whole cache),
    and offloadRatio.
    """
    script = ROOT / "BUNDLED-TOOLS" / "lm-studio" / "Optimize-LMStudioModelConfig.ps1"
    assert script.is_file(), "the LM Studio model-config optimizer is gone"
    body = ps_code(script)

    assert "'q4_0'" in body, "the optimizer no longer writes q4_0; q8_0 is double the cache"
    assert "llm.load.numParallelSessions' 1" in body, (
        "the optimizer no longer pins one parallel session -- the setting is a "
        "multiplier on the entire KV cache and nothing in its name says so"
    )
    assert "llm.load.llama.acceleration.offloadRatio' 1" in body, (
        "the optimizer no longer forces full GPU offload"
    )
    # Never write without a backup, and never write unasked.
    assert "Copy-Item" in body and "uabs-backup" in body, (
        "the optimizer overwrites user config without backing it up first"
    )
    assert "$Apply" in body, "the optimizer no longer has a dry-run default"

    # A context of 0 is not a setting. A model too big for any useful window
    # still has to be written a legal value.
    assert "-lt 4096" in body, (
        "the optimizer can write a context below 4096; flooring a tiny budget "
        "produced ctx 0 on a 14.26 GB quant during development"
    )

    readme = read(ROOT / "BUNDLED-TOOLS" / "lm-studio" / "README.md")
    assert "user-concrete-model-default-config" in readme, (
        "the README no longer says WHERE the settings that actually win are kept"
    )
    assert "Optimize-LMStudioModelConfig.ps1" in readme, "the README does not mention the optimizer"


def test_no_shipped_json_carries_a_byte_order_mark() -> None:
    """A UTF-8 BOM in a JSON file is invisible until something outside the pack
    reads it.

    Every reader *inside* the pack opens these with ``utf-8-sig``, so the BOM
    never surfaced here. It surfaced in the shipped archives: the Core variant
    rewrites ``OFFLINE-MANIFEST.json`` through ``json.dumps(...).encode('utf-8')``
    and therefore shipped it BOM-less, while the source tree and the Full
    variant shipped the same logical file with three extra leading bytes. Same
    file, two encodings, decided by which archive you downloaded.

    ``json.load(open(path))`` -- the obvious call, and the one any consumer
    outside this repo writes -- raises on the BOM version and succeeds on the
    other. These are also the same three bytes that broke ``START-HERE.bat`` in
    two separate releases.

    Walks MANIFEST.json rather than naming the two known files, so a BOM
    entering through any *new* JSON fails too. MANIFEST and not ``git
    ls-files``: this suite is also run from an extracted archive, where there
    is no git.
    """
    bom = b"\xef\xbb\xbf"
    manifest = json.loads(read(ROOT / "MANIFEST.json"))
    rows = manifest["files"] if isinstance(manifest, dict) else manifest

    offenders = []
    checked = 0
    for row in rows:
        rel = row["path"] if isinstance(row, dict) else row
        if not rel.endswith(".json"):
            continue
        p = ROOT / rel
        if not p.is_file():
            continue
        checked += 1
        if p.read_bytes().startswith(bom):
            offenders.append(rel)

    assert checked > 5, (
        "only %d JSON files were inspected; MANIFEST.json is not being walked "
        "and this contract is asserting nothing" % checked
    )
    assert not offenders, (
        "these shipped JSON files start with a UTF-8 BOM, so plain "
        "json.load(open(path)) fails on them for any reader outside this pack: "
        + ", ".join(sorted(offenders))
    )

    # Absence of a BOM is not the same as the file still reading. Prove the
    # two that actually carried one parse the plain way.
    for rel in ("BUNDLED-TOOLS/CATALOG.json", "BUNDLED-TOOLS/OFFLINE-MANIFEST.json"):
        p = ROOT / rel
        assert p.is_file(), rel + " is gone"
        with io.open(str(p), encoding="utf-8") as fh:
            json.load(fh)

    # Both shipped variants must keep agreeing on the encoding of the one file
    # whose Core bytes are regenerated rather than copied.
    build = read(ROOT / "TOOLS" / "build_release.py")
    assert "encode('utf-8')" in build or 'encode("utf-8")' in build, (
        "build_release no longer states the encoding it writes the Core "
        "OFFLINE-MANIFEST with; Core and Full can silently diverge again"
    )

def test_rtk_is_documented_as_a_git_tool_not_a_general_filter() -> None:
    """Every rtk number this pack shipped before 8.6.11 was a git command.

    Measured off git at 0.46.0 the same tool aggregates **7.4%** against git's
    85.2%, one subcommand breaks outright, and a blanket claim this pack
    had been repeating turned out to be false. All three have to survive in the
    docs, because each one is the kind of fact that a tidy-up deletes:

    1. ``rtk find`` breaks on **compound predicates**. A simple ``-name`` works
       (709 -> 565 B, exit 0); adding ``-not -path`` returns **0 bytes, exit
       1**. The first pass here diagnosed this as shell-expansion of the
       pattern and was wrong -- caught before the release was tagged, which is
       why the corrected form is pinned rather than the symptom. Upstream has
       ten-plus open issues against ``rtk find`` alone, including #3410, where
       the unconditional rewrite captures ``find ... -delete``/``-exec`` and
       refuses it, breaking ``&&`` chains. The ``-g`` hook rewrites ``find``
       automatically.
    2. ``rtk json`` on a 5,425-row array returns one element and
       ``... +5424 more``. 100% "saved" is 100% of the data gone.
    3. rtk does **not** always discard. ``rtk test`` writes a complete tee log
       and prints its path. The pack shipped "no archive and no retrieval" as
       an unqualified property of the tool; it is true only of some
       subcommands.
    """
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    entry = next((c for c in catalog["components"] if c.get("id") == "rtk"), None)
    assert entry, "CATALOG.json no longer lists rtk"
    note = entry["scope_note"]
    readme = read(ROOT / "README.md")

    # 1. The broken subcommand, in both places.
    for where, text in (("catalog note", note), ("README", readme)):
        assert "rtk find" in text, (
            "the %s no longer names `rtk find`, which returns EMPTY stdout for "
            "-name patterns at 0.46.0 and is rewritten automatically by the hook"
            % where
        )
    # Pin the CORRECTED diagnosis, not the symptom. The first pass blamed
    # shell-expansion; a simple `-name` works fine and the compound predicate
    # is what fails. If "compound" disappears, the wrong story is back.
    for where, text in (("catalog note", note), ("README", readme)):
        assert "compound" in text.lower(), (
            "the %s no longer says COMPOUND PREDICATE is what breaks `rtk find`. "
            "A simple -name works; an earlier draft of this pack blamed "
            "shell-expansion of the pattern and was wrong" % where
        )
    assert "3410" in note or "3410" in readme, (
        "the reference to upstream rtk-ai/rtk#3410 is gone -- the unconditional "
        "`find` rewrite that captures `-delete`/`-exec` and breaks && chains is "
        "the most serious thing known about this subcommand, and it is their "
        "report rather than anything measured here"
    )

    # 2. Truncation must never be presented as compression.
    assert "TRUNCATION IS NOT SAVING" in note or "truncat" in note.lower(), (
        "the catalog note lost the warning that rtk json's 100% is truncation"
    )

    # 3. The archive claim must stay qualified. This is the assertion that
    #    matters: the unqualified sentence is what shipped, and it was wrong.
    lowered = note.lower()
    if "no archive" in lowered:
        window = lowered.split("no archive", 1)[1][:400]
        assert "rtk test" in window or "corrected" in lowered, (
            "the catalog note claims rtk keeps 'no archive' without qualifying "
            "it -- `rtk test` writes a COMPLETE tee log and prints the path, so "
            "the blanket form of this claim is false"
        )
    assert "tee" in lowered, (
        "the catalog note no longer mentions the tee archive at all; the "
        "correction to the 'rtk discards everything' claim has been lost"
    )

    # The non-git aggregate has to be stated next to the git one, or the
    # 85-88% headline reads as the tool's general behaviour.
    assert "7.4%" in note, "the catalog note lost the measured non-git aggregate"
    assert "7.4%" in readme, "the README lost the measured non-git aggregate"

    # And the hook decision has to stay attached to its evidence.
    rtk_section = readme.split("### rtk:", 1)[1].split("\n### ", 1)[0]
    assert "not rewritten" in rtk_section, (
        "the README dropped the rewrite table showing that `npm test`, `curl` "
        "and `python x.py` are NOT rewritten -- which is why the hook does not "
        "deliver the only strong non-git rows"
    )

def test_doctor_reports_hooks_that_steer_at_unregistered_mcps() -> None:
    """A session hook that TELLS an agent to use an MCP is only correct while
    that MCP is registered, and this pack profile-gates most of its MCPs.

    Those two facts drift apart silently, and the cost is invisible: the
    instructions reach the model, the tools do not, and the turn is spent
    reaching for something uncallable.

    Found on the maintainer's machine 2026-08-27: ``cbm-session-reminder``,
    installed by codebase-memory-mcp itself, emitted 695 bytes of "ALWAYS use
    codebase-memory-mcp tools FIRST" naming six tools on every startup,
    resume, clear and compact -- while codebase-memory was registered on no
    provider at all.

    The doctor reports it and never rewrites it, exactly like the autostart
    check: these hooks belong to the tools that installed them.

    Two properties this pins, because getting either wrong makes the check
    useless rather than merely noisy:

    1. A hook that emits nothing is not flagged. cbm's *other* hook shells out
       to a binary and exits; its own comment says it "NEVER blocks a tool
       call". Flagging it would be a false positive.
    2. A hook that GATES itself is not flagged. Punishing the fix is worse
       than not having the check -- and the guard must be found across the
       whole body, because a gate is invoked by piping the payload into it
       (``printf ... | gate || exit 0``) and that printf is the hook asking,
       not the hook speaking. An earlier draft anchored on the first print
       construct and therefore read the guard as arriving too late, flagging
       a hook that was already correct.
    """
    doctor = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")

    assert "hookMisdirection" in doctor, (
        "the doctor no longer checks whether a session hook instructs agents "
        "toward an MCP server that is registered nowhere"
    )
    assert "registered on no provider" in doctor, (
        "the hook-misdirection warning lost the text that says WHY it fired"
    )

    # It must decide "unregistered" from the measured capability states, not
    # from a hardcoded list of server names.
    idx = doctor.index("hookMisdirection")
    prelude = doctor[:idx]
    assert "capabilityStates" in prelude and "registered_for" in prelude, (
        "the check no longer derives 'unregistered' from the doctor's own "
        "measured capability states; a hardcoded server list would rot"
    )
    assert "codebase-memory" not in doctor.split("hookMisdirection")[0][-4000:], (
        "the check appears to hardcode codebase-memory rather than walking "
        "whatever the capability states report as unregistered"
    )

    # Property 1: silent hooks are exempt.
    assert "Write-Output" in doctor and "printf" in doctor, (
        "the emit-detection that exempts hooks producing no text is gone"
    )

    # Property 2: self-gated hooks are exempt, checked across the whole body.
    assert "(exit\\s+0|return)" in doctor, (
        "the doctor no longer exempts hooks that gate themselves with a "
        "conditional early exit -- it would now warn about the very fix it "
        "asks for"
    )
    assert "$prelude" not in doctor, (
        "the gate detection is anchored on the text before the first print "
        "again; a gate invoked as `printf ... | gate || exit 0` puts a printf "
        "ahead of its own guard and is then misread as ungated"
    )

    # Reported, never repaired.
    assert "does not rewrite hooks it did not install" in doctor, (
        "the doctor no longer states that it leaves these hooks alone; this "
        "pack reports third-party hooks, it does not edit them"
    )

    # And it has to reach the JSON report, or nothing downstream can see it.
    assert "hook_misdirection" in doctor, (
        "hook misdirection is printed but never written to "
        "installed-state-doctor.json"
    )

def test_doctor_reports_pack_tools_shadowed_by_another_copy() -> None:
    """The installer records where it put each tool. Nothing checked that the
    recorded copy is the one that actually runs.

    Measured 2026-08-27: codebase-memory-mcp had been updated to 0.10.8 under
    ``%LOCALAPPDATA%\\Programs``, while ``%USERPROFILE%\\.local\\bin`` still held
    a **0.9.0** binary from six weeks earlier -- and ``.local\\bin`` came first
    on PATH, so every caller got 0.9.0, including codebase-memory's own
    discovery hook, which hardcodes that path. The update had reported success
    on every run it ever made.

    The sibling failure, found the same day, is not path order at all:
    ``headroom`` was pip-installed at **0.36.5** into Python 3.14 while the
    registered launcher belonged to Python 3.12, which had **0.35.0**. Same
    symptom -- an update that succeeds and changes nothing -- via a different
    mechanism. That one is documented rather than automated.

    Two properties keep this check useful rather than noisy:

    1. **Two copies alone is not a finding.** Several tools legitimately
       install their own launcher alongside the pack's. Only copies that
       *differ* can silently diverge, so the sizes are compared and identical
       ones are passed over.
    2. **Compared by length, not hash.** These are single-file builds, so a
       version change always moves the size, and hashing a 274 MB binary on
       every doctor run buys certainty nobody needs.

    Reported with both paths, never repaired: which copy should win is a PATH
    decision, and this pack does not reorder anyone's PATH.
    """
    doctor = ps_code(ROOT / "TOOLS" / "Test-Installed-State.ps1")

    assert "shadowed" in doctor, (
        "the doctor no longer checks whether a pack-installed tool is shadowed "
        "by another copy earlier on PATH"
    )
    assert "PATH resolves" in doctor, (
        "the shadowing warning lost the text naming which copy actually wins"
    )

    # Property 1: identical copies are not reported.
    assert "-eq $sizeB" in doctor or "$sizeA -eq $sizeB" in doctor, (
        "the doctor no longer skips shadowed copies that are byte-equal in "
        "length -- it will now warn about every tool that ships its own "
        "launcher next to the pack's, which is normal and not a defect"
    )

    # It has to read the recorded install location rather than guess one.
    assert "install-state.json" in doctor, (
        "the shadowing check no longer reads install-state.json, so it has "
        "nothing authoritative to compare PATH against"
    )
    assert "Get-Command" in doctor, (
        "the check no longer resolves the tool through PATH, which is the "
        "whole comparison"
    )

    # Reported, never repaired -- same rule as autostarts and third-party hooks.
    assert "does not reorder your PATH" in doctor, (
        "the doctor no longer states that it leaves PATH alone; this pack "
        "reports this condition, it does not fix it"
    )

    # And it must reach the JSON report.
    assert "shadowed_tools" in doctor, (
        "shadowed tools are printed but never written to "
        "installed-state-doctor.json"
    )

def test_retired_marketplaces_are_unregistered_not_just_undeployed() -> None:
    """Marketplace registration is additive in every provider, and nothing ever
    removed one.

    ``Install-Provider-Starter-Settings.ps1`` only ever ADDS to
    ``extraKnownMarketplaces``. No provider removes a marketplace when the tool
    behind it is uninstalled. So a dead registration outlives its tool -- and
    it **propagates**, because Grok inherits Claude's marketplace list.

    Measured 2026-08-27: claude-mem had been uninstalled and 1.29 GB of its
    payload already reclaimed, yet ``thedotmack`` was still registered in
    Claude's ``known_marketplaces.json`` *and* ``settings.json``, still cloned
    at 140 MB, still present as four orphaned 140 MB temp clones, and had been
    synced into ``~/.grok/marketplace-cache`` -- where grok reported
    ``thedotmack (0 plugins) [error] Git sync failed: failed to lock cache``.
    The user never registered it in Grok at all.

    ``RETIRED-SKILLS.json`` already solved exactly this for skills. This is the
    same idea for marketplaces, and the safety rails have to match:

    1. **Name AND url must both match.** Removing on name alone would delete a
       marketplace someone re-pointed at their own fork.
    2. **A marketplace still backing an ENABLED plugin is never touched.** The
       point is clearing the dead, not disabling something in use.
    3. **Every edited config is backed up first.**
    """
    catalog_path = ROOT / "BUNDLED-TOOLS" / "RETIRED-PLUGINS.json"
    assert catalog_path.is_file(), (
        "BUNDLED-TOOLS/RETIRED-PLUGINS.json is gone; retired marketplaces have "
        "nothing declaring them and will accumulate again"
    )
    data = json.loads(read(catalog_path))
    retired = data.get("retired") or []
    assert retired, "RETIRED-PLUGINS.json declares no retired marketplaces"
    for e in retired:
        assert e.get("marketplace"), "a retired entry has no marketplace name"
        assert e.get("url"), (
            "retired marketplace %r has no url; name-only matching would delete "
            "a marketplace someone re-pointed at their own fork" % e.get("marketplace")
        )
        assert e.get("reason"), (
            "retired marketplace %r has no reason; a deletion list nobody can "
            "audit is how a live entry gets removed by accident" % e["marketplace"]
        )

    # A retired marketplace in a fresh-install template makes every install
    # add it and the cleanup pass remove it again, producing backup litter on
    # every identical rerun. The opt-in component may still register it when
    # explicitly requested; defaults may not.
    starter_candidates = _starter_templates() + [
        ROOT / "1-TAILORED-PROVIDER-TREES" / "Claude" / "settings.json"
    ]
    for entry in retired:
        needles = (entry["marketplace"].lower(), entry["url"].lower())
        bad = [
            p.relative_to(ROOT).as_posix()
            for p in starter_candidates
            if any(needle in read(p).lower() for needle in needles)
        ]
        assert not bad, (
            "retired marketplace %s is still shipped in fresh-install settings: %s"
            % (entry["marketplace"], ", ".join(bad))
        )

    # A retired marketplace MAY belong to a component the pack still ships --
    # claude-mem is opt-in behind -WithClaudeMem and its catalog entry
    # registers this very marketplace. That is only safe because the cleaner
    # skips a marketplace whose plugin is still installed or enabled. Without
    # that guard the cleanup at the end of every install would unregister what
    # the same install had just registered.
    live = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    live_repos = set()
    for c in live.get("components", []):
        gh = c.get("github") or {}
        if gh.get("owner") and gh.get("repo"):
            live_repos.add(("%s/%s" % (gh["owner"], gh["repo"])).lower())
    overlapping = []
    for e in retired:
        slug = e["url"].lower().rstrip("/")
        if slug.endswith(".git"):
            slug = slug[:-4]
        overlapping.append("/".join(slug.split("/")[-2:]) in live_repos)
    if any(overlapping):
        guard = ps_code(ROOT / "TOOLS" / "Clean-StaleState.ps1")
        assert "installed_plugins.json" in guard, (
            "a retired marketplace belongs to a component CATALOG.json still "
            "ships, but the cleaner does not check installed_plugins.json -- "
            "the install-time cleanup would unregister what the install just "
            "registered, on every single run"
        )

    cleaner = ps_code(ROOT / "TOOLS" / "Clean-StaleState.ps1")
    assert "RETIRED-PLUGINS.json" in cleaner, (
        "Clean-StaleState no longer reads RETIRED-PLUGINS.json, so retired "
        "marketplaces are declared and never acted on"
    )

    # Rail 1: url must be compared, not just the name.
    assert "Test-UabsUrlMatch" in cleaner, (
        "the cleaner no longer compares the marketplace URL before removing it "
        "-- name-only matching would delete a re-pointed fork"
    )

    # Rail 2: never remove one that still backs an enabled plugin.
    assert "enabledPlugins" in cleaner and "installed_plugins.json" in cleaner, (
        "the cleaner no longer checks both enabledPlugins and "
        "installed_plugins.json before unregistering a marketplace; it could "
        "disable something the user is actively using, or fight the installer "
        "over a component the pack still ships"
    )
    assert "still installed or enabled as" in cleaner, (
        "the cleaner lost the message explaining why a retired marketplace was "
        "left alone; a silent skip is indistinguishable from a broken check"
    )

    # Rail 3: back up before editing anyone's config.
    assert "bak-retired-" in cleaner, (
        "the cleaner edits provider config without writing a backup first"
    )

    # All three registration shapes have to be handled, or the entry survives
    # in whichever provider was skipped and syncs back into the others.
    for needle, what in (
        ("known_marketplaces", "Claude's marketplace registry"),
        ("extraKnownMarketplaces", "Claude's settings.json"),
        ("marketplace-cache", "Grok's hashed clone cache"),
        ("[marketplaces.", "Codex's config.toml tables"),
    ):
        assert needle in cleaner, (
            "the cleaner no longer handles %s; a retired marketplace left there "
            "propagates back into the providers that inherit it" % what
        )

    # Grok's cache directories are hashed, so they can only be matched by remote.
    assert ".git\\config" in cleaner or ".git/config" in cleaner, (
        "the cleaner no longer identifies Grok's hashed marketplace caches by "
        "their git remote, which is the only way to tell which one is which"
    )

def test_always_on_mcp_pins_come_from_the_catalog() -> None:
    """A version in two places is a version in the wrong place.

    ``TOOLS/Add-Reasoning-MCPs.ps1`` wires the always-on core -- context7,
    github, headroom -- onto all five providers. Until 8.6.12 it carried its
    own hardcoded ``@upstash/context7-mcp@4.0.2``, and that made the catalog
    decorative for the one npx server every provider registers.

    Proven, not assumed: 8.6.12 bumped context7 to 4.0.3 in ``CATALOG.json``,
    re-measured its capability record, and ran the full installer. Afterwards
    **all five providers were still pinned to 4.0.2** -- Claude, Codex, Grok,
    Kimi and Hermes -- because this one file had its own copy of the number.
    A catalog bump that cannot reach an installed machine is not a bump.

    The same file's own comment already said CATALOG entries "carry a version
    to check rather than only a pin to trust", which is what made the
    duplicate so easy to miss.
    """
    src = ps_code(ROOT / "TOOLS" / "Add-Reasoning-MCPs.ps1")
    migrator = ps_code(ROOT / "TOOLS" / "Migrate-HermesProfiles.ps1")
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    c7 = next((c for c in catalog["components"] if c.get("id") == "context7"), None)
    assert c7, "CATALOG.json no longer describes context7"
    declared = c7["version"]

    # It must read the catalog rather than carry its own pin.
    assert "CATALOG.json" in src, (
        "Add-Reasoning-MCPs.ps1 no longer reads CATALOG.json, so the context7 "
        "pin it writes to all five providers can drift from the catalog again"
    )
    assert "$context7Args" in src, (
        "the resolved-from-catalog context7 argument list is gone"
    )

    # The literal pin may survive ONLY as the documented fallback, and it must
    # not be what the server entry actually uses.
    entry = re.search(r"id\s*=\s*'context7'.*?\}", src, re.S)
    assert entry, "the context7 server entry is no longer recognisable"
    body = entry.group(0)
    assert "$context7Args" in body, (
        "the context7 entry stopped using the catalog-resolved arguments"
    )
    assert not re.search(r"args\s*=\s*@\(\s*'-y'\s*,\s*'@upstash/context7-mcp@", body), (
        "the context7 entry hardcodes its package pin again; bumping "
        "CATALOG.json will silently not reach any provider"
    )

    # Whatever literal remains must be a fallback, and must never be NEWER than
    # the catalog -- a fallback ahead of the catalog would install an untested
    # version whenever the catalog read fails.
    literals = re.findall(r"@upstash/context7-mcp@([0-9][0-9.]*)", src)
    for lit in literals:
        assert tuple(int(x) for x in lit.split(".")) <= tuple(
            int(x) for x in declared.split(".")
        ), (
            "the hardcoded context7 fallback (%s) is newer than the catalog "
            "declares (%s); if the catalog read fails this installs a version "
            "nothing measured" % (lit, declared)
        )

    # Hermes has a second writer for its native named profiles. It used to keep
    # the exact hardcoded 4.0.2 pin this contract removed from the AIO writer.
    assert "CATALOG.json" in migrator and "$context7Args" in migrator
    hermes_entry = re.search(r"Get-UabsCoreSpec.*?'context7'.*?\}\s*'context7'", migrator, re.S)
    assert hermes_entry and "args = $context7Args" in hermes_entry.group(0), (
        "Hermes' standalone profile migrator stopped using the Context7 args "
        "resolved from CATALOG.json"
    )
    for lit in re.findall(r"@upstash/context7-mcp@([0-9][0-9.]*)", migrator):
        assert tuple(int(x) for x in lit.split(".")) <= tuple(
            int(x) for x in declared.split(".")
        ), "Hermes carries an unmeasured Context7 fallback newer than the catalog"

def test_manifest_covers_every_tracked_file() -> None:
    """``verify_manifest.py`` proves every RECORDED file exists. Nothing proved
    every existing file is recorded, and the difference hid two bugs.

    1. ``git ls-files`` **octal-quotes** any path containing a non-ASCII byte.
       An em dash came back as
       ``"0-UNRESTRAINT-PACKS/AIO-INSTRUCTION \\342\\200\\224 Compact.md"``,
       quotes included, while ``os.walk`` yielded the real name. They never
       matched, so eleven tracked files were dropped from the manifest in
       silence. Fixed with ``ls-files -z``.
    2. ``MANIFEST.json`` was skipped by bare NAME anywhere in the tree, which
       also excluded the vendored Forge manifest at
       ``BUNDLED-TOOLS/skyrim-forge/MANIFEST.json``. Now skipped only at the
       root, where it genuinely cannot hash its own output.

    Twelve tracked files were shipping unverified. Both failures are invisible
    to a verifier that only walks the manifest, which is exactly why this walks
    the other direction.

    Skipped when git is unavailable -- this suite also runs from an extracted
    archive, where there is no repository to compare against.
    """
    try:
        raw = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z"],
            capture_output=True, check=True,
        ).stdout
    except Exception:
        return  # extracted archive: nothing to compare against

    tracked = {p for p in raw.decode("utf-8").split("\0") if p}
    tracked.discard("MANIFEST.json")

    rows = json.loads(read(ROOT / "MANIFEST.json"))
    recorded = {r["path"] for r in rows}

    # The names that trigger this are non-ASCII by definition, and this
    # message is printed to a cp1252 console. Escape them, or the contract
    # dies with a UnicodeEncodeError instead of saying what is wrong -- which
    # is exactly what the first version of it did.
    def _safe(paths):
        return ", ".join(p.encode("ascii", "backslashreplace").decode("ascii")
                         for p in paths[:5])

    uncovered = sorted(tracked - recorded)
    assert not uncovered, (
        "%d tracked file(s) are absent from MANIFEST.json and therefore ship "
        "with no recorded hash; verify_manifest.py cannot see this because it "
        "only checks that recorded files exist. First few: %s"
        % (len(uncovered), _safe(uncovered))
    )

    phantom = sorted(recorded - tracked)
    assert not phantom, (
        "%d file(s) are recorded in MANIFEST.json but are not tracked; a fresh "
        "clone will fail verification with MISSING for files it never had. "
        "First few: %s" % (len(phantom), _safe(phantom))
    )

    # The generator must keep reading NUL-separated paths, or the non-ASCII
    # names silently drop out again and this contract is the only thing that
    # would have noticed.
    gen = read(ROOT / "TOOLS" / "generate_manifest.py")
    assert "'ls-files', '-z'" in gen or '"ls-files", "-z"' in gen, (
        "generate_manifest.py stopped using `git ls-files -z`; paths with a "
        "non-ASCII byte come back octal-quoted, never match the filesystem "
        "walk, and vanish from the manifest without an error"
    )

def test_a_running_mcp_binary_cannot_fail_the_whole_install() -> None:
    """Running the installer with the AI apps open used to abort everything.

    A component whose binary is currently running cannot be overwritten.
    robocopy answers that with exit code 8, ``Copy-UabsRobo`` turns exit >= 8
    into a throw, and the throw takes down the entire install:

        INSTALL FAILED
        robocopy failed exit=8 from=...uabs-extract-github-mcp-server-...

    Measured 2026-08-27 with four ``github-mcp-server`` processes alive as MCP
    servers for open Claude, Codex, Grok, Kimi and Hermes sessions -- which is
    the *ordinary* case, not an edge one. One locked file, and nothing else in
    the run completed.

    houseCARL and codebase-memory already handled this. The generic
    ``zip-extract`` branch every other component falls through to did not, and
    ``github-mcp-server`` falls through to it.

    Two properties, and the second is the one that matters:

    1. The lock is **detected** and the owning process stopped, so the update
       normally still happens. It did here: 1.10.1 -> 1.11.0 on the same run
       that had just failed.
    2. If the file still will not release, that component is **skipped with a
       warning**, not thrown. Aborting an entire install over one MCP binary
       is disproportionate, and the user cannot act on it without being told
       which file and why.
    """
    aio = ps_code(ROOT / "INSTALL-AIO.ps1")

    # The generic branch must consult the lock helpers the pack already has.
    assert "Test-UabsFileLocked" in aio, (
        "INSTALL-AIO no longer checks whether a target binary is locked before "
        "overwriting it; robocopy exit 8 will abort the whole install again"
    )
    assert "Stop-UabsProcessUsingExecutable" in aio, (
        "the installer no longer tries to stop the process holding a locked "
        "binary, so an update silently never happens"
    )

    # Property 2: skip, do not throw.
    assert "skipped-in-use" in aio, (
        "a still-locked component no longer degrades to a recorded skip; one "
        "running MCP server can take the entire install down again"
    )
    assert "Nothing else in this install was affected" in aio, (
        "the skip no longer tells the user the rest of the install survived, "
        "which is the whole difference between this and INSTALL FAILED"
    )
    assert "Close every AI app" in aio, (
        "the skip warning no longer says what to DO about it"
    )

    # The skip must be recorded, or the doctor and the state file cannot tell
    # a stale component from a current one.
    idx = aio.index("skipped-in-use")
    window = aio[max(0, idx - 600):idx + 600]
    assert "locked" in window, (
        "the skipped-in-use record does not name which files were locked, so "
        "nothing downstream can report what stayed behind"
    )

    # And the raw copy must remain the else-branch, not the default path.
    assert "Copy-UabsRobo -From $rootExtract -To $target" in aio, (
        "the generic extract no longer copies at all when nothing is locked"
    )

def test_an_unenabled_profile_is_never_reported_as_a_missing_tool() -> None:
    """Gating MCP servers on cost is defensible. Failing with no path forward
    is not.

    Reported by the maintainer 2026-08-27, from a real Grok transcript: the
    agent tried houseCARL and Skyrim Forge tools, both searches returned
    nothing, and it concluded "houseCARL and Forge MCP are disconnected". No
    part of the pack told anyone that both tools were *installed* and one
    command from working, or what that command was. Their words: "I don't even
    know how to change profiles on grok."

    Three separate holes, all of which had to be filled:

    1. ``skyrim-tool-router`` said "if a tool is missing, recommend install".
       houseCARL **is** installed -- following that advice tells the user to
       install what they already have.
    2. ``tool-discovery`` had one failure mode, TOOL MISSING, and no concept of
       installed-but-not-registered.
    3. ``INSTALL-AIO`` runs ``Set-McpProfile -Auto`` **only when
       ``-WorkspaceRoot`` is passed**, and ``START-HERE.bat`` never passes it.
       So on a default install the detection had never run, and the closing
       text mentioned the command without ever saying that zero profiles were
       enabled.

    The pack may absolutely keep these servers off by default. It may not leave
    the user to guess that "off" is why nothing works.
    """
    router = read(ROOT / "_CANONICAL-SKILLS" / "skyrim-tool-router" / "SKILL.md")
    discovery = read(ROOT / "_CANONICAL-SKILLS" / "tool-discovery" / "SKILL.md")
    aio = ps_code(ROOT / "INSTALL-AIO.ps1")

    # 1 + 2: both skills must name the enable command, and must distinguish the
    # two failures rather than treating everything as an install.
    for name, text in (("skyrim-tool-router", router), ("tool-discovery", discovery)):
        assert "Set-McpProfile" in text, (
            "%s never names Set-McpProfile, so an agent that finds no houseCARL "
            "or Forge tools has no way to tell the user what to do" % name
        )
        assert "not enabled" in text.lower() or "NOT ENABLED" in text, (
            "%s no longer distinguishes 'installed but not enabled for this "
            "project' from 'not installed'; it will tell users to install "
            "something they already have" % name
        )
        assert "restart" in text.lower(), (
            "%s does not say the AI app must be restarted; a running session "
            "does not pick up a newly registered MCP server, so the fix looks "
            "like it did not work" % name
        )

    # 3: the installer must report the actual state, not just mention a command.
    assert "NONE are enabled for any project yet" in aio, (
        "INSTALL-AIO no longer says when zero project profiles are enabled. "
        "-Auto only runs when -WorkspaceRoot is passed and START-HERE.bat never "
        "passes it, so silence here means the user is never told these servers "
        "exist, let alone that they are off"
    )
    assert "one-command fix, not an install problem" in aio, (
        "the installer notice no longer distinguishes this from an install "
        "failure, which is the entire confusion it exists to prevent"
    )
    assert "Currently enabled:" in aio, (
        "the installer no longer lists which profiles ARE enabled, so a user "
        "cannot tell a working setup from an empty one"
    )
    assert "$pr.Value.global" in aio and "(global)" in aio, (
        "machine-wide profiles are rendered as a blank project path"
    )
    # It must read real state rather than printing a fixed sentence.
    assert "mcp-profiles.json" in aio, (
        "the installer prints profile guidance without reading mcp-profiles.json, "
        "so the message cannot reflect what is actually enabled"
    )

def test_every_canonical_skill_reached_every_provider_tree() -> None:
    """Editing a canonical skill and shipping are two different acts.

    ``_CANONICAL-SKILLS`` is the authoring tree. ``INSTALL-AIO`` copies from
    ``1-TAILORED-PROVIDER-TREES/<Provider>/COPY-TO-SKILLS-DIRECTORY/skills``,
    which ``TOOLS/fanout_providers.py`` generates. Forget the fanout and the
    edit exists only where nothing reads it.

    Measured 2026-08-27, on this very repo: two skills were corrected so an
    agent would stop telling users to *install* an already-installed houseCARL.
    The full gate ran green -- **104 contracts** -- the installer reported
    "skills installed" for all five providers, and every provider copy was
    still yesterday's file. Nothing failed. Nothing shipped.

    Two contracts already touched this and neither would have caught it: one
    byte-compares only a short list of "v7.8 reliability skills", the other
    compares only the *set of names* in each tree, never their contents. The
    two edited skills were in neither list.

    Normalisation, both parts load-bearing:

    * the nested ``provider:`` metadata line is rewritten per target by design
      and is the only intended per-provider tailoring;
    * line endings, because ``unrestraint-packs`` carries mixed EOLs in
      canonical that the fanout writes out as CRLF. That is cosmetic and
      predates this check; failing on it would train people to ignore the
      contract.

    Everything else must match, for all 164 skills across all five trees.
    """
    providers = ["Claude", "Codex", "Grok", "Kimi", "Hermes"]
    tag = re.compile(r"(?m)^\s*provider:\s*\S+\s*$\n?")

    def norm(raw: bytes) -> str:
        text = raw.decode("utf-8").replace("\r\n", "\n")
        return tag.sub("", text)

    canon = sorted(CANON.glob("*/SKILL.md"))
    assert len(canon) >= 100, "canonical tree looks empty (%d skills)" % len(canon)

    drifted = []
    missing = []
    for p in canon:
        name = p.parent.name
        expected = norm(p.read_bytes())
        for prov in providers:
            q = (ROOT / "1-TAILORED-PROVIDER-TREES" / prov /
                 "COPY-TO-SKILLS-DIRECTORY" / "skills" / name / "SKILL.md")
            if not q.is_file():
                missing.append("%s/%s" % (prov, name))
                continue
            if norm(q.read_bytes()) != expected:
                drifted.append("%s/%s" % (prov, name))

    assert not missing, (
        "%d canonical skill(s) never reached a provider tree: %s -- run "
        "`python TOOLS/fanout_providers.py _CANONICAL-SKILLS .`"
        % (len(missing), ", ".join(sorted(missing)[:5]))
    )
    assert not drifted, (
        "%d provider copy(ies) differ from canonical in content: %s. Editing "
        "_CANONICAL-SKILLS does not ship anything on its own -- INSTALL-AIO "
        "copies from 1-TAILORED-PROVIDER-TREES. Run "
        "`python TOOLS/fanout_providers.py _CANONICAL-SKILLS .`"
        % (len(drifted), ", ".join(sorted(drifted)[:5]))
    )

def test_profile_detection_sees_a_workspace_of_projects() -> None:
    """Detection scanned only the project root, and people do not work that way.

    Measured 2026-08-27 on the maintainer's Skyrim workspace: 45 mod
    directories holding **327 .esp and 5,877 .psc files**, and
    ``Set-McpProfile -Detect`` reported *"no profile markers found"* -- because
    not one marker sits at the root. Their agent then failed on missing
    houseCARL and Forge tools with nothing to suggest, which is the exact
    failure the profile system exists to prevent.

    Root-only was deliberate, and its two reasons still stand: a recursive scan
    of a large tree is slow, and it matches markers belonging to vendored
    dependencies. Neither argues for missing the *workspace* shape, where each
    immediate child is a project.

    So: root, then immediate subdirectories. **Depth 1, never recursive.**
    0.6 s on that 45-project tree, and `game-skyrim` now fires.

    Two properties, both load-bearing:

    1. **Bounded.** Depth 1 and a cap on how many children are examined, or a
       directory with thousands of entries turns `-Detect` into a stall.
    2. **Vendor directories skipped by name.** `node_modules`, `vendor`,
       `dist`, `.venv` and friends hold someone else's markers. Matching those
       is the false positive the original rule was protecting against, and
       widening the scan without this would reintroduce it.
    """
    src = ps_code(ROOT / "TOOLS" / "Set-McpProfile.ps1")

    assert "Test-UabsProfileMarkersIn" in src, (
        "the per-directory marker test was folded back into the detector, so "
        "detection can only look at one directory again"
    )

    # Property 1: bounded, and explicitly not recursive.
    #
    # Bound the assertion to the CHILD ENUMERATION, not to the file. A first
    # draft accepted any "Select-Object -First" anywhere -- and the marker test
    # a few lines above uses "Select-Object -First 1" for its glob probe, so
    # deleting the real cap still passed. An assertion satisfied by an
    # unrelated line is decoration.
    idx = src.find('-Directory')
    assert idx != -1, "the immediate-child directory enumeration is gone"
    enum = src[idx:idx + 400]
    cap = re.search(r"Select-Object\s+-First\s+(\d+)", enum)
    assert cap and int(cap.group(1)) > 1, (
        "child-directory enumeration is unbounded; a folder with thousands of "
        "entries would stall -Detect. Found: %r" % enum[:200]
    )
    assert "-Recurse" not in src.split("Test-UabsProfileDetected")[-1][:2000], (
        "detection went recursive; that is slow on a large tree and matches "
        "markers inside vendored dependencies"
    )

    # Property 2: vendored trees are skipped by name.
    assert "UabsDetectSkipDirs" in src, (
        "the vendored-directory skip list is gone; detection will now match a "
        "dependency's markers, which is why the scan was root-only to begin with"
    )
    for vendor in ("node_modules", "vendor", ".venv"):
        assert vendor in src, (
            "%r is no longer skipped during detection; a marker inside it "
            "belongs to someone else's code" % vendor
        )

    # The reason has to survive, or the next reader re-narrows this. Read the
    # RAW file: ps_code() strips comments on purpose, so the explanation is
    # invisible to it -- and the explanation is exactly what is being pinned.
    raw = read(ROOT / "TOOLS" / "Set-McpProfile.ps1")
    assert "workspace" in raw.lower(), (
        "the comment explaining WHY detection looks one level down is gone; "
        "without it this reads as an accidental widening and gets reverted"
    )
    assert "327" in raw or "5,877" in raw or "45 mod" in raw, (
        "the measurement that motivated the change is gone from the source; "
        "'looks one level down' without the tree it was measured on is folklore"
    )

def test_a_machine_controlling_server_is_never_swept_by_calling_its_tools() -> None:
    """The capability sweep would have driven the operator's desktop.

    TOOLS/measure_mcp_capability.py calls EVERY tool a server advertises, with
    arguments synthesized from each tool's own schema. That is the right idea
    against a web API. windows-mcp advertises Click, Type, Shortcut, PowerShell,
    Registry, Clipboard, MultiEdit, Process, App and FileSystem.

    Its only protection was MUTATING_HINTS, a blocklist of name fragments --
    "create", "delete", "push", "merge" and friends. Every one of those is a verb
    a REST API would use. Not one of them matches `Click` or `Registry`, so the
    sweep sailed straight through, and this was measured on 2026-08-27 rather
    than reasoned about: the run called FileSystem, Snapshot, Scrape,
    DisplayInventory and Wait for real. FileSystem takes mode:enum and the
    synthesizer picks enum[0]. That happened to be "read". Had upstream listed
    the enum as ["write", "read", ...] the sweep would have written a file. The
    safety of that call rested on the ordering of somebody else's enum.

    So two things are pinned here:

    1. The refusal is driven by CATALOG data (`controls_machine`), not by
       guessing at spellings. A blocklist fails open on the name nobody
       predicted, which is exactly what happened, and this file already knows
       that -- the same script's environment handling was converted to an
       allowlist for the same reason.
    2. The refusal happens BEFORE any tool is called, and names the read-only
       tool that answers the same question.
    """
    src = read(ROOT / "TOOLS" / "measure_mcp_capability.py")

    assert "controls_machine" in src, (
        "the capability sweep no longer asks whether a server drives the "
        "machine; it will call Click, Type, PowerShell and Registry against a "
        "live desktop with synthesized arguments"
    )

    # The guard has to run before measure(), or it guards nothing.
    guard = src.index("if controls_machine(component_id)")
    call = src.index("record = measure(")
    assert guard < call, (
        "the desktop-control refusal runs after measure(); by then every tool "
        "has already been called"
    )

    # It must be a catalog lookup, not a name heuristic.
    assert "CATALOG.json" in src and 'component.get("controls_machine")' in src, (
        "controls_machine stopped being read from CATALOG.json -- a heuristic "
        "over tool names is the blocklist this replaced"
    )

    # And the catalog has to actually mark the one server that needs it.
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    win = [c for c in catalog["components"] if c["id"] == "windows-mcp"]
    assert win, "windows-mcp left the catalog"
    assert win[0].get("controls_machine") is True, (
        "windows-mcp is no longer flagged controls_machine, so the sweep will "
        "call Click, Type, PowerShell and Registry on the operator's desktop"
    )


def test_desktop_control_can_never_be_switched_on_by_detection() -> None:
    """-Auto must not be able to reach a profile that can type and run shells.

    Every other profile earns its place from a marker on disk: a pyproject.toml
    means code-intel is useful, ModOrganizer.ini means houseCARL is. There is no
    file whose presence is evidence that an operator wants an agent clicking
    their mouse, so the windows profile carries no markers at all and the
    reasoning is written down next to it -- without that note the empty block
    reads like an oversight and the next person helpfully fills it in.
    """
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    win = [p for p in profiles["profiles"] if p["id"] == "windows"]
    assert win, "the windows profile is gone"
    win = win[0]

    detect = win.get("detect") or {}
    for key in ("files", "globs", "json"):
        assert not detect.get(key), (
            "the windows profile grew a %s detection marker. -Auto would then "
            "enable keyboard, mouse, PowerShell and registry control because a "
            "directory looked a certain way." % key
        )
    assert win.get("detect_note"), (
        "the note explaining why detection is empty is gone; the next reader "
        "will treat the empty block as an omission and fill it in"
    )

    server = win["servers"][0]
    assert server["id"] == "windows-mcp"
    assert not server.get("key"), "windows-mcp must stay keyless"
    cost = server.get("measured_cost") or {}
    assert cost.get("schema_bytes") == 22088 and cost.get("tools") == 20, (
        "the windows-mcp cost figures changed without a re-measurement; run "
        "TOOLS/Measure-McpSchemaCost.ps1 -Command 'uvx windows-mcp@0.8.5 serve'"
    )
    # Pinned, for the reason every other npx/uvx entry here is pinned.
    assert any("@" in str(a) for a in server["args"]), (
        "windows-mcp lost its version pin; an unpinned uvx server can change "
        "its tool surface mid-session"
    )


def test_the_schema_cost_tool_does_not_send_a_byte_order_mark() -> None:
    """It spent seven releases sending a BOM no provider sends.

    Windows PowerShell 5.1 puts EF BB BF in front of the first frame written to
    a child's stdin, and windows-mcp's pydantic parser rejects the whole
    initialize message for it. Every server measured before it tolerated the BOM
    silently, which is why a tool whose entire job is speaking MCP the way a
    provider does went that long being wrong.

    The fix is specific and the specificity is the point: wrapping
    StandardInput.BaseStream in a BOM-less StreamWriter does NOT work, because
    reading .StandardInput builds .NET's own writer and sets AutoFlush, and
    Flush() emits the preamble before this script ever has a handle. That was
    tried first and measured still emitting EF BB BF. Console::InputEncoding is
    what that writer is constructed from, so it is the only lever early enough,
    and it has to be set before Process.Start.
    """
    src = ps_code(ROOT / "TOOLS" / "Measure-McpSchemaCost.ps1")

    # Match the ASSIGNMENT, not the property name. Matching the name alone is
    # satisfied by the line two above that only READS the previous value, so
    # deleting the fix left this assertion green and blew up on .index() with
    # "substring not found" instead of saying what broke. Caught by mutating it.
    setter = "[Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false"
    assert setter in src, (
        "the stdin BOM fix is gone; strict MCP servers will reject the "
        "initialize frame this tool sends"
    )
    enc = src.index(setter)
    start = src.index("[System.Diagnostics.Process]::Start($psi)")
    assert enc < start, (
        "Console::InputEncoding is set after Process.Start; the child's writer "
        "is already built by then and the BOM is already in the pipe"
    )
    assert "$prevConsoleIn" in src, (
        "the previous console encoding is not restored, so measuring a server "
        "changes the encoding for everything that runs after it in the session"
    )

    # The BaseStream dead end has to stay documented, in the comments, or it
    # gets re-attempted -- it is the obvious fix and it does not work.
    prose = read(ROOT / "TOOLS" / "Measure-McpSchemaCost.ps1")
    assert "BaseStream" in prose and "AutoFlush" in prose, (
        "the note explaining why the obvious BaseStream fix fails is gone; "
        "without it the next person tries it, sees clean-looking code, and "
        "ships the BOM back"
    )


def test_mcp_proofs_do_not_require_a_python_path_alias() -> None:
    """The AIO can own a working Python while `python` is absent from PATH.

    This happened on the maintainer machine after a successful all-provider
    install: Hermes and Skyrim Forge both had runnable venv interpreters, but
    `Test-McpHandshake.ps1` did `(Get-Command python -ErrorAction Stop)` and
    therefore failed before it sent one MCP frame. The full pack gate made the
    same assumption. A fresh winget Python install can also expose `py` before
    the current process sees a `python` PATH update.

    Resolve and execute a real interpreter once in the shared helper. The two
    proofs must use that helper rather than reintroducing launcher assumptions.
    """
    common = ps_code(ROOT / "TOOLS" / "UABS-Common.ps1")
    probe = ps_code(ROOT / "TOOLS" / "Test-McpHandshake.ps1")
    pack = ps_code(ROOT / "TESTS" / "Test-Pack.ps1")
    profile = ps_code(ROOT / "TOOLS" / "Set-McpProfile.ps1")
    writer = ps_code(ROOT / "TOOLS" / "UABS-Mcp-Write.ps1")

    assert "function Get-UabsPythonExecutable" in common
    for evidence in ("SKYRIM_FORGE_PYTHON", "Get-Command py", "hermes\\hermes-agent\\venv"):
        assert evidence in common, "shared Python resolver lost fallback: %s" % evidence
    assert "Get-UabsPythonExecutable" in probe and "Get-UabsPythonExecutable" in pack
    assert profile.index("UABS-Common.ps1") < profile.index("UABS-Mcp-Write.ps1"), (
        "profile routing does not load the shared Python resolver before its writer"
    )
    expand = writer.split("function Expand-UabsTemplate", 1)[1].split("\nfunction ", 1)[0]
    assert "Get-UabsPythonExecutable" in expand and "$out -ieq 'python'" in expand, (
        "profile commands again write a bare Python alias instead of the resolved executable"
    )
    assert "Get-Command python -ErrorAction Stop" not in probe, (
        "the live MCP proof again hard-requires a `python` PATH alias"
    )
    assert "\\s{4,6}-" in read(ROOT / "TOOLS" / "Test-McpHandshake.ps1"), (
        "the Hermes handshake reader accepts only the old six-space sequence "
        "indent; current ruamel config launches every MCP with no arguments"
    )
    handshake = read(ROOT / "TOOLS" / "Test-McpHandshake.ps1")
    assert "enabledProp" in handshake and "disabledProp" in handshake, (
        "the JSON handshake reader launches servers the provider marks disabled"
    )
    assert "enabledLine" in handshake and "Value -eq 'false'" in handshake, (
        "the TOML handshake reader launches servers the provider marks disabled"
    )


def test_versioned_online_tools_pin_the_same_version_offline() -> None:
    """OnlineLatest and Full-Offline must not install different releases."""
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    components = {c["id"]: c for c in catalog["components"]}

    headroom = components["headroom"]
    assert headroom["version"] in headroom["pip_spec"]
    assert headroom["version"] in headroom["offline_asset"]
    installer = ps_code(ROOT / "INSTALL-AIO.ps1")
    assert '$wheelSpec = ("{0}[mcp]" -f $asset)' in installer, (
        "the bundled Headroom wheel is installed without its MCP dependencies"
    )
    assert "Get-Command uv" in installer and "tool','install','--force" in installer, (
        "Headroom has no uv fallback when Windows exposes no base Python launcher"
    )
    assert installer.index("if ($uv)") < installer.index("pip install $asset"), (
        "pip is preferred over uv again, so a successful install can leave an older "
        "headroom.exe earlier on PATH"
    )
    assert "tool dir --bin" in installer and "$hrInstalled" in installer, (
        "the installer does not record the Headroom executable uv actually installed"
    )
    assert "Stop-UabsProcessUsingExecutable $activeHeadroom.Source" in installer, (
        "a running Headroom MCP can lock its own entrypoint and defeat the uv upgrade"
    )
    common = ps_code(ROOT / "TOOLS" / "UABS-Common.ps1")
    bootstrap = ps_code(ROOT / "TOOLS" / "Ensure-Provider-CLIs.ps1")
    assert "function Refresh-ProcessPath" in common, (
        "Headroom calls Refresh-ProcessPath but the shared installer scope does not define it"
    )
    assert "function Refresh-ProcessPath" not in bootstrap, (
        "the PATH refresh helper drifted back into one caller instead of shared scope"
    )

    codeburn = components["codeburn"]
    assert codeburn["version"] in codeburn["npm_spec"], (
        "CodeBurn's catalog version does not constrain the npm install"
    )
    assert codeburn["npm_integrity"] == (
        "sha512-0/u52Lg8hjGy18vDEZrQgPT91EyOsVa8LkLCLOkYiM+YbuWITgon2Qsrt2i9A4JEuw2gyz0YLD6w8NwNdPBaJA=="
    )
    assert codeburn["npm_args"] == ["--ignore-scripts"]


def test_github_auth_guidance_matches_the_official_oauth_binary() -> None:
    """The official binary no longer requires a PAT on github.com."""
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    github = next(c for c in catalog["components"] if c["id"] == "github-mcp-server")
    note = github["scope_note"].lower()
    writer = read(ROOT / "TOOLS" / "Add-Reasoning-MCPs.ps1")

    assert github.get("api_key_optional") is True
    assert github.get("auth_mode") == "built-in-oauth-or-optional-pat"
    assert "no pat is required" in note and "browser authorization" in note
    assert "both servers work without one, with lower limits" not in writer
    assert "opens browser oauth" in writer.lower(), (
        "the installer no longer tells a keyless user how official GitHub OAuth starts"
    )


def test_fresh_codex_home_exists_before_instruction_copy() -> None:
    """Codex skills live outside CODEX_HOME, so they cannot create it for us."""
    src = ps_code(ROOT / "INSTALL-AIO.ps1")
    loop = re.search(
        r"\$providerHome\s*=\s*Get-UabsProviderHome.*?"
        r"New-Item\s+-ItemType\s+Directory\s+-Force\s+-Path\s+\$providerHome.*?"
        r"\$instructionTarget\s*=\s*Join-Path\s+\$providerHome",
        src,
        re.S,
    )
    assert loop, (
        "the provider home is not created before fresh-install instructions; "
        "Codex fails because its skills are written to ~/.agents instead"
    )


def test_profile_repair_and_frontend_detection_are_default() -> None:
    """Installer reruns repair owned scopes without enabling browser tools for any Node repo."""
    installer = ps_code(ROOT / "INSTALL-AIO.ps1")
    profiles = json.loads(read(ROOT / "BUNDLED-TOOLS" / "PROFILES.json"))
    writer = ps_code(ROOT / "TOOLS" / "Set-McpProfile.ps1")
    web = next(p for p in profiles["profiles"] if p["id"] == "web")

    assert "& $mcpProfile -Repair" in installer
    assert installer.index("& $mcpProfile -Repair") < installer.index("& $mcpProfile -Auto")
    assert "ParameterSetName = 'Repair'" in writer and "& $PSCommandPath @invoke" in writer
    assert "Providers = @($job.Providers)" in writer
    assert "Test-UabsServerDeclared -Path $target.Path" in writer
    assert "package.json" not in web["detect"].get("files", [])
    probes = web["detect"].get("json_has_any", [])
    names = {name for probe in probes for name in probe.get("names", [])}
    assert {"vite", "react", "vue", "svelte"} <= names
    assert "json_has_any" in writer
    assert "IsNullOrWhiteSpace([string]$_)" in installer, (
        "a global-only profile prints a fake blank project in the install summary"
    )


def test_new_creative_skills_are_pinned_and_single_writer() -> None:
    """Image-to-3D and UI craft keep immutable provenance and one bundle writer."""
    catalog = json.loads(read(ROOT / "BUNDLED-TOOLS" / "CATALOG.json"))
    impeccable = next(c for c in catalog["components"] if c["id"] == "impeccable")
    installer = ps_code(ROOT / "INSTALL-AIO.ps1")
    notices = read(CANON / "THIRD-PARTY-NOTICES.md")
    img_skill = read(CANON / "img2threejs" / "SKILL.md")
    img_wrapper = ps_code(CANON / "img2threejs" / "scripts" / "uabs-python.ps1")
    vision_project = read(CANON / "img2threejs" / "integrations" / "vision" / "pyproject.toml")
    vision_lock = read(CANON / "img2threejs" / "integrations" / "vision" / "uv.lock")
    node_root = CANON / "img2threejs" / "integrations" / "glb_character_pipeline" / "node"
    node_package = json.loads(read(node_root / "package.json"))
    node_lock = json.loads(read(node_root / "package-lock.json"))
    ui_skill = read(CANON / "impeccable" / "SKILL.md")

    assert "dede5909be4e494b228c801a55dda47439143932" in notices
    assert re.search(r"(?m)^version:\s*1\.5\.1\s*$", img_skill)
    assert "PYTHONUTF8" in img_wrapper and "must be inside" in img_wrapper
    assert "PYTHONDONTWRITEBYTECODE" in img_wrapper, (
        "img2threejs wrapper can leave __pycache__ inside every installed skill tree"
    )
    assert '"transformers>=5.16.1,<6"' in vision_project
    assert re.search(r'(?m)^name = "transformers"\nversion = "5\.16\.1"$', vision_lock)
    assert node_package["devDependencies"]["esbuild"] == "0.28.2"
    assert node_lock["packages"]["node_modules/esbuild"]["version"] == "0.28.2"
    assert impeccable["version"] == "3.6.1" and impeccable["skill_version"] == "4.1.3"
    assert impeccable["skill_asset_sha256"] == "fdcb41a24ddfb613786e3141bc7bb8466a406ffbd437a2e302f4ca70181bed9f"
    assert impeccable["npm_integrity"].startswith("sha512-")
    assert impeccable["npm_args"] == ["--omit=optional", "--ignore-scripts"]
    assert "view $comp.npm_spec dist.integrity" in installer and "blocked-integrity" in installer
    assert re.search(r"(?m)^\s+version:\s*4\.1\.3\s*$", ui_skill)
    assert not (CANON / "impeccable" / "scripts" / "pin.mjs").exists()
    routing = read(CANON / "impeccable" / "reference" / "routing.md")
    assert "scripts/detect.mjs --json" in routing and "no network, no npx" in routing


def test_skill_discovery_is_search_only() -> None:
    """The catalog finder can discover candidates but cannot mutate managed skill homes."""
    skill = read(CANON / "skill-discovery" / "SKILL.md")
    wrapper = ps_code(CANON / "skill-discovery" / "scripts" / "find-skills.ps1")
    assert "skills@1.5.23" in wrapper and "'find'" in wrapper
    assert "DISABLE_TELEMETRY" in wrapper and "DO_NOT_TRACK" in wrapper
    assert not re.search(r"['\"](?:add|update|remove|experimental_sync)['\"]", wrapper)
    for command in ("skills add", "skills update", "skills remove", "skills experimental_sync"):
        assert command in skill, f"discovery skill does not forbid {command}"


def test_outdated_hermes_npm_duplicates_are_removed_only_after_current_install() -> None:
    """A successful update must not leave its former Hermes-private copy behind."""
    installer = ps_code(ROOT / "INSTALL-AIO.ps1")
    start = installer.index("function Remove-UabsOutdatedHermesNpmDuplicate")
    end = installer.index("function Remove-UabsGlobalMcpRegistration", start)
    repair = installer[start:end]

    assert "Get-UabsNpxPackageBase" in repair
    assert "$activeVersion -ne $expectedVersion" in repair
    assert "([version]$legacyVersion) -ge ([version]$activeVersion)" in repair, (
        "the repair can remove an equal or newer Hermes-private package"
    )
    assert "[StringComparison]::OrdinalIgnoreCase" in repair, (
        "the repair can mistake the active Hermes npm root for another Windows path"
    )
    assert "'uninstall', '-g', $packageName" in repair

    branch = installer.split("'npx-or-npm'", 1)[1].split("'pip-or-wheel'", 1)[0]
    installed = branch.index("if (Invoke-UabsNative $npm.Source $npmArgs)")
    cleanup = branch.index("Remove-UabsOutdatedHermesNpmDuplicate")
    assert installed < cleanup, "legacy cleanup runs before the exact current package exists"


def test_batch_launchers_drop_incompatible_powershell_module_roots() -> None:
    """A cmd boundary must not feed PowerShell 7 modules to Windows PowerShell."""
    batches = sorted(ROOT.glob("*.bat")) + sorted(FORGE_SOURCE.rglob("*.bat"))
    launchers = []
    for path in batches:
        text = read(path)
        match = re.search(r"(?im)^.*\bpowershell(?:\.exe)?\b.*$", text)
        if not match:
            continue
        launchers.append(path)
        prefix = text[: match.start()]
        assert re.search(r'(?im)^\s*set\s+"PSModulePath="\s*$', prefix), (
            "%s launches Windows PowerShell with an inherited module path; "
            "PowerShell 7/Codex can shadow Microsoft.PowerShell.Utility and "
            "remove Get-FileHash" % path.relative_to(ROOT).as_posix()
        )
    assert launchers, "no shipped batch-to-PowerShell launchers were checked"


def test_pack_gate_does_not_write_persistent_environment() -> None:
    gate = read(ROOT / "TESTS" / "Test-Pack.ps1")
    assert not re.search(r"SetEnvironmentVariable\(\s*['\"]HOUSECARL_MCP", gate), (
        "the pack gate writes the user's persistent houseCARL environment"
    )
    assert "$env:HOUSECARL_MCP = $liveExe" in gate, (
        "the houseCARL resolver fixture is no longer isolated to the test process"
    )
    assert not re.search(r"&\s+python(?:\.exe)?\b", gate, re.IGNORECASE), (
        "the pack gate bypasses Get-UabsPythonExecutable and requires bare python on PATH"
    )

if __name__ == "__main__":
    raise SystemExit(main())
