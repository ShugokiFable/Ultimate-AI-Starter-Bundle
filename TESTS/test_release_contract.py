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
import sys
import zipfile
import hashlib
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANON = ROOT / "_V7-CANONICAL-SKILLS"
PROVIDERS = ("Claude", "Codex", "Grok", "Hermes", "Kimi")

VERSION = (ROOT / "VERSION.txt").read_text(encoding="utf-8-sig").strip()   # v7.9.0
BARE = VERSION.lstrip("vV")                                               # 7.9.0


def forge_asset() -> Path:
    """The one bundled Forge payload. Its version is data, not a literal."""
    hits = sorted((ROOT / "BUNDLED-TOOLS" / "offline").glob("Skyrim-Forge-*.zip"))
    assert len(hits) == 1, f"expected exactly one bundled Forge payload, found {[p.name for p in hits]}"
    return hits[0]

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
    assert VERSION.lower() in compat
    assert "set \"exitcode=%errorlevel%\"" in compat
    assert "exit /b %exitcode%" in compat
    assert "skyrim ai v5" not in compat

    ps = read(ROOT / "INSTALL-V7-AIO.ps1")
    assert VERSION in ps
    doctor = "Test-Installed-State.ps1"
    assert doctor in ps, "final install-state doctor is not invoked"
    assert ps.index(doctor) < ps.index('INSTALL COMPLETE'), "doctor must run before success banner"
    assert "Optional Forge" not in ps, "Forge still presented as manual optional next step"
    assert "Skyrim-Forge-*.zip" in ps, "installer no longer discovers the Forge payload"
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

def test_forge_payload() -> None:
    zpath = forge_asset()
    stem = zpath.stem                       # Skyrim-Forge-x.y.z
    forge_version = stem[len("Skyrim-Forge-"):]
    with zipfile.ZipFile(zpath) as z:
        assert z.testzip() is None, "Forge ZIP CRC failure"
        names = set(z.namelist())
        assert f"{stem}/skyrim_forge/bundle_contract.py" in names, "Forge archive root does not match its filename"
        contract = z.read(f"{stem}/skyrim_forge/bundle_contract.py").decode("utf-8")
        # Forge must actually accept THIS bundle, not some remembered range.
        low = re.search(r"MIN_BUNDLE = \((\d+), (\d+), (\d+)\)", contract)
        high = re.search(r"MAX_BUNDLE_EXCLUSIVE = \((\d+), (\d+), (\d+)\)", contract)
        assert low and high, "Forge bundle contract no longer declares a supported range"
        mine = tuple(int(x) for x in BARE.split("."))
        assert tuple(int(x) for x in low.groups()) <= mine < tuple(int(x) for x in high.groups()), (
            f"bundled Forge {forge_version} does not accept bundle {BARE}"
        )
        version_txt = z.read(f"{stem}/VERSION.txt").decode("utf-8")
        assert f"Skyrim Forge {forge_version}" in version_txt, "Forge archive name and VERSION.txt disagree"



