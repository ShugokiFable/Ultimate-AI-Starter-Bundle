from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path

from _workflows import workflows_dir


class CIValidationScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        script = Path(__file__).resolve().parents[1] / "scripts" / "validate_repository.py"
        spec = importlib.util.spec_from_file_location("forge_validate_repository", script)
        assert spec and spec.loader
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_python_scope_never_rebuilds_native_binaries(self):
        checks = self.module.validation_checks("python")
        self.assertIn("python", checks)
        self.assertIn("packaging", checks)
        self.assertNotIn("native", checks)
        self.assertNotIn("go", checks)

    def test_full_scope_contains_reproducibility_checks(self):
        checks = self.module.validation_checks("full")
        self.assertIn("native", checks)
        self.assertIn("go", checks)

    def test_unknown_scope_is_rejected(self):
        with self.assertRaises(ValueError):
            self.module.validation_checks("unknown")

    def test_embedded_validator_resolves_root_go_toolchain(self):
        self.assertEqual(
            self.module.GO_TOOLCHAIN,
            "go1.23.2",
            "embedded Forge validator lost the repository-root Go pin",
        )

    def test_embedded_rebuild_helper_resolves_root_go_toolchain(self):
        script = Path(__file__).resolve().parents[1] / "scripts" / "rebuild_native_helpers.py"
        spec = importlib.util.spec_from_file_location("forge_rebuild_native_helpers", script)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(
            module.TOOLCHAIN,
            "go1.23.2",
            "embedded Forge rebuild helper lost the repository-root Go pin",
        )


class WorkflowPinningTests(unittest.TestCase):
    """CodeQL's init and analyze actions must always run the same release.

    Dependabot raises one pull request per action unless they are grouped, so
    each request bumped half of the pair and every CodeQL run on those branches
    died with "Loaded a configuration file for version '4.37.6', but running
    version '4.36.0'". Four pull requests sat blocked behind it.
    """

    WORKFLOWS = workflows_dir()

    def test_codeql_action_versions_are_pinned_together(self):
        if self.WORKFLOWS is None:
            self.skipTest("no workflows above this subtree")
        pinned = set()
        for workflow in self.WORKFLOWS.glob("*.yml"):
            for match in re.finditer(r"github/codeql-action/\w+@(\S+)", workflow.read_text(encoding="utf-8")):
                pinned.add(match.group(1))
        if not pinned:
            self.skipTest("no CodeQL workflow present")
        self.assertEqual(len(pinned), 1, f"codeql-action steps are pinned to different revisions: {sorted(pinned)}")

    def test_dependabot_groups_the_codeql_pair(self):
        if self.WORKFLOWS is None:
            self.skipTest("no workflows above this subtree")
        config = self.WORKFLOWS.parent / "dependabot.yml"
        if not config.exists():
            self.skipTest("no dependabot configuration present")
        self.assertIn("github/codeql-action", config.read_text(encoding="utf-8"),
                      "dependabot must group codeql-action so the pair cannot be split across pull requests")

    def test_release_publish_is_idempotent(self):
        # Forge stopped publishing releases of its own when it moved into the
        # bundle repository. If a release workflow ever appears at the checkout
        # root, re-running it over an existing tag must still not fail.
        release = self.WORKFLOWS / "release.yml" if self.WORKFLOWS else None
        if release is None or not release.is_file():
            self.skipTest("no release workflow present")
        workflow = release.read_text(encoding="utf-8")
        self.assertIn('gh release view "$GITHUB_REF_NAME"', workflow)
        self.assertIn('gh release upload "$GITHUB_REF_NAME" dist/* --clobber', workflow)
        self.assertIn('gh release create "$GITHUB_REF_NAME" dist/* --verify-tag --generate-notes', workflow)


if __name__ == "__main__":
    unittest.main()
