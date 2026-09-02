#!/usr/bin/env python3
"""Report version drift for pinned catalog components without changing files."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "BUNDLED-TOOLS" / "CATALOG.json"
VERSION_RE = re.compile(r"(?<!\d)(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)")


def versioned_package(spec: str | None) -> str | None:
    if not spec:
        return None
    text = str(spec).strip()
    split = text.rfind("@")
    if split <= 0 or not text[split + 1 : split + 2].isdigit():
        return None
    return text[:split]


def version_source(component: dict) -> tuple[str, str] | None:
    """Derive the registry from the install command already used as truth."""
    install = str(component.get("install") or "")
    if install == "bundle-source" or not component.get("version"):
        return None

    npm = versioned_package(component.get("npm_spec"))
    if not npm and ("npx" in install or "npm" in install):
        npm = next((versioned_package(x) for x in component.get("npx_args", [])
                    if versioned_package(x)), None)
    if npm:
        return "npm", npm

    pip_spec = str(component.get("pip_spec") or "")
    pip = re.match(r"^([A-Za-z0-9._-]+)(?:\[[^]]+\])?==", pip_spec)
    if pip:
        return "pypi", pip.group(1)

    if install == "mcp-uvx":
        package = next((versioned_package(x) for x in component.get("npx_args", [])
                        if versioned_package(x)), None)
        if package:
            return "pypi", package

    if install == "uv-tool":
        command = str(component.get("install_command") or "")
        match = re.search(r"\buv\s+tool\s+install\b(.*)$", command)
        if match:
            candidates = [x for x in shlex.split(match.group(1), posix=False)
                          if not x.startswith("-")]
            if candidates:
                package = candidates[-1].split("==", 1)[0]
                return "pypi", package

    github = component.get("github")
    if github and github.get("owner") and github.get("repo"):
        return "github", f"{github['owner']}/{github['repo']}"
    return None


def get_json(url: str, timeout: int) -> dict:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Ultimate-AI-Starter-Bundle-catalog-audit"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def latest_version(source: tuple[str, str], timeout: int) -> str:
    kind, name = source
    encoded = urllib.parse.quote(name, safe="")
    if kind == "npm":
        return str(get_json(f"https://registry.npmjs.org/{encoded}/latest", timeout)["version"])
    if kind == "pypi":
        return str(get_json(f"https://pypi.org/pypi/{encoded}/json", timeout)["info"]["version"])
    if kind == "github":
        tag = str(get_json(f"https://api.github.com/repos/{name}/releases/latest", timeout)["tag_name"])
        match = VERSION_RE.search(tag)
        if not match:
            raise ValueError(f"latest GitHub tag has no semantic version: {tag!r}")
        return match.group(1)
    raise ValueError(f"unknown version source: {kind}")


def version_targets(component: dict) -> list[tuple[str, str, tuple[str, str] | None]]:
    targets = [(str(component.get("id")), str(component.get("version")), version_source(component))]
    github = component.get("github") or {}
    if component.get("skill_version") and github.get("owner") and github.get("repo"):
        targets.append((f"{component.get('id')}:skill", str(component["skill_version"]),
                        ("github", f"{github['owner']}/{github['repo']}")))
    return targets


def audit(catalog: dict, timeout: int) -> list[dict]:
    results = []
    for component in catalog.get("components", []):
        pinned = component.get("version")
        if not pinned or component.get("install") == "bundle-source":
            continue
        for target_id, target_pin, source in version_targets(component):
            if not source:
                results.append({"id": target_id, "pinned": target_pin,
                                "status": "skipped", "error": "no deterministic version source"})
                continue
            try:
                latest = latest_version(source, timeout)
                results.append({
                    "id": target_id,
                    "pinned": target_pin,
                    "latest": latest,
                    "source": f"{source[0]}:{source[1]}",
                    "status": "current" if target_pin == latest else "stale",
                })
            except Exception as exc:  # one unavailable registry must not hide the rest
                results.append({"id": target_id, "pinned": target_pin,
                                "source": f"{source[0]}:{source[1]}",
                                "status": "error", "error": str(exc)})
    return results


def self_test() -> None:
    assert versioned_package("@playwright/mcp@0.0.80") == "@playwright/mcp"
    assert versioned_package("codeburn@0.9.23") == "codeburn"
    assert versioned_package("@latest") is None
    assert version_source({"install": "mcp-npx", "version": "1.2.3",
                           "npx_args": ["-y", "@scope/tool@1.2.3"]}) == ("npm", "@scope/tool")
    assert version_source({"install": "pip-or-wheel", "version": "1.2.3",
                           "pip_spec": "thing[mcp]==1.2.3"}) == ("pypi", "thing")
    assert version_source({"install": "uv-tool", "version": "1.7.0",
                           "install_command": "uv tool install -p 3.13 serena-agent"}) == ("pypi", "serena-agent")
    assert version_source({"install": "zip-extract", "version": "1.2.3",
                           "github": {"owner": "o", "repo": "r"}}) == ("github", "o/r")
    assert version_source({"install": "bundle-source", "version": "6.0.0"}) is None
    assert version_targets({"id": "impeccable", "install": "npx-or-npm",
                            "version": "3.6.1", "npm_spec": "impeccable@3.6.1",
                            "skill_version": "4.1.3",
                            "github": {"owner": "o", "repo": "r"}}) == [
        ("impeccable", "3.6.1", ("npm", "impeccable")),
        ("impeccable:skill", "4.1.3", ("github", "o/r")),
    ]
    assert VERSION_RE.search("release-v1.2.3").group(1) == "1.2.3"
    print("catalog freshness self-test PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--fail-on-stale", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    catalog = json.loads(args.catalog.read_text(encoding="utf-8-sig"))
    results = audit(catalog, args.timeout)
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for item in results:
            latest = item.get("latest", "-")
            detail = item.get("error") or item.get("source", "")
            print(f"{item['status'].upper():7} {item['id']:<24} {item['pinned']:<12} {latest:<12} {detail}")
        counts = {status: sum(x["status"] == status for x in results)
                  for status in ("current", "stale", "skipped", "error")}
        print("summary: " + ", ".join(f"{key}={value}" for key, value in counts.items()))

    if any(x["status"] == "error" for x in results):
        return 2
    if args.fail_on_stale and any(x["status"] == "stale" for x in results):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
