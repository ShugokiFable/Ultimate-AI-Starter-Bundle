from __future__ import annotations

from typing import Any

from .capabilities import registry as capability_registry
from .fomod import self_test as fomod_self_test
from .framework_builder import self_test as framework_builder_self_test
from .frameworks import self_test as framework_lint_self_test
from .native import self_test as native_self_test
from .nexus import self_test as nexus_self_test
from .papyrus import self_test as papyrus_self_test
from .version import VERSION
from .toolchain import load_catalog


def run_all() -> dict[str, Any]:
    catalog = load_catalog()
    checks = {
        "framework_lint": framework_lint_self_test(),
        "framework_builder": framework_builder_self_test(),
        "fomod": fomod_self_test(),
        "papyrus": papyrus_self_test(),
        "native": native_self_test(),
        "nexus": nexus_self_test(),
        "capabilities": capability_registry(),
        "toolchain": {"result": "PASS" if any(item["id"] == "bsarch" for item in catalog["tools"]) and all(not item.get("public_bundle_allowed", False) for item in catalog["tools"]) else "FAIL", "catalog_count": len(catalog["tools"])},
    }
    failed = [name for name, report in checks.items() if str(report.get("result", "FAIL")).upper() != "PASS"]
    return {
        "result": "PASS" if not failed else "FAIL",
        "version": VERSION,
        "failed": failed,
        "checks": checks,
        "evidence": "Built-in deterministic regression fixtures. External tool and Skyrim runtime evidence remain separate.",
    }
