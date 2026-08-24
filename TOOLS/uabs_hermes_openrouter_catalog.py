"""Expose OpenRouter's live tool-capable catalog in Hermes pickers.

Hermes 0.20.x fetches the live catalog but intersects it with a small curated
manifest.  This process-local compatibility shim removes that allowlist while
retaining Hermes' tool-calling compatibility check and offline fallback.
"""
from __future__ import annotations

import functools
import inspect
import json
import urllib.request
from typing import Any, Callable, Iterable


def _supports_tools(item: Any) -> bool:
    if not isinstance(item, dict):
        return True
    params = item.get("supported_parameters")
    return not isinstance(params, list) or "tools" in params


def _is_free(pricing: Any) -> bool:
    if not isinstance(pricing, dict):
        return False
    try:
        return float(pricing.get("prompt", "0")) == 0 and float(pricing.get("completion", "0")) == 0
    except (TypeError, ValueError):
        return False


def _catalog_rows(
    live_items: Iterable[Any],
    *,
    silent_default: str = "",
) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    seen: set[str] = set()
    for item in live_items:
        if not isinstance(item, dict) or not _supports_tools(item):
            continue
        model_id = str(item.get("id") or "").strip()
        if not model_id or model_id in seen:
            continue
        seen.add(model_id)
        description = "default" if model_id == silent_default else ("free" if _is_free(item.get("pricing")) else "")
        rows.append((model_id, description))
    if rows and not rows[0][1]:
        rows[0] = (rows[0][0], "recommended")
    return rows


def install() -> None:
    """Patch the dedicated Hermes process; safe to call more than once."""
    import hermes_cli.models as models

    if getattr(models, "_uabs_live_openrouter_catalog", False):
        return

    fallback: Callable[..., list[tuple[str, str]]] = models.fetch_openrouter_models

    @functools.wraps(fallback)
    def fetch_openrouter_models(timeout: float = 8.0, *, force_refresh: bool = False) -> list[tuple[str, str]]:
        if models._openrouter_catalog_cache is not None and not force_refresh:
            return list(models._openrouter_catalog_cache)
        try:
            request = urllib.request.Request(
                models._OPENROUTER_CATALOG_URL,
                headers={"Accept": "application/json"},
            )
            with models._urlopen_model_catalog_request(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode())
            live_items = payload.get("data", [])
            if not isinstance(live_items, list):
                raise ValueError("OpenRouter catalog data is not a list")

            seeded = models._seed_reasoning_caps(models._OPENROUTER_CATALOG_URL, live_items)
            if models._openrouter_reasoning_caps_cache is None and seeded is not None:
                models._openrouter_reasoning_caps_cache = seeded
            rows = _catalog_rows(
                live_items,
                silent_default=models.get_preferred_silent_default_model("openrouter"),
            )
            if not rows:
                raise ValueError("OpenRouter returned no tool-capable models")
            models._openrouter_catalog_cache = rows
            return list(rows)
        except Exception:
            return fallback(timeout=timeout, force_refresh=force_refresh)

    fetch_openrouter_models._uabs_live_catalog = True  # type: ignore[attr-defined]
    models.fetch_openrouter_models = fetch_openrouter_models
    models._uabs_live_openrouter_catalog = True

    import hermes_cli.model_switch as model_switch

    original_picker = model_switch.list_picker_providers
    if getattr(original_picker, "_uabs_openrouter_uncapped", False):
        return

    @functools.wraps(original_picker)
    def list_picker_providers(*args: Any, **kwargs: Any) -> list[dict]:
        bound = inspect.signature(original_picker).bind_partial(*args, **kwargs)
        requested_limit = bound.arguments.get("max_models")
        bound.arguments["max_models"] = None
        providers = original_picker(*bound.args, **bound.kwargs)
        if requested_limit is not None:
            for provider in providers:
                if str(provider.get("slug") or "").lower() != "openrouter":
                    provider["models"] = list(provider.get("models") or [])[: int(requested_limit)]
        return providers

    list_picker_providers._uabs_openrouter_uncapped = True  # type: ignore[attr-defined]
    model_switch.list_picker_providers = list_picker_providers