def test_offline_manifest_complete() -> None:
    m = json.loads(read(ROOT / "BUNDLED-TOOLS" / "OFFLINE-MANIFEST.json"))
    assert m.get("pack_version") == BARE, "offline manifest pack version drifted"
    declared = {a["file"] for a in m.get("assets", [])}
    actual = {p.name for p in (ROOT / "BUNDLED-TOOLS" / "offline").iterdir() if p.is_file()}
    assert declared == actual, f"offline manifest coverage mismatch declared-only={sorted(declared-actual)} actual-only={sorted(actual-declared)}"
    assert forge_asset().name in declared
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
    assert "_required_forge" in text, "Core builder no longer pins a required Forge payload"
    assert "required Forge" in text or "required forge" in text.lower(), "Core artifact does not explain retained Forge payload"

    # A Core archive intentionally omits most BUNDLED-TOOLS/offline payloads,
    # so it cannot ship the Full tree's MANIFEST.json unchanged. Prove the
    # builder rewrites the Core manifest to describe only what it actually
    # ships while retaining the mandatory Forge payload.
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
                {"file": forge_asset().name, "size": 5, "sha256": hashlib.sha256(b"forge").hexdigest()},
                {"file": "optional-tool.zip", "size": 8, "sha256": hashlib.sha256(b"optional").hexdigest()},
            ],
        }
        required = {
            "START-HERE.bat": b"@echo off\r\n",
            "INSTALL-V7-AIO.ps1": b"# aio\n",
            "BUNDLED-TOOLS/CATALOG.json": b"{}\n",
            "BUNDLED-TOOLS/OFFLINE-MANIFEST.json": (json.dumps(offline_inventory, indent=2) + "\n").encode("utf-8"),
            "VERSION.txt": VERSION.encode("utf-8") + b"\n",
            f"BUNDLED-TOOLS/offline/{forge_asset().name}": b"forge",
            "BUNDLED-TOOLS/offline/optional-tool.zip": b"optional",
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
            assert f"BUNDLED-TOOLS/offline/{forge_asset().name}" in core_paths
            assert "BUNDLED-TOOLS/offline/optional-tool.zip" not in core_paths, "Core ships a Full-only manifest row"
            assert prefix + "BUNDLED-TOOLS/offline/optional-tool.zip" not in z.namelist()

            core_offline = json.loads(z.read(prefix + "BUNDLED-TOOLS/OFFLINE-MANIFEST.json"))
            declared = {a["file"] for a in core_offline["assets"]}
            assert declared == {forge_asset().name}, f"Core offline inventory describes files it does not ship: {declared}"
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
    shipped = forge_asset().stem[len("Skyrim-Forge-"):]
    assert shipped in readme and "bundle" in readme, f"README does not describe bundle-managed Forge {shipped}"
    for stale in ("skyrim forge** is not redistributed", "install it yourself", "### not bundled"):
        assert stale not in readme, f"README contradicts bundle-managed Forge with stale instruction: {stale}"



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

    provider = read(ROOT / "TOOLS" / "Ensure-Provider-CLIs.ps1")
    assert "System.Text.UTF8Encoding" in provider, "provider bootstrap should use an explicit System.Text encoder type"


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
    assert forge.get("offline_asset") == forge_asset().name
    assert forge.get("install") != "manual-user-product"


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
    code = re.sub(r"(?s)<#.*?#>", "", text)
    code = "\n".join(l for l in code.split("\n") if not l.strip().startswith("#"))
    assert not re.search(r"Skyrim-Forge-\d+\.\d+", code), "installer code restates a Forge version"
    assert "Refusing a version-stamped Forge install directory" in code, "installer does not refuse a stamped root"
    assert "-ResolveOnly" in text, "install root resolution is not independently testable"
    assert (ROOT / "TESTS" / "Test-ForgeRootResolution.ps1").is_file(), "root resolution gate is missing"


def test_forge_contract_check_reads_a_field_forge_emits() -> None:
    """7.8.0 tested `$contract.compatible`, which Forge has never emitted.

    `-not $null` is always true, so the installer threw
    'Forge reports incompatible bundle contract' on every run and the AIO
    aborted the whole install on the non-zero exit. A fresh Windows install of
    7.8.0 could not complete. Nothing caught it because no test read the two
    files together.
    """
    installer = read(ROOT / "TOOLS" / "Install-SkyrimForge.ps1")
    checked = set(re.findall(r"\$contract\.([A-Za-z_][A-Za-z0-9_]*)", installer))
    assert checked, "installer no longer inspects the bundle contract at all"
    with zipfile.ZipFile(forge_asset()) as z:
        stem = forge_asset().stem
        contract_src = z.read(f"{stem}/skyrim_forge/bundle_contract.py").decode("utf-8")
    emitted = set(re.findall(r'^\s+"([a-z_]+)":', contract_src, re.M))
    unknown = sorted(f for f in checked if f not in emitted)
    assert not unknown, f"installer reads contract field(s) Forge never emits: {unknown} (emitted: {sorted(emitted)})"


def test_no_skill_documents_an_unshipped_product() -> None:
    """skyrim-forge-bridge described a 0.2.x product that no longer exists.

    It told the agent Forge cannot write ESP records -- false for the shipped
    5.2 -- and shipped a script hardcoded to a personal Documents\\Apps path.
    A skill that contradicts the tool actually installed is worse than no
    skill: the agent believes it.
    """
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
    common = read(ROOT / "TOOLS" / "V7-Common.ps1")
    defined = set(re.findall(r"^function\s+([A-Za-z][A-Za-z0-9-]*)", common, re.M))
    assert "Get-V5PackRoot" in defined, "V7-Common.ps1 no longer parses as expected"

    verbs = ("Get|Set|New|Add|Remove|Test|Install|Restore|Repair|Invoke|Update"
             "|Copy|Save|Expand|Resolve|Find|Write|Convert|Import|Export")
    # Call position only. A helper name inside a comment or a quoted string is
    # prose or a pattern, not an invocation: Test-V7-Pack.ps1 legitimately
    # asserts that the AIO does NOT contain "Invoke-V5SkillDedupe -Provider
    # 'Grok'", and V7-Common.ps1 names a retired helper in a comment. Flagging
    # those would make the gate lie, and a lying gate gets switched off.
    call = re.compile(r"(?<![\w\"'`-])((?:" + verbs + r")-V5[A-Za-z0-9]*)(?![\w\"'-])")

    missing = []
    for folder in ("TOOLS", "TESTS"):
        for p in sorted((ROOT / folder).glob("*.ps1")):
            text = read(p)
            if "V7-Common.ps1" not in text:
                continue
            code = re.sub(r"(?s)<#.*?#>", "", text)          # <# block comments #>
            code = "\n".join(re.sub(r"#.*$", "", line) for line in code.split("\n"))
            local = set(re.findall(r"^\s*function\s+([A-Za-z][A-Za-z0-9-]*)", text, re.M))
            for name in sorted(set(call.findall(code))):
                if name not in defined and name not in local:
                    missing.append(f"{p.relative_to(ROOT).as_posix()} calls {name}")
    assert not missing, "undefined V7-Common helper(s): " + "; ".join(sorted(missing))


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
        test_forge_payload,
        test_offline_manifest_complete,
        test_manifest_generator_excludes_developer_state,
        test_release_builder_contract,
        test_current_forge_docs_contract,
        test_ps51_utf8_reads_are_explicit,
        test_windows_ci_and_ps51_static_contract,
        test_version_sources,
        test_forge_install_directory_is_never_version_stamped,
        test_forge_contract_check_reads_a_field_forge_emits,
        test_no_skill_documents_an_unshipped_product,
        test_no_skill_script_hardcodes_a_machine_path,
        test_every_v5_helper_called_actually_exists,
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


if __name__ == "__main__":
    raise SystemExit(main())
