r"""Generate BUNDLED-TOOLS/RETIRED-SKILLS.json from this repository's own history.

The installer copies the canonical tree into every provider's skills directory.
It has never removed a skill that the pack STOPPED shipping, so a machine
installed against v7 still carries the v7 names forever. Measured on the
maintainer's machine at v8.2.0: seven retired skills present in three provider
trees, twenty-one directories, every one of them loaded and offered to the agent
alongside the skill that replaced it.

That is worse than clutter. `skyrim-kid-distribution` and `kid-authoring` both
claim to own KID syntax, and the retired one documents the older dialect.

The retired set is derived rather than hand-maintained: every directory name
that has ever existed under a canonical skills tree, minus the names that exist
now. Hand-maintaining it would drift the first time someone renamed a skill and
forgot, which is exactly the failure being fixed.

    python TOOLS/generate_retired_skills.py

CI cannot rely on full history (checkout may be shallow), so the RESULT is
committed and a contract checks it against the current tree; the generator is
only re-run when a skill is renamed or removed.
"""
from __future__ import annotations

import io
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANON = os.path.join(ROOT, "_CANONICAL-SKILLS")
OUT = os.path.join(ROOT, "BUNDLED-TOOLS", "RETIRED-SKILLS.json")

# Canonical tree has been renamed across major versions; history spans all of
# them, and a name retired under the old root is just as stale today.
TREES = ("_CANONICAL-SKILLS", "_V7-CANONICAL-SKILLS", "_V5-CANONICAL-SKILLS")

# Replacement is stated where one exists, so the removal notice can say what to
# use instead rather than only what is going away.
SUCCESSORS = {
    "skyrim-kid-distribution": "kid-authoring",
    "skyrim-spid-distribution": "spid-authoring",
    "skyrim-archive": "skyrim-assets-pbr",
    "skyrim-esp": "skyrim-plugin-authoring",
    "skyrim-mcm": "skyrim-papyrus-modding",
    "skyrim-papyrus": "skyrim-papyrus-modding",
    "skyrim-skse": "skse-plugin-authoring",
    "skyrim-forge-bridge": "skyrim-forge",
}

# Skills this pack never SHIPPED but now supersedes. The mega-pack was copied
# onto machines by hand and lived in every provider tree while existing in no
# repository; its 73 skills are consolidated into the routers below. On a machine
# that has both, the loose copy competes with the skill that absorbed it -- so the
# derived history list cannot see them and they are declared instead.
#
# Deliberately absent: saints-row-modding and roblox-game-development (now shipped
# canonically, so removing them would delete a live skill) and autonomous-ai-agents
# (a Hermes CATEGORY directory holding Hermes' own docs, not ours to remove).
ABSORBED = {
    'arma3-modding': 'game-modding',
    'baldurs-gate3-modding': 'game-modding',
    'bannerlord-modding': 'game-modding',
    'barotrauma-modding': 'game-modding',
    'beamng-modding': 'game-modding',
    'cities-skylines2-modding': 'game-modding',
    'ck3-modding': 'paradox-modding',
    'cyberpunk2077-modding': 'game-modding',
    'dayz-modding': 'game-modding',
    'divinity-original-sin2-modding': 'game-modding',
    'dont-starve-together-modding': 'game-modding',
    'dotnet-harmony-patching': 'unity-mod-frameworks',
    'eu4-modding': 'paradox-modding',
    'factorio-modding': 'game-modding',
    'fallout4-modding': 'bethesda-creation-modding',
    'game-mod-assets': 'game-modding',
    'game-mod-code-review': 'game-modding',
    'game-mod-crash-diagnostics': 'game-modding',
    'game-mod-development': 'game-modding',
    'game-mod-facts': 'game-modding',
    'game-mod-load-order-compatibility': 'game-modding',
    'game-mod-memory': 'game-modding',
    'game-mod-native-plugin': 'game-modding',
    'game-mod-packaging': 'game-modding',
    'game-mod-performance-profiling': 'game-modding',
    'game-mod-reworking': 'game-modding',
    'game-mod-runtime-patching': 'game-modding',
    'game-mod-ship-gate': 'game-modding',
    'game-mod-tool-router': 'game-modding',
    'game-mod-unknown-game-fallback': 'game-modding',
    'game-mod-versioned-workspace': 'game-modding',
    'garrys-mod-modding': 'game-modding',
    'hoi4-modding': 'paradox-modding',
    'kerbal-space-program-modding': 'unity-mod-frameworks',
    'lethal-company-modding': 'unity-mod-frameworks',
    'local-ai-tooling-ops': 'mcp-server-diagnostics',
    'minecraft-content-datagen-worldgen': 'minecraft-modding',
    'minecraft-data-components-attachments': 'minecraft-modding',
    'minecraft-fabric-quilt-modding': 'minecraft-modding',
    'minecraft-forge-neoforge-modding': 'minecraft-modding',
    'minecraft-java-game-modding': 'minecraft-modding',
    'minecraft-java-modding': 'minecraft-modding',
    'minecraft-library-api-integrations': 'minecraft-modding',
    'minecraft-mixins-access-control': 'minecraft-modding',
    'minecraft-modpack-scripting': 'minecraft-modding',
    'minecraft-multiloader-architectury': 'minecraft-modding',
    'minecraft-networking-persistence': 'minecraft-modding',
    'minecraft-rendering-animation': 'minecraft-modding',
    'minecraft-testing-porting-release': 'minecraft-modding',
    'no-mans-sky-modding': 'game-modding',
    'noita-modding': 'game-modding',
    'oxygen-not-included-modding': 'unity-mod-frameworks',
    'palworld-modding': 'unreal-mod-frameworks',
    'paradox-clausewitz-jomini-modding': 'paradox-modding',
    'project-zomboid-modding': 'game-modding',
    'repo-release-sweep': 'release-checklist',
    'rimworld-harmony-modding': 'unity-mod-frameworks',
    'risk-of-rain2-modding': 'unity-mod-frameworks',
    'roblox-docs': 'roblox-game-development',
    'satisfactory-sml-modding': 'unreal-mod-frameworks',
    'slay-the-spire-modding': 'game-modding',
    'space-engineers-modding': 'game-modding',
    'stardew-valley-modding': 'unity-mod-frameworks',
    'starfield-modding': 'bethesda-creation-modding',
    'stellaris-modding': 'paradox-modding',
    'subnautica-nautilus-modding': 'unity-mod-frameworks',
    'terraria-tmodloader-modding': 'game-modding',
    'unity-bepinex-harmony': 'unity-mod-frameworks',
    'unreal-ue4ss-modding': 'unreal-mod-frameworks',
    'valheim-jotunn-modding': 'unity-mod-frameworks',
    'victoria3-modding': 'paradox-modding',
    'witcher3-redkit-modding': 'game-modding',
    'xcom2-modding': 'unreal-mod-frameworks',
}


