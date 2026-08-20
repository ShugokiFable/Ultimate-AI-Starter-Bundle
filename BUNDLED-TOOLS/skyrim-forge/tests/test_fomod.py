from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from skyrim_forge.errors import ValidationError
from skyrim_forge.fomod import (
    PLAN_SCHEMA,
    build_fomod,
    scaffold_plan,
    simulate_plan,
    validate_fomod,
    validate_plan_data,
)
from skyrim_forge.release import validate_release_tree


def sample_plan() -> dict:
    return {
        "schema": PLAN_SCHEMA,
        "module": {
            "name": "Forge FOMOD Fixture",
            "author": "Forge Tests",
            "version": "1.2.3",
            "machine_version": "1.2.3",
            "description": "Complete installer fixture",
            "website": "https://example.invalid",
            "image": "fomod/images/banner.png",
        },
        "required_files": [
            {"kind": "folder", "source": "00 Core", "destination": "", "always_install": True}
        ],
        "steps": [
            {
                "name": "Visual Selection",
                "groups_order": "Explicit",
                "groups": [
                    {
                        "name": "Theme",
                        "type": "SelectExactlyOne",
                        "plugins_order": "Explicit",
                        "plugins": [
                            {
                                "name": "Red",
                                "description": "Red textures",
                                "files": [{"kind": "folder", "source": "10 Red", "destination": "", "priority": 10}],
                                "flags": {"Theme": "Red"},
                                "type": "Recommended",
                            },
                            {
                                "name": "Blue",
                                "description": "Blue textures",
                                "files": [{"kind": "folder", "source": "20 Blue", "destination": "", "priority": 10}],
                                "flags": {"Theme": "Blue"},
                                "type": "Optional",
                            },
                        ],
                    }
                ],
            }
        ],
        "conditional_files": [
            {
                "dependencies": {"flag": {"name": "Theme", "value": "Red"}},
                "files": [{"kind": "file", "source": "Extras/red.ini", "destination": "SKSE/Plugins/red.ini", "priority": 20}],
            }
        ],
        "strict_coverage": True,
    }


def create_payload(root: Path) -> None:
    for relative, content in {
        "00 Core/SKSE/Plugins/Core.dll": b"core",
        "10 Red/textures/theme.dds": b"red",
        "20 Blue/textures/theme.dds": b"blue",
        "Extras/red.ini": b"red=true\n",
        "fomod/images/banner.png": b"png",
    }.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)


