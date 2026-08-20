from __future__ import annotations

import copy
import json
import tempfile
import unittest
import zipfile
from datetime import date, timedelta
from pathlib import Path

from skyrim_forge.errors import ValidationError
from skyrim_forge.nexus import ADULT_KEYS, DECLARATIONS, REQUIRED_POLICIES, PLAN_SCHEMA, audit_plan, build_publication_bundle, render_mod_page, validate_plan


class NexusPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.release = self.root / "release"
        self.release.mkdir()
        (self.release / "Example.esp").write_bytes(b"TES4")
        (self.release / "LICENSE.md").write_text("Custom permissions\n", encoding="utf-8")
        self.plan_dir = self.root / "plan"
        self.plan_dir.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def plan(self):
        today = date.today().isoformat()
        return {
            "schema": PLAN_SCHEMA,
            "intent": "nexus_public",
            "policy_review": {
                "reviewed_at": today,
                "reviewer": "Tester",
                "sources": [{"id": key, "title": key, "url": url, "reviewed": True} for key, url in REQUIRED_POLICIES.items()],
            },
            "mod": {
                "name": "Example Mod", "version": "1.0.0", "game": "Skyrim Special Edition",
                "game_terms_url": "https://example.com/game-eula", "uploader": "Tester",
                "summary": "A small tested example.", "category": "Utilities", "tags": ["utility"],
                "donation_points": False, "event": "",
            },
            "page": {
                "description": "A functional example release.", "requirements": ["Skyrim Special Edition"],
                "installation": ["Install with a supported mod manager."], "uninstallation": ["Remove the mod."],
                "compatibility": ["Skyrim SE/AE"], "known_issues": [], "support": "Use the Nexus page.",
                "claims": [], "changelog": ["1.0.0: Initial release."],
            },
            "ownership": {
                "original_work": True,
                "project_license": {"id": "CUSTOM", "name": "Custom Nexus permissions", "url": "", "text_path": "LICENSE.md", "permissions_statement": "No redistribution without permission."},
                "collaborators": [],
                "assets": [
                    {"id": "plugin", "paths": ["Example.esp"], "kind": "plugin", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "not_allowed", "commercial_use": "not_allowed", "donation_points": "not_applicable", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""},
                    {"id": "license", "paths": ["LICENSE.md"], "kind": "documentation", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "not_allowed", "commercial_use": "not_allowed", "donation_points": "not_applicable", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""},
                ],
                "dependencies": [],
            },
            "declarations": {name: True for name in DECLARATIONS},
            "software": {"contains_executables": False, "internet_access": False, "internet_access_crucial": False, "source_code_url": "", "nexus_staff_contact_evidence": "", "network_disclosure": ""},
            "ai": {"used": True, "areas": ["code", "documentation"], "human_verified": True, "disclosure": "AI assisted code and documentation; the uploader reviewed the final output."},
            "content": {"adult": {name: False for name in ADULT_KEYS}, "political_references": False, "msf_branding": False, "violence": "none", "tags": []},
            "permissions": {"redistribution": "No redistribution.", "modification": "Ask first.", "asset_use": "Ask first.", "conversion": "Ask first.", "translation": "Allowed with credit.", "commercial_use": "Not allowed.", "donation_points": "Not applicable."},
            "attestation": {"signed_by": "Tester", "signed_at": today, "responsibility_accepted": True},
        }

    def normalized(self, plan=None):
        return validate_plan(plan or self.plan())

    def test_valid_release_is_share_ready(self):
        report = audit_plan(self.normalized(), self.release, evidence_base=self.plan_dir)
        self.assertEqual(report["result"], "PASS")
        self.assertTrue(report["share_ready"])
        self.assertEqual(report["mapped_file_count"], 2)

    def test_credit_is_not_permission(self):
        plan = self.plan()
        asset = plan["ownership"]["assets"][0]
        asset["provenance"] = "third_party_mod"
        asset["permission_basis"] = "owned"
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertEqual(report["result"], "FAIL")
        self.assertTrue(any("acceptable permission basis" in item for item in report["errors"]))

    def test_explicit_permission_requires_evidence(self):
        plan = self.plan()
        asset = plan["ownership"]["assets"][0]
        asset["provenance"] = "third_party_mod"
        asset["permission_basis"] = "explicit_permission"
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("documented permission evidence" in item for item in report["errors"]))

    def test_relative_permission_evidence_is_hashed_but_not_exposed(self):
        evidence = self.plan_dir / "evidence" / "permission.txt"
        evidence.parent.mkdir()
        evidence.write_text("permission granted", encoding="utf-8")
        plan = self.plan()
        asset = plan["ownership"]["assets"][0]
        asset["provenance"] = "third_party_mod"
        asset["permission_basis"] = "explicit_permission"
        asset["evidence"] = [{"path": "evidence/permission.txt", "description": "Private author permission", "public": False}]
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertEqual(report["result"], "PASS")
        self.assertIn("sha256", report["evidence"][0])
        self.assertNotIn(str(evidence), json.dumps(report["evidence"]))

    def test_absolute_permission_evidence_path_rejected(self):
        plan = self.plan()
        plan["ownership"]["assets"][0]["evidence"] = [{"path": "C:/private/message.png", "description": "Permission", "public": False}]
        with self.assertRaises(ValidationError):
            validate_plan(plan)


    def test_open_license_requires_licence_copy(self):
        plan = self.plan()
        asset = plan["ownership"]["assets"][0]
        asset["permission_basis"] = "open_license"
        asset["license"] = {"id": "MIT", "name": "MIT License", "url": "https://opensource.org/license/mit", "text_path": "", "permissions_statement": "MIT"}
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("no licence text path" in item for item in report["errors"]))

    def test_copyleft_license_requires_source_and_acknowledgement(self):
        (self.release / "GPL-LICENSE.txt").write_text("GPL", encoding="utf-8")
        plan = self.plan()
        plan["ownership"]["assets"].append({"id": "gpl-license", "paths": ["GPL-LICENSE.txt"], "kind": "documentation", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "allowed", "commercial_use": "allowed", "donation_points": "allowed", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""})
        asset = plan["ownership"]["assets"][0]
        asset["permission_basis"] = "open_license"
        asset["license"] = {"id": "GPL-3.0-only", "name": "GNU GPLv3", "url": "https://www.gnu.org/licenses/gpl-3.0.html", "text_path": "GPL-LICENSE.txt", "permissions_statement": "GPLv3"}
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        joined = "\n".join(report["errors"])
        self.assertIn("source-code location", joined)
        self.assertIn("obligations acknowledgement", joined)

    def test_unknown_license_requires_manual_acknowledgement(self):
        (self.release / "CUSTOM-LICENSE.txt").write_text("custom", encoding="utf-8")
        plan = self.plan()
        plan["ownership"]["assets"].append({"id": "custom-license", "paths": ["CUSTOM-LICENSE.txt"], "kind": "documentation", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "allowed", "commercial_use": "allowed", "donation_points": "allowed", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""})
        asset = plan["ownership"]["assets"][0]
        asset["permission_basis"] = "open_license"
        asset["license"] = {"id": "WEIRD-1.0", "name": "Unmodelled licence", "url": "https://example.com/license", "text_path": "CUSTOM-LICENSE.txt", "permissions_statement": "Custom"}
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("unmodelled licence" in item for item in report["errors"]))

    def test_unmapped_file_blocks_release(self):
        (self.release / "meshes.nif").write_bytes(b"Gamebryo File Format")
        report = audit_plan(self.normalized(), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("not mapped" in item for item in report["errors"]))

    def test_multiple_asset_match_blocks_release(self):
        plan = self.plan()
        duplicate = copy.deepcopy(plan["ownership"]["assets"][0])
        duplicate["id"] = "duplicate"
        plan["ownership"]["assets"].append(duplicate)
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(report["multiple_asset_matches"])
        self.assertEqual(report["result"], "FAIL")


    def test_compilation_requires_value_beyond_repackaging(self):
        plan = self.plan()
        plan["mod"]["release_type"] = "compilation"
        plan["mod"]["value_added_description"] = ""
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("beyond repackaging" in item for item in report["errors"]))

    def test_patch_release_requires_original_dependency(self):
        plan = self.plan()
        plan["mod"]["release_type"] = "patch"
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("must declare the original/required dependency" in item for item in report["errors"]))

    def test_nexus_permission_presets_cannot_exceed_asset_rights(self):
        plan = self.plan()
        plan["ownership"]["assets"][0]["redistribution"] = "not_allowed"
        plan["permissions"]["nexus_settings"] = {
            "upload_elsewhere": "allowed_with_credit",
            "modification": "allowed_with_credit",
            "asset_use": "allowed_with_credit",
            "conversion": "permission_required",
            "translation": "allowed_with_credit",
            "commercial_use": "allowed",
            "donation_points": "not_applicable",
        }
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        joined = "\n".join(report["errors"])
        self.assertIn("upload-elsewhere permission is broader", joined)
        self.assertIn("modification permission is broader", joined)
        self.assertIn("commercial-use permission is broader", joined)

    def test_donation_points_requires_each_asset_permission(self):
        plan = self.plan()
        plan["mod"]["donation_points"] = True
        plan["ownership"]["assets"][0]["donation_points"] = "unknown"
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("Donation Points" in item for item in report["errors"]))

    def test_known_game_file_is_blocked(self):
        (self.release / "Skyrim.esm").write_bytes(b"TES4")
        plan = self.plan()
        plan["ownership"]["assets"].append({"id": "game", "paths": ["Skyrim.esm"], "kind": "plugin", "provenance": "game_derived", "author": "Bethesda", "source_url": "", "source_name": "Skyrim", "license": None, "permission_basis": "game_terms", "redistribution": "allowed", "modification": "not_allowed", "commercial_use": "not_allowed", "donation_points": "not_allowed", "credit": "Bethesda", "credit_required": True, "bundled": True, "evidence": [], "notes": ""})
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("original game/tool files" in item for item in report["errors"]))

    def test_executable_inventory_must_match_declaration(self):
        (self.release / "Tool.exe").write_bytes(b"MZ")
        plan = self.plan()
        plan["ownership"]["assets"].append({"id": "tool", "paths": ["Tool.exe"], "kind": "executable", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "allowed", "commercial_use": "allowed", "donation_points": "allowed", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""})
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("contains_executables" in item for item in report["errors"]))

    def test_internet_connected_tool_requires_source_staff_contact_and_disclosure(self):
        (self.release / "Tool.exe").write_bytes(b"MZ")
        plan = self.plan()
        plan["ownership"]["assets"].append({"id": "tool", "paths": ["Tool.exe"], "kind": "executable", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "allowed", "commercial_use": "allowed", "donation_points": "allowed", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""})
        plan["software"].update({"contains_executables": True, "internet_access": True})
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        joined = "\n".join(report["errors"])
        self.assertIn("not crucial", joined)
        self.assertIn("source-code URL", joined)
        self.assertIn("Nexus staff", joined)
        self.assertIn("network disclosure", joined)

    def test_performance_claim_requires_evidence(self):
        plan = self.plan()
        plan["page"]["description"] = "Doubles FPS and removes all stutter."
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("Performance/optimization claims" in item for item in report["errors"]))

    def test_stale_policy_review_blocks(self):
        plan = self.plan()
        plan["policy_review"]["reviewed_at"] = (date.today() - timedelta(days=91)).isoformat()
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("policy review is stale" in item for item in report["errors"]))

    def test_event_profile_blocks_ai(self):
        plan = self.plan()
        plan["mod"]["event"] = "nexus-25th-anniversary-2026"
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("prohibits generative AI" in item for item in report["errors"]))

    def test_adult_content_requires_matching_tag(self):
        plan = self.plan()
        plan["content"]["adult"]["nudity"] = True
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("Adult content is declared" in item for item in report["errors"]))

    def test_uploader_attestation_cannot_be_mismatched(self):
        plan = self.plan()
        plan["attestation"]["signed_by"] = "AI Agent"
        report = audit_plan(self.normalized(plan), self.release, evidence_base=self.plan_dir)
        self.assertTrue(any("must match mod.uploader" in item for item in report["errors"]))

    def test_build_bundle_separates_private_audit(self):
        plan = self.plan()
        plan_path = self.plan_dir / "plan.json"
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        workspace = self.root / "workspace"
        workspace.mkdir()
        output = workspace / "publication"
        report = build_publication_bundle(plan_path, self.release, output, workspace, approved=True)
        self.assertTrue(report["share_ready"])
        self.assertTrue((output / "release-tree" / "NEXUS-MOD-PAGE.bbcode").is_file())
        self.assertTrue((output / "release-tree" / "RIGHTS-MANIFEST.json").is_file())
        self.assertTrue((output / "private-audit" / "NEXUS-COMPLIANCE-AUDIT.json").is_file())
        archive = Path(report["archive"])
        with zipfile.ZipFile(archive) as zf:
            names = set(zf.namelist())
        self.assertIn("RIGHTS-MANIFEST.json", names)
        self.assertFalse(any(name.startswith("private-audit/") for name in names))

    def test_rendered_page_contains_credits_permissions_and_ai_disclosure(self):
        page = render_mod_page(self.normalized())
        self.assertIn("[heading]Credits[/heading]", page)
        self.assertIn("[heading]Permissions and Licensing[/heading]", page)
        self.assertIn("[heading]AI Assistance Disclosure[/heading]", page)


if __name__ == "__main__":
    unittest.main()