def git(*args: str) -> str:
    proc = subprocess.run(["git"] + list(args), cwd=ROOT,
                          capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit("git %s failed: %s" % (" ".join(args), proc.stderr.strip()))
    return proc.stdout


def main() -> int:
    ever: set[str] = set()
    log = git("log", "--all", "--name-only", "--pretty=format:",
              "--diff-filter=AMD", "--", *TREES)
    for line in log.splitlines():
        line = line.strip().replace("\\", "/")
        if "/" not in line:
            continue
        parts = line.split("/")
        if len(parts) >= 2 and parts[0] in TREES:
            ever.add(parts[1])

    current = {d for d in os.listdir(CANON)
               if os.path.isdir(os.path.join(CANON, d))}
    # Derived history plus declared absorptions; both are stale on a machine.
    retired = sorted((ever | set(ABSORBED)) - current)

    # A name that is both retired and current is a contradiction; guard rather
    # than emit a list that would delete a shipped skill.
    for name in retired:
        assert name not in current, name

    unknown = [n for n in retired if n not in SUCCESSORS and n not in ABSORBED]
    if unknown:
        print("NOTE: no successor recorded for: %s" % ", ".join(unknown))

    payload = {
        "schema": 1,
        "generated_by": "TOOLS/generate_retired_skills.py",
        "why": (
            "Skills this pack used to ship and no longer does, plus skills it "
            "ABSORBED that were never shipped from here. The installer "
            "copies the canonical tree in but never removed what left it, so a "
            "machine installed against an older version kept loading the "
            "superseded skill next to its replacement -- two skills claiming "
            "the same domain, the retired one documenting the older dialect."
        ),
        "current_skill_count": len(current),
        "retired": [
            {"name": n, "superseded_by": SUCCESSORS.get(n) or ABSORBED.get(n)}
            for n in retired
        ],
    }
    text = json.dumps(payload, indent=2, ensure_ascii=True) + "\n"
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(text)
    print("%d current skills, %d retired -> %s"
          % (len(current), len(retired), os.path.relpath(OUT, ROOT)))
    for entry in payload["retired"]:
        print("  %-28s -> %s" % (entry["name"], entry["superseded_by"] or "(no successor)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
