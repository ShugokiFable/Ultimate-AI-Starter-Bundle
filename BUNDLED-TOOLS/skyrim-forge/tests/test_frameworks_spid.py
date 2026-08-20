from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from skyrim_forge.frameworks import lint_paths


class SpidGrammarTests(unittest.TestCase):
    def test_actor_level_plus_skill_range_is_valid(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ForHonor_DISTR.ini"
            path.write_text("Perk = 0x123~ForHonor.esp|||25/255,0(55/255)|||100\n", encoding="utf-8")
            report = lint_paths([path])
            self.assertEqual(report["result"], "PASS", report)
            self.assertEqual(report["errors"], 0)

    def test_single_value_skill_expression_is_reported_not_failed(self):
        """A single-value skill filter is reported, never failed.

        Forge treated this as malformed. The reference corpus contains 13,427
        installed rows of exactly this shape across skill indices 12-16, and
        po3_SpellPerkItemDistributor.log records zero parse failures for them;
        one was traced end to end (Abyss `14(20)` -> SPEL:FE059810 distributed).
        Five rows using index 0 were rejected at runtime, so the note is kept -
        but failing 13,427 working rows to catch 5 is the worse error.
        """
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "Probe_DISTR.ini"
            path.write_text("Perk = 0x123~Probe.esp|||10/24,0(25)|||100\n", encoding="utf-8")
            report = lint_paths([path])
            self.assertEqual(report["result"], "PASS", report)
            issues = [issue for item in report["reports"] for issue in item["issues"]]
            self.assertTrue(any("skill" in issue["message"].casefold() for issue in issues))
            self.assertTrue(all(issue["severity"] != "error" for issue in issues), issues)

    def test_runtime_proven_skill_filter_is_silent(self):
        # Abyss ships this line and it distributes; it must not be flagged at all.
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "Abyss_DISTR.ini"
            path.write_text("Spell = 0x810~Abyss.esp|Vampire|NONE|14(20)|NONE|NONE|30\n", encoding="utf-8")
            report = lint_paths([path])
            self.assertEqual(report["result"], "PASS", report)
            self.assertFalse([i for item in report["reports"] for i in item["issues"] if i["severity"] == "error"])

    def test_skill_index_and_range_order_are_checked(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "Broken_DISTR.ini"
            path.write_text("Perk = 0x123~Broken.esp|||18(50/10)|||100\n", encoding="utf-8")
            report = lint_paths([path])
            self.assertEqual(report["result"], "FAIL")
            messages = [issue["message"] for item in report["reports"] for issue in item["issues"]]
            self.assertTrue(any("index" in message.casefold() for message in messages))

    def test_unknown_future_key_is_warning_not_false_failure(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "future_DISTR.ini"
            path.write_text("FutureDistribution = 0x1~A.esp||||||100\n", encoding="utf-8")
            report = lint_paths([path])
            self.assertEqual(report["result"], "PASS")
            self.assertEqual(report["errors"], 0)
            self.assertEqual(report["warnings"], 1)
            self.assertIn("outside Forge's pinned 7.3 profile", report["reports"][0]["issues"][0]["message"])

    def test_known_weapon_alias_remains_a_hard_error(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "bad_DISTR.ini"
            path.write_text("Weapon = 0x1~A.esp||||||100\n", encoding="utf-8")
            report = lint_paths([path])
            self.assertEqual(report["result"], "FAIL")
            self.assertEqual(report["errors"], 1)


class InstalledCorpusRegressionTests(unittest.TestCase):
    """Shapes taken verbatim from ~1200 installed, working framework configs.

    Forge's profiles were written from documentation with no reference corpus.
    Run against the real thing, the linter produced 13,554 errors and 11,762
    warnings across 16% of files; triage against the frameworks' own SKSE
    runtime logs showed essentially all of it was false. Each case below is a
    real installed line that must not be failed again.
    """

    def _lint(self, name: str, body: str, subdir: tuple[str, ...] = ()) -> dict:
        td = Path(tempfile.mkdtemp())
        path = td.joinpath(*subdir) / name if subdir else td / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body.encode("utf-8"))
        return lint_paths([path])

    def test_skypatcher_clause_value_may_be_a_comma_separated_form_list(self):
        # Animallica ships this. Forge split the value on ',' and demanded '='
        # in every element, reporting each form after the first: 11,730 warnings.
        line = ("filterByLLNPCs=Skyrim.esm|0x01E78D:removeFromLLs=Animallica.esp|001DBD, "
                "Animallica.esp|001DC8, Animallica.esp|0055C9:addToLLs=Animallica.esp|001DBD~1~1\n")
        report = self._lint("Animallica.esp.ini", line, ("SKSE", "Plugins", "SkyPatcher", "leveledlist"))
        self.assertEqual(report["result"], "PASS", report)
        self.assertEqual(report["warnings"], 0, report)

    def test_skypatcher_categories_present_in_real_installs_are_known(self):
        # outfit, ingestible, misc, ingredient and projectile are all installed.
        for category in ("outfit", "ingestible", "misc", "ingredient", "projectile"):
            report = self._lint("x.ini", "filterByArmors=A.esp|1:clearArmorAddons=true\n",
                                ("SKSE", "Plugins", "SkyPatcher", category))
            self.assertEqual(report["warnings"], 0, f"{category}: {report}")

    def test_stacked_and_midfile_boms_do_not_invent_findings(self):
        # One corpus file opens with three stacked BOMs; another carries a BOM
        # mid-file where two sources were concatenated. Survivors turned a
        # comment into a malformed line and a valid key into an unknown one.
        report = self._lint("Probe_DISTR.ini", "﻿﻿﻿;Personal Template\nSpell = 0x1~A.esp\n")
        self.assertEqual(report["result"], "PASS", report)
        self.assertEqual(report["errors"], 0, report)
        flm = self._lint("Probe_FLM.ini", "﻿FormList = AnimatedFishing_Bait|WTMothWingDimfrost\n")
        self.assertEqual(flm["warnings"], 0, flm)

    def test_kid_keys_are_case_insensitive(self):
        # BOOBIES ships lowercase `keyword =`; BoobiesArmorPouch [KYWD:FF001DA3]
        # was created and distributed at runtime.
        report = self._lint("Probe_KID.ini", "keyword = BoobiesArmorPouch|Armor|DBM_ELRLCoatBeltBags\n")
        self.assertEqual(report["result"], "PASS", report)
        self.assertEqual(report["errors"], 0, report)

    def test_kid_two_field_line_is_not_an_unsupported_type(self):
        # `Keyword = BoobiesArmorScarf|aMCHood` filters by name, not type, and
        # BoobiesArmorScarf [KYWD:FF001DA5] applied at runtime.
        report = self._lint("Probe_KID.ini", "Keyword = BoobiesArmorScarf|aMCHood\n")
        self.assertEqual(report["result"], "PASS", report)
        self.assertEqual(report["errors"], 0, report)

    def test_repeated_advisory_is_collapsed_to_one_entry(self):
        body = "".join(f"Spell = 0x{n:X}~A.esp|Vampire|NONE|14(20)|NONE|NONE|30\n" for n in range(1, 41))
        report = self._lint("Probe_DISTR.ini", body)
        issues = [issue for item in report["reports"] for issue in item["issues"]]
        self.assertEqual(len(issues), 1, issues)
        self.assertIn("40 lines", issues[0]["message"])


if __name__ == "__main__":
    unittest.main()
