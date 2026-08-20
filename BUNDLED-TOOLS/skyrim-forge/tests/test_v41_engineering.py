from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

from skyrim_forge.capabilities import get_capability, registry
from skyrim_forge.framework_builder import build as build_framework, validate_plan as validate_framework_plan
from skyrim_forge.frameworks import lint_file, lint_paths
from skyrim_forge.native import audit_binary, audit_project, scaffold, validate_plan as validate_native_plan
from skyrim_forge.papyrus import analyze_sources
from skyrim_forge.plugin_writer import build_plugin, validate_plan as validate_plugin_plan
from skyrim_forge.records import query_records


class V41EngineeringTests(unittest.TestCase):
    def test_capability_registry_has_honest_boundaries(self):
        report = registry()
        self.assertEqual(report["result"], "PASS")
        by_id = {item["id"]: item for item in report["capabilities"]}
        self.assertEqual(by_id["native.scaffold"]["level"], "profiled")
        self.assertEqual(by_id["runtime.skyrim"]["level"], "human_gate")
        self.assertEqual(by_id["navmesh.write"]["level"], "unsupported")
        self.assertEqual(get_capability("does.not.exist")["level"], "unsupported")

    def test_framework_builder_spid_runtime_proven_shape(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); work = root / "work"; work.mkdir()
            plan = root / "spid.json"
            plan.write_text(json.dumps({
                "schema":"skyrim-forge-framework-plan/1","profile":"spid-7.3","output_file":"ForHonor_DISTR.ini",
                "entries":[{"type":"Perk","form":"0x123~ForHonor.esp","level_filters":["25/255","0(55/255)"],"chance":"100"}]
            }), encoding="utf-8")
            report = build_framework(plan, work / "out", work, approved=True)
            self.assertEqual(report["result"], "PASS", report)
            self.assertEqual(report["issues"], [])
            self.assertIn("25/255,0(55/255)", Path(report["output"]).read_text())

    def test_framework_builder_flags_single_value_skill_without_failing(self):
        # Runtime disproved the blanket rejection: this shape is installed on
        # 13,427 rows in the reference corpus with no SPID parse failures. The
        # advisory stays so an author sees it; the hard error is gone.
        plan={"schema":"skyrim-forge-framework-plan/1","profile":"spid-7.3","output_file":"Bad_DISTR.ini","entries":[{"type":"Perk","form":"0x1~A.esp","level_filters":["0(25)"]}]}
        normalized=validate_framework_plan(plan)
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/"Bad_DISTR.ini"
            from skyrim_forge.framework_builder import render
            path.write_text(render(normalized))
            issues=lint_file(path)
            self.assertTrue(any("skill" in item["message"].casefold() for item in issues), issues)
            self.assertFalse([item for item in issues if item["severity"]=="error"], issues)

    def test_skypatcher_unknown_category_is_warning_not_false_failure(self):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/"SKSE"/"Plugins"/"SkyPatcher"/"newcategory"/"x.ini"
            path.parent.mkdir(parents=True)
            path.write_text("futureFilter=A:futurePatch=B\n", encoding="utf-8")
            report=lint_paths([path])
            self.assertEqual(report["result"],"PASS",report)
            self.assertGreaterEqual(report["warnings"],1)

    def test_skypatcher_typed_build_uses_canonical_path(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); work=root/"work"; work.mkdir(); plan=root/"plan.json"
            plan.write_text(json.dumps({"schema":"skyrim-forge-framework-plan/1","profile":"skypatcher-6.4.2","category":"weapon","output_file":"Example.ini","entries":[{"filters":[{"key":"filterByKeywords","value":"Skyrim.esm|1E715"}],"patches":[{"key":"attackDamage","value":"30"}]}]}))
            result=build_framework(plan,work/"mod",work,approved=True)
            self.assertEqual(result["result"],"PASS",result)
            self.assertTrue(Path(result["output"]).as_posix().endswith("SKSE/Plugins/SkyPatcher/weapon/Example.ini"))

    def test_papyrus_case_identity_and_hot_event_are_reviewed(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            # Windows filesystems are normally case-insensitive. Put the two
            # case-colliding identities in separate source roots so both files
            # exist and the analyzer, rather than the filesystem, detects them.
            first=root/"first"; second=root/"second"
            first.mkdir(); second.mkdir()
            a=first/"Example.psc"; b=second/"example.PSC"
            a.write_text("ScriptName Example extends Quest\nEvent OnUpdate()\nWhile True\nGame.GetPlayer()\nEndWhile\nEndEvent\n")
            b.write_text("ScriptName example extends Quest\n")
            report=analyze_sources([a,b])
            self.assertEqual(report["result"],"FAIL")
            codes={item["code"] for item in report["errors"]}
            self.assertIn("PAPYRUS-DUPLICATE-IDENTITY",codes)
            warning_codes={item["code"] for item in report["warnings"]}
            self.assertIn("PAPYRUS-LOOP-IN-UPDATE",warning_codes)
            self.assertIn("heuristics",report["evidence"].casefold())

    def test_native_scaffold_uses_one_runtime_strategy_and_staging(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); work=root/"work"; work.mkdir(); plan=root/"native.json"
            plan.write_text(json.dumps({"schema":"skyrim-forge-native-plugin-plan/1","project":"ExamplePlugin","display_name":"Example Plugin","version":"1.0.0","author":"Tester","email":"","description":"Test plugin","minimum_skse_version":"0.0.0","runtime_strategy":"address_library","compatible_runtimes":[],"struct_dependent":False}))
            report=scaffold(plan,work/"project",work,approved=True)
            self.assertEqual(report["result"],"PASS",report)
            audit=audit_project(work/"project")
            self.assertEqual(audit["result"],"PASS",audit)
            cmake=(work/"project"/"CMakeLists.txt").read_text()
            self.assertIn("USE_ADDRESS_LIBRARY",cmake)
            self.assertNotIn("COMPATIBLE_RUNTIMES",cmake)
            self.assertIn("FORGE_OUTPUT_ROOT",cmake)
            self.assertNotIn("TARGET_PDB_FILE",cmake)

    def test_native_runtime_strategy_conflicts_are_rejected(self):
        with self.assertRaises(Exception):
            validate_native_plan({"schema":"skyrim-forge-native-plugin-plan/1","project":"X","version":"1.0.0","author":"A","description":"D","runtime_strategy":"address_library","compatible_runtimes":["1.6.1170"]})

    def test_native_binary_audit_distinguishes_dll(self):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/"test.dll"; data=bytearray(512); data[:2]=b"MZ"; struct.pack_into("<I",data,0x3C,0x80); data[0x80:0x84]=b"PE\0\0"; struct.pack_into("<HHIIIHH",data,0x84,0x8664,1,0,0,0,0xF0,0x2022); struct.pack_into("<H",data,0x98,0x20B); path.write_bytes(data)
            result=audit_binary(path)
            self.assertEqual(result["result"],"PASS",result)
            self.assertTrue(result["dll_characteristic"])

    def test_plugin_formkeys_are_required_and_encoded(self):
        with self.assertRaises(Exception):
            validate_plugin_plan({"schema":"skyrim-forge-plugin-plan/1","output":"X.esp","masters":["Skyrim.esm"],"operations":[{"record":"FLST","editor_id":"List","forms":[0x123]}]})
        with self.assertRaises(Exception):
            validate_plugin_plan({"schema":"skyrim-forge-plugin-plan/1","output":"X.esp","masters":["Skyrim.esm"],"operations":[{"record":"FLST","editor_id":"List","forms":["0x05123456"]}]})
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); plan=root/"plan.json"; out=root/"out"
            plan.write_text(json.dumps({"schema":"skyrim-forge-plugin-plan/1","output":"X.esp","plugin_type":"espfe","masters":["Skyrim.esm"],"operations":[{"record":"KYWD","editor_id":"LocalKeyword"},{"record":"FLST","editor_id":"List","forms":["0x1E715~Skyrim.esm","@LocalKeyword"]}]}))
            result=build_plugin(plan,out,approved=True)
            self.assertEqual(result["result"],"PASS",result)
            matches=query_records(out/"X.esp")
            local_ids=[int(item["local_form_id_hex"],16) for item in matches["matches"]]
            self.assertEqual(min(local_ids),1)


if __name__ == "__main__":
    unittest.main()