class FomodTests(unittest.TestCase):
    def test_plan_build_validate_and_release_gate(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            source = root / "source"
            workspace = root / "workspace"
            source.mkdir(); workspace.mkdir()
            create_payload(source)
            plan_path = root / "plan.json"
            plan_path.write_text(json.dumps(sample_plan()), encoding="utf-8")
            report = build_fomod(plan_path, source, workspace / "Built", workspace, approved=True)
            self.assertEqual(report["result"], "PASS", report)
            validation = validate_fomod(workspace / "Built")
            self.assertEqual(validation["result"], "PASS", validation)
            self.assertEqual(validation["counts"]["plugins"], 2)
            release = validate_release_tree(workspace / "Built")
            self.assertEqual(release["result"], "PASS", release)
            self.assertEqual(release["fomod"]["result"], "PASS")

    def test_spid_style_branch_simulation_enforces_group_and_flags(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td) / "source"
            source.mkdir()
            create_payload(source)
            result = simulate_plan(sample_plan(), {"Visual Selection/Theme": "Red"}, {}, source)
            self.assertEqual(result["result"], "PASS", result)
            self.assertEqual(result["flags"], {"Theme": "Red"})
            self.assertIn("Visual Selection/Theme/Red", result["selected_plugins"])
            self.assertEqual(result["mapping_count"], 3)
            invalid = simulate_plan(sample_plan(), {"Visual Selection/Theme": ["Red", "Blue"]}, {}, source)
            self.assertEqual(invalid["result"], "FAIL")
            self.assertTrue(any("exactly one" in item for item in invalid["errors"]))

    def test_unreferenced_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td)
            create_payload(source)
            (source / "Forgotten.txt").write_text("not mapped", encoding="utf-8")
            with self.assertRaises(ValidationError):
                validate_plan_data(sample_plan(), source)

    def test_path_traversal_is_rejected(self):
        plan = sample_plan()
        plan["required_files"][0]["source"] = "../outside"
        with self.assertRaises(ValidationError):
            validate_plan_data(plan)

    def test_equal_priority_collision_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td)
            create_payload(source)
            plan = sample_plan()
            plan["required_files"].extend([
                {"kind": "file", "source": "10 Red/textures/theme.dds", "destination": "textures/collision.dds", "priority": 5},
                {"kind": "file", "source": "20 Blue/textures/theme.dds", "destination": "textures/collision.dds", "priority": 5},
            ])
            with self.assertRaises(ValidationError):
                validate_plan_data(plan, source)

    def test_scaffold_unwraps_single_data_folder(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            data = root / "Data" / "meshes"
            data.mkdir(parents=True)
            (data / "x.nif").write_bytes(b"nif")
            plan = scaffold_plan(root, "Data Fixture", "1.0.0")
            self.assertEqual(plan["required_files"][0]["source"], "Data")
            self.assertEqual(plan["required_files"][0]["destination"], "")
            validate_plan_data(plan, root)

    def test_invalid_moduleconfig_order_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            fomod = root / "fomod"
            fomod.mkdir()
            (fomod / "ModuleConfig.xml").write_text(
                '<?xml version="1.0"?><config><installSteps order="Explicit"/><moduleName>X</moduleName></config>',
                encoding="utf-8",
            )
            (fomod / "info.xml").write_text('<fomod><Name>X</Name><Version MachineVersion="1.0.0">1.0.0</Version></fomod>', encoding="utf-8")
            report = validate_fomod(root, strict_coverage=False)
            self.assertEqual(report["result"], "FAIL")
            self.assertTrue(any("order" in item.casefold() for item in report["errors"]))


if __name__ == "__main__":
    unittest.main()


class FomodSchemaHardeningTests(unittest.TestCase):
    def test_generated_xml_uses_direct_visible_dependencies_and_schema_order(self):
        import xml.etree.ElementTree as ET
        from skyrim_forge.fomod import plan_to_xml

        plan = sample_plan()
        plan["steps"].append({
            "name": "Compatibility",
            "visible": {"flag": {"name": "Theme", "value": "Red"}},
            "groups": [{
                "name": "Patch",
                "type": "SelectAny",
                "plugins": [{
                    "name": "Optional Patch",
                    "description": "Conditional option",
                    "flags": {"PatchSelected": "true"},
                    "type": {
                        "default": "Optional",
                        "patterns": [{
                            "dependencies": {"flag": {"name": "Theme", "value": "Red"}},
                            "type": "Recommended",
                        }],
                    },
                }],
            }],
        })
        normalized = validate_plan_data(plan)
        config_tree, _ = plan_to_xml(normalized)
        root = config_tree.getroot()
        steps = root.find("installSteps")
        self.assertIsNotNone(steps)
        self.assertEqual(steps.attrib["order"], "Explicit")
        compatibility = list(steps)[1]
        self.assertEqual([node.tag for node in compatibility], ["visible", "optionalFileGroups"])
        visible = compatibility.find("visible")
        self.assertEqual([node.tag for node in visible], ["flagDependency"])
        self.assertIsNone(visible.find("dependencies"))
        dynamic = compatibility.find("./optionalFileGroups/group/plugins/plugin/typeDescriptor/dependencyType")
        self.assertEqual([node.tag for node in dynamic], ["defaultType", "patterns"])
        pattern = dynamic.find("patterns/pattern")
        self.assertEqual([node.tag for node in pattern], ["dependencies", "type"])

    def test_typed_root_destination_is_emitted_explicitly(self):
        from skyrim_forge.fomod import plan_to_xml

        normalized = validate_plan_data(sample_plan())
        config_tree, _ = plan_to_xml(normalized)
        required = config_tree.getroot().find("requiredInstallFiles/folder")
        self.assertIsNotNone(required)
        self.assertIn("destination", required.attrib)
        self.assertEqual(required.attrib["destination"], "")

    def test_utf16_and_screenshot_module_image_are_supported(self):
        from skyrim_forge.fomod import plan_to_xml, _write_xml

        plan = sample_plan()
        plan["xml_encoding"] = "utf-16"
        plan["module"].pop("image")
        plan["module"]["image_show"] = False
        plan["module"]["image_height"] = 0
        normalized = validate_plan_data(plan)
        config_tree, info_tree = plan_to_xml(normalized)
        image = config_tree.getroot().find("moduleImage")
        self.assertIsNotNone(image)
        self.assertNotIn("path", image.attrib)
        self.assertEqual(image.attrib["showImage"], "false")
        self.assertEqual(image.attrib["height"], "0")
        with tempfile.TemporaryDirectory() as td:
            config_path = Path(td) / "ModuleConfig.xml"
            info_path = Path(td) / "info.xml"
            _write_xml(config_tree, config_path, "utf-16")
            _write_xml(info_tree, info_path, "utf-16")
            self.assertTrue(config_path.read_bytes().startswith((b"\xff\xfe", b"\xfe\xff")))

    def test_plugin_and_conditional_payload_requirements_are_enforced(self):
        plan = sample_plan()
        plugin = plan["steps"][0]["groups"][0]["plugins"][0]
        plugin.pop("files")
        plugin["flags"] = {}
        with self.assertRaisesRegex(ValidationError, "explicitly contain files or condition flags"):
            validate_plan_data(plan)

        plan = sample_plan()
        plugin = plan["steps"][0]["groups"][0]["plugins"][0]
        plugin["files"] = []
        plugin["flags"] = {}
        normalized = validate_plan_data(plan)
        self.assertTrue(normalized["steps"][0]["groups"][0]["plugins"][0]["files_present"])

        plan = sample_plan()
        plan["conditional_files"][0]["files"] = []
        with self.assertRaisesRegex(ValidationError, "must contain at least one mapping"):
            validate_plan_data(plan)

        plan = sample_plan()
        plan["conditional_files"][0].pop("dependencies")
        with self.assertRaisesRegex(ValidationError, "dependencies is required"):
            validate_plan_data(plan)

    def test_temporal_flag_references_are_enforced(self):
        plan = sample_plan()
        plan["module_dependencies"] = {"flag": {"name": "Theme", "value": "Red"}}
        with self.assertRaisesRegex(ValidationError, "before installation begins"):
            validate_plan_data(plan)

        plan = sample_plan()
        plan["steps"][0]["visible"] = {"flag": {"name": "Theme", "value": "Red"}}
        with self.assertRaisesRegex(ValidationError, "not defined by earlier steps"):
            validate_plan_data(plan)

    def test_always_install_and_install_if_usable_apply_when_option_unselected(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td)
            create_payload(source)
            plan = sample_plan()
            red = plan["steps"][0]["groups"][0]["plugins"][0]
            blue = plan["steps"][0]["groups"][0]["plugins"][1]
            red["files"][0]["destination"] = "textures/red"
            blue["files"][0]["destination"] = "textures/blue"
            red["files"][0]["always_install"] = True
            blue["files"][0]["install_if_usable"] = True
            result = simulate_plan(plan, {"Visual Selection/Theme": "Red"}, {}, source)
            self.assertEqual(result["result"], "PASS", result)
            # required core + selected red + unselected blue installIfUsable + red conditional
            self.assertEqual(result["mapping_count"], 4)

    def test_always_install_breaks_mutually_exclusive_collision_safety(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td)
            create_payload(source)
            plan = sample_plan()
            red = plan["steps"][0]["groups"][0]["plugins"][0]["files"][0]
            blue = plan["steps"][0]["groups"][0]["plugins"][1]["files"][0]
            red["destination"] = "textures/shared"
            blue["destination"] = "textures/shared"
            red["always_install"] = True
            with self.assertRaisesRegex(ValidationError, "Ambiguous FOMOD destination collision"):
                validate_plan_data(plan, source)

    def test_existing_xml_omitted_destination_defaults_to_source(self):
        import xml.etree.ElementTree as ET
        from skyrim_forge.fomod import plan_to_xml, _write_xml

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            create_payload(root)
            plan = sample_plan()
            plan["strict_coverage"] = False
            normalized = validate_plan_data(plan)
            config_tree, info_tree = plan_to_xml(normalized)
            mapping = config_tree.getroot().find("requiredInstallFiles/folder")
            mapping.attrib.pop("destination")
            _write_xml(config_tree, root / "fomod" / "ModuleConfig.xml")
            _write_xml(info_tree, root / "fomod" / "info.xml")
            report = validate_fomod(root, strict_coverage=False)
            self.assertEqual(report["result"], "PASS", report)

    def test_schema_location_is_reported_but_never_fatal(self):
        """`xsi:noNamespaceSchemaLocation` is an optional XML hint.

        ModConfig5.0.xsd does not require it and no manager reads it, so
        enforcing it failed installers that Vortex and MO2 install without
        complaint. It is reported as a warning and the structure is still
        validated.
        """
        from skyrim_forge.fomod import plan_to_xml, _write_xml, XSI

        for value in ("wrong.xsd", "https://qconsulting.ca/fo3/ModConfig5.0.xsd", None):
            with tempfile.TemporaryDirectory() as td:
                root = Path(td)
                create_payload(root)
                normalized = validate_plan_data(sample_plan())
                config_tree, info_tree = plan_to_xml(normalized)
                attribute = f"{{{XSI}}}noNamespaceSchemaLocation"
                if value is None:
                    config_tree.getroot().attrib.pop(attribute, None)
                else:
                    config_tree.getroot().set(attribute, value)
                _write_xml(config_tree, root / "fomod" / "ModuleConfig.xml")
                _write_xml(info_tree, root / "fomod" / "info.xml")
                report = validate_fomod(root, strict_coverage=False)
                self.assertEqual(report["result"], "PASS", f"schema location {value!r} must not fail validation")
                self.assertFalse([e for e in report["errors"] if "schema" in e.lower()])
            if value != "https://qconsulting.ca/fo3/ModConfig5.0.xsd":
                self.assertTrue(any("schema location" in w or "noNamespaceSchemaLocation" in w for w in report["warnings"]))

    def test_csharp_installer_is_still_refused(self):
        from skyrim_forge.fomod import plan_to_xml, _write_xml

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            create_payload(root)
            normalized = validate_plan_data(sample_plan())
            config_tree, info_tree = plan_to_xml(normalized)
            _write_xml(config_tree, root / "fomod" / "ModuleConfig.xml")
            _write_xml(info_tree, root / "fomod" / "info.xml")
            (root / "fomod" / "script.cs").write_text("// arbitrary code", encoding="utf-8")
            report = validate_fomod(root, strict_coverage=False)
            self.assertEqual(report["result"], "FAIL")
            self.assertTrue(any("C# scripted" in item for item in report["errors"]))


SCHEMA_ATTRS = ('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                'xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd"')
MINIMAL_INFO = '<?xml version="1.0" encoding="utf-8"?>\n<fomod><Name>P</Name><Version>1.0</Version></fomod>\n'


def write_third_party_fomod(root: Path, plugin_body: str, module_dependencies: str = "") -> None:
    """Write a FOMOD that is legal per ModConfig5.0.xsd, as a real mod ships it."""
    (root / "fomod").mkdir(parents=True, exist_ok=True)
    (root / "core").mkdir(parents=True, exist_ok=True)
    (root / "core" / "Probe.esp").write_bytes(b"TES4probe")
    (root / "fomod" / "option.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    config = (
        f'<?xml version="1.0" encoding="utf-8"?>\n<config {SCHEMA_ATTRS}>\n'
        "  <moduleName>Probe</moduleName>\n"
        f"{module_dependencies}"
        '  <installSteps order="Explicit">\n    <installStep name="Main">\n'
        '      <optionalFileGroups order="Explicit">\n'
        '        <group name="G" type="SelectExactlyOne">\n'
        '          <plugins order="Explicit">\n'
        f"{plugin_body}\n"
        "          </plugins>\n        </group>\n"
        "      </optionalFileGroups>\n    </installStep>\n  </installSteps>\n</config>\n"
    )
    (root / "fomod" / "ModuleConfig.xml").write_text(config, encoding="utf-8")
    (root / "fomod" / "info.xml").write_text(MINIMAL_INFO, encoding="utf-8")


class ThirdPartyFomodFalsePositiveTests(unittest.TestCase):
    """Installers that Vortex and MO2 accept must not be failed by Forge.

    Forge is meant to be the last gate a mod passes, which makes a false
    rejection more expensive than a missed nicety: it teaches the author to stop
    trusting the gate. Each case here is legal per the official
    ModConfig5.0.xsd and was rejected before 5.0.1.
    """

    def test_plugin_with_an_option_image_is_accepted(self):
        # XSD plugin sequence: description, image?, (files|conditionFlags...), typeDescriptor.
        # The optional image was not allowed for, so every option carrying a
        # screenshot - which is most of them - was rejected.
        body = ('            <plugin name="Core">\n'
                "              <description>Core.</description>\n"
                '              <image path="fomod/option.png" />\n'
                '              <files><folder source="core" destination="" /></files>\n'
                '              <typeDescriptor><type name="Required" /></typeDescriptor>\n'
                "            </plugin>")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write_third_party_fomod(root, body)
            report = validate_fomod(root, strict_coverage=True)
            self.assertEqual(report["result"], "PASS", report["errors"])

    def test_game_specific_version_dependency_is_recorded_not_refused(self):
        # The fo3 schema Forge names as canonical exists to add foseDependency.
        # Refusing it contradicted the schema the validator asks for.
        body = ('            <plugin name="Core">\n'
                "              <description>Core.</description>\n"
                '              <files><folder source="core" destination="" /></files>\n'
                '              <typeDescriptor><type name="Required" /></typeDescriptor>\n'
                "            </plugin>")
        deps = ('  <moduleDependencies operator="And">\n'
                '    <foseDependency version="1.2" />\n'
                "  </moduleDependencies>\n")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write_third_party_fomod(root, body, module_dependencies=deps)
            report = validate_fomod(root, strict_coverage=True)
            self.assertEqual(report["result"], "PASS", report["errors"])
            self.assertTrue(any("foseDependency" in w for w in report["warnings"]))

    def test_unreferenced_payload_names_the_files_it_rejects(self):
        # A gate that says "1 unreferenced file(s)" without naming it cannot be
        # acted on. Coverage stays strict; the message became usable.
        body = ('            <plugin name="Core">\n'
                "              <description>Core.</description>\n"
                '              <files><folder source="core" destination="" /></files>\n'
                '              <typeDescriptor><type name="Required" /></typeDescriptor>\n'
                "            </plugin>")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write_third_party_fomod(root, body)
            (root / "orphan").mkdir()
            (root / "orphan" / "Unused.esp").write_bytes(b"TES4unused")
            report = validate_fomod(root, strict_coverage=True)
            self.assertEqual(report["result"], "FAIL")
            self.assertTrue(any("orphan/Unused.esp" in e for e in report["errors"]),
                            f"error must name the offending file: {report['errors']}")


class ExistingFomodCompatibilityTests(unittest.TestCase):
    def test_empty_info_xml_is_valid_metadata_omission_with_warnings(self):
        from skyrim_forge.fomod import plan_to_xml, _write_xml

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            create_payload(root)
            normalized = validate_plan_data(sample_plan())
            config_tree, _ = plan_to_xml(normalized)
            _write_xml(config_tree, root / "fomod" / "ModuleConfig.xml")
            (root / "fomod" / "info.xml").write_text('<?xml version="1.0"?><fomod/>', encoding="utf-8")
            report = validate_fomod(root, strict_coverage=False)
            self.assertEqual(report["result"], "PASS", report)
            self.assertTrue(any("no Name" in item for item in report["warnings"]))
            self.assertTrue(any("no Version" in item for item in report["warnings"]))

    def test_empty_files_node_is_accepted_for_informational_option(self):
        from skyrim_forge.fomod import plan_to_xml, _write_xml

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            create_payload(root)
            normalized = validate_plan_data(sample_plan())
            config_tree, info_tree = plan_to_xml(normalized)
            first_files = config_tree.getroot().find("./installSteps/installStep/optionalFileGroups/group/plugins/plugin/files")
            for child in list(first_files):
                first_files.remove(child)
            _write_xml(config_tree, root / "fomod" / "ModuleConfig.xml")
            _write_xml(info_tree, root / "fomod" / "info.xml")
            report = validate_fomod(root, strict_coverage=False)
            self.assertEqual(report["result"], "PASS", report)

    def test_existing_xml_rejects_flag_reference_before_defining_step(self):
        from skyrim_forge.fomod import plan_to_xml, _write_xml

        plan = sample_plan()
        plan["steps"].append({
            "name": "Later",
            "visible": {"flag": {"name": "Theme", "value": "Red"}},
            "groups": [{
                "name": "Patch",
                "type": "SelectAny",
                "plugins": [{"name": "Patch", "description": "", "files": [], "type": "Optional"}],
            }],
        })
        normalized = validate_plan_data(plan)
        config_tree, info_tree = plan_to_xml(normalized)
        steps = config_tree.getroot().find("installSteps")
        defining, consuming = list(steps)
        steps.remove(consuming)
        steps.insert(0, consuming)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            create_payload(root)
            _write_xml(config_tree, root / "fomod" / "ModuleConfig.xml")
            _write_xml(info_tree, root / "fomod" / "info.xml")
            report = validate_fomod(root, strict_coverage=False)
            self.assertEqual(report["result"], "FAIL")
            self.assertTrue(any("not defined by earlier steps" in item for item in report["errors"]))
