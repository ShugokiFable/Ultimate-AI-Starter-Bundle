from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "writer" / "native-go"
TARGETS = {
    "linux": (ROOT / "writer" / "published" / "linux-x64" / "SkyrimForge.Native", {"CGO_ENABLED":"0","GOOS":"linux","GOARCH":"amd64"}),
    "windows": (ROOT / "writer" / "published" / "win-x64" / "SkyrimForge.Native.exe", {"CGO_ENABLED":"0","GOOS":"windows","GOARCH":"amd64"}),
}
PACKAGE_TARGETS = {
    "linux": ROOT / "skyrim_forge" / "bin" / "linux-x64" / "SkyrimForge.Native",
    "windows": ROOT / "skyrim_forge" / "bin" / "win-x64" / "SkyrimForge.Native.exe",
}
GO = os.environ.get("SKYRIM_FORGE_GO") or shutil.which("go") or "go"


def pinned_toolchain() -> str:
    """The Go version CI builds with, read from the workflow rather than copied.

    The published binaries only reproduce under one toolchain. CI pins
    go-version 1.23.2 with GOTOOLCHAIN=local; a maintainer whose PATH happens to
    hold a newer Go used to produce different bytes here and see the repository
    validator report the *shipped* binaries as irreproducible -- the opposite of
    what had happened. Rebuilding then broke CI. Verified: building 5.1.3 under
    go1.23.2 reproduces the published SHA-256 exactly, while go1.26.5 does not.

    GOTOOLCHAIN makes the local `go` fetch and use that exact version, so the
    result matches CI regardless of what is installed.
    """
    workflow = None
    for parent in (ROOT, *ROOT.parents):
        candidate = parent / ".github" / "workflows" / "ci.yml"
        if candidate.is_file():
            workflow = candidate
            break
    if workflow is None:
        raise SystemExit("no repository-root .github/workflows/ci.yml found")
    versions = re.findall(r'go-version:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)?)"',
                          workflow.read_text(encoding="utf-8"))
    if not versions:
        raise SystemExit("no go-version pin found in .github/workflows/ci.yml")
    if len(set(versions)) != 1:
        raise SystemExit(f"ci.yml pins conflicting Go versions: {sorted(set(versions))}")
    return "go" + versions[0]


TOOLCHAIN = pinned_toolchain()


def build(target: str) -> None:
    output, environment = TARGETS[target]
    output.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy(); env.update(environment)
    # Pin the toolchain, not just the flags. Reproducibility here is per-Go-version.
    env["GOTOOLCHAIN"] = TOOLCHAIN
    command = [GO, "build", "-trimpath", "-buildvcs=false", "-ldflags=-s -w -buildid=", "-o", str(output), "."]
    subprocess.run(command, cwd=SOURCE, env=env, check=True)
    package = PACKAGE_TARGETS[target]
    package.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(output, package)


def main() -> int:
    parser = argparse.ArgumentParser(description="Rebuild deterministic Skyrim Forge native helpers")
    parser.add_argument("--target", choices=["all", *TARGETS], default="all")
    args = parser.parse_args()
    selected = TARGETS if args.target == "all" else [args.target]
    for target in selected:
        build(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
