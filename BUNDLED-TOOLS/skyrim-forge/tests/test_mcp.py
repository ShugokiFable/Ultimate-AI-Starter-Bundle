from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from skyrim_forge.config import load_config
from skyrim_forge.mcp_server import (
    META_PROTOCOL_VERSION,
    META_SERVER_INFO,
    MODERN_PROTOCOL,
    TOOL_SPECS,
    UNSUPPORTED_PROTOCOL_VERSION,
    handle,
)
from skyrim_forge.service import ForgeService


class McpTests(unittest.TestCase):
    def test_initialize_and_tools(self):
        with tempfile.TemporaryDirectory() as td:
            with patch("pathlib.Path.home", return_value=Path(td)):
                service=ForgeService(load_config(Path(td)/"config.toml"))
            response=handle(service,{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}})
            self.assertEqual(response["result"]["protocolVersion"],"2025-11-25")
            listed=handle(service,{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
            self.assertEqual(len(listed["result"]["tools"]),len(TOOL_SPECS))
            self.assertGreaterEqual(len(TOOL_SPECS),18)


    def test_fomod_surface_is_exposed(self):
        expected = {
            "forge_fomod_validate",
            "forge_fomod_plan_validate",
            "forge_fomod_build",
            "forge_fomod_scaffold",
            "forge_fomod_simulate",
        }
        self.assertTrue(expected.issubset(TOOL_SPECS))
        with tempfile.TemporaryDirectory() as td:
            with patch("pathlib.Path.home", return_value=Path(td)):
                service = ForgeService(load_config(Path(td) / "config.toml"))
            resources = handle(service, {"jsonrpc": "2.0", "id": 4, "method": "resources/list", "params": {}})
            uris = {item["uri"] for item in resources["result"]["resources"]}
            self.assertIn("forge://schemas/fomod-plan", uris)
            self.assertIn("forge://docs/fomod", uris)
            prompts = handle(service, {"jsonrpc": "2.0", "id": 5, "method": "prompts/list", "params": {}})
            names = {item["name"] for item in prompts["result"]["prompts"]}
            self.assertIn("build_fomod_installer", names)


    def test_nexus_publication_surface_is_exposed(self):
        expected = {
            "forge_nexus_policy_status",
            "forge_nexus_scaffold",
            "forge_nexus_plan_validate",
            "forge_nexus_audit",
            "forge_nexus_build",
            "forge_nexus_page_render",
        }
        self.assertTrue(expected.issubset(TOOL_SPECS))
        with tempfile.TemporaryDirectory() as td:
            with patch("pathlib.Path.home", return_value=Path(td)):
                service = ForgeService(load_config(Path(td) / "config.toml"))
            resources = handle(service, {"jsonrpc": "2.0", "id": 6, "method": "resources/list", "params": {}})
            uris = {item["uri"] for item in resources["result"]["resources"]}
            self.assertIn("forge://schemas/nexus-publication-plan", uris)
            self.assertIn("forge://docs/nexus-publication", uris)
            self.assertIn("forge://references/nexus-policy-lock", uris)
            prompts = handle(service, {"jsonrpc": "2.0", "id": 7, "method": "prompts/list", "params": {}})
            names = {item["name"] for item in prompts["result"]["prompts"]}
            self.assertIn("prepare_nexus_release", names)

    def test_tool_call(self):
        with tempfile.TemporaryDirectory() as td:
            with patch("pathlib.Path.home", return_value=Path(td)):
                service=ForgeService(load_config(Path(td)/"config.toml"))
            result=handle(service,{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"forge_version","arguments":{}}})
            self.assertFalse(result["result"]["isError"])

    def test_papyrus_compile_tool_reaches_the_service(self):
        with tempfile.TemporaryDirectory() as td:
            with patch("pathlib.Path.home", return_value=Path(td)):
                service = ForgeService(load_config(Path(td) / "config.toml"))
            with patch.object(service, "papyrus_compile", return_value={"result": "ROUTED"}):
                response = handle(service, {
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "tools/call",
                    "params": {
                        "name": "forge_papyrus_compile",
                        "arguments": {
                            "scripts": [],
                            "output_dir": str(Path(td) / "compiled"),
                            "approved": False,
                        },
                    },
                })
            self.assertFalse(response["result"]["isError"])
            self.assertIn('"ROUTED"', response["result"]["content"][0]["text"])


class DualEraMcpTests(unittest.TestCase):
    """2026-07-28 removed the handshake; Forge must serve both eras at once."""

    def _service(self, td):
        with patch("pathlib.Path.home", return_value=Path(td)):
            return ForgeService(load_config(Path(td) / "config.toml"))

    def _modern(self, method, params=None):
        body = dict(params or {})
        body["_meta"] = {META_PROTOCOL_VERSION: MODERN_PROTOCOL}
        return {"jsonrpc": "2.0", "id": 1, "method": method, "params": body}

    def test_server_discover_is_implemented(self):
        # Servers MUST implement server/discover under 2026-07-28.
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, self._modern("server/discover"))["result"]
            self.assertIn(MODERN_PROTOCOL, result["supportedVersions"])
            self.assertEqual(result["resultType"], "complete")
            self.assertEqual(result["_meta"][META_SERVER_INFO]["name"], "skyrim-forge")
            self.assertIn("tools", result["capabilities"])

    def test_discover_answers_an_unprobed_client(self):
        # The stdio backward-compatibility probe may arrive without _meta.
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, {"jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {}})["result"]
            self.assertIn(MODERN_PROTOCOL, result["supportedVersions"])

    def test_unsupported_version_is_refused_with_its_supported_list(self):
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            request = {"jsonrpc": "2.0", "id": 9, "method": "tools/list",
                       "params": {"_meta": {META_PROTOCOL_VERSION: "1900-01-01"}}}
            error = handle(service, request)["error"]
            self.assertEqual(error["code"], UNSUPPORTED_PROTOCOL_VERSION)
            self.assertEqual(error["data"]["requested"], "1900-01-01")
            self.assertIn(MODERN_PROTOCOL, error["data"]["supported"])

    def test_modern_lists_carry_required_caching_hints(self):
        # Caching hints are MANDATORY on complete results for these operations.
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            for method in ("tools/list", "resources/list", "prompts/list"):
                result = handle(service, self._modern(method))["result"]
                self.assertEqual(result["resultType"], "complete", method)
                self.assertGreaterEqual(result["ttlMs"], 0, method)
                self.assertEqual(result["cacheScope"], "public", method)

    def test_local_configuration_is_never_publicly_cacheable(self):
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, self._modern("resources/read", {"uri": "forge://config"}))["result"]
            self.assertEqual(result["cacheScope"], "private")
            self.assertEqual(result["ttlMs"], 0)

    def test_legacy_clients_keep_their_exact_result_shape(self):
        # Codex, Claude and Grok are registered against the handshake era. A
        # legacy response must not grow modern fields it cannot parse.
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            handshake = handle(service, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                         "params": {"protocolVersion": "2025-11-25"}})["result"]
            self.assertEqual(handshake["protocolVersion"], "2025-11-25")
            self.assertEqual(handshake["serverInfo"]["name"], "skyrim-forge")
            for method in ("tools/list", "resources/list", "prompts/list"):
                result = handle(service, {"jsonrpc": "2.0", "id": 2, "method": method, "params": {}})["result"]
                self.assertNotIn("resultType", result, method)
                self.assertNotIn("ttlMs", result, method)
                self.assertNotIn("cacheScope", result, method)

    def test_modern_tool_call_carries_result_type(self):
        # Claude Code 2026-07-28 rejects tools/call without resultType once the
        # server has advertised that revision. Caching hints are list/read only.
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, self._modern("tools/call", {"name": "forge_version", "arguments": {}}))["result"]
            self.assertEqual(result["resultType"], "complete")
            self.assertFalse(result["isError"])
            self.assertNotIn("ttlMs", result)
            self.assertNotIn("cacheScope", result)

    def test_tool_call_without_meta_still_carries_result_type(self):
        # stdio clients still send initialize, then tools/call with no _meta.
        # Advertising 2026-07-28 in discover/initialize is enough for Claude to
        # require resultType on the call result.
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                      "params": {"name": "forge_version", "arguments": {}}})["result"]
            self.assertEqual(result["resultType"], "complete")
            self.assertFalse(result["isError"])

    def test_initialize_modern_version_carries_result_type(self):
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                      "params": {"protocolVersion": MODERN_PROTOCOL}})["result"]
            self.assertEqual(result["protocolVersion"], MODERN_PROTOCOL)
            self.assertEqual(result["resultType"], "complete")

    def test_legacy_initialize_keeps_handshake_shape(self):
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            result = handle(service, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                      "params": {"protocolVersion": "2025-11-25"}})["result"]
            self.assertEqual(result["protocolVersion"], "2025-11-25")
            self.assertNotIn("resultType", result)

    def test_both_eras_expose_the_same_tools(self):
        with tempfile.TemporaryDirectory() as td:
            service = self._service(td)
            legacy = handle(service, {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})["result"]["tools"]
            modern = handle(service, self._modern("tools/list"))["result"]["tools"]
            self.assertEqual(legacy, modern)
            self.assertEqual(len(modern), len(TOOL_SPECS))


if __name__ == "__main__": unittest.main()
