"""The Hermes Superpowers bootstrap must survive a compaction.

Hermes injects the bootstrap into the first turn's user message. A long
session gets compacted, that message is summarised away, and before v7.7.0
the hook only ever fired on turn 1 -- so the model silently lost superpowers
for the rest of the run. The three cases below are the whole contract.

Run: python TESTS/test_hermes_bootstrap.py
"""
import os
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "BUNDLED-TOOLS" / "plugins" / "superpowers" / ".hermes-plugin"


def load_adapter():
    sys.path.insert(0, str(PLUGIN))
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "hermes_superpowers", PLUGIN / "__init__.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FakeCtx:
    def __init__(self):
        self.skills = {}
        self.hooks = {}

    def register_skill(self, name, path):
        assert isinstance(path, Path), "register_skill needs a Path, not a str"
        self.skills[name] = path

    def register_hook(self, name, fn):
        self.hooks[name] = fn


def main():
    mod = load_adapter()
    ctx = FakeCtx()
    mod.register(ctx)

    assert ctx.skills, "no skills registered"
    hook = ctx.hooks.get("pre_llm_call")
    assert hook, "pre_llm_call not registered"
    marker = mod.BOOTSTRAP_MARKER

    # 1. first turn -> inject
    out = hook(is_first_turn=True, conversation_history=[])
    assert out and marker in out["context"], "first turn must inject"

    # 2. normal turn, bootstrap still in history -> do not re-inject
    hist = [{"role": "user", "content": "hello " + marker + " rest"},
            {"role": "assistant", "content": "hi"}]
    out = hook(is_first_turn=False, conversation_history=hist)
    assert out is None, "must not re-inject while the bootstrap is still present"

    # 3. after compaction, marker gone -> inject again
    compacted = [{"role": "user", "content": "[summary of earlier turns]"},
                 {"role": "assistant", "content": "continuing"}]
    out = hook(is_first_turn=False, conversation_history=compacted)
    assert out and marker in out["context"], "must re-inject after compaction"

    # 4. history not supplied -> stay quiet rather than inject every turn
    out = hook(is_first_turn=False, conversation_history=None)
    assert out is None, "unknown history must not trigger per-turn injection"

    # 5. nested/odd shapes must not crash the hook
    weird = [{"role": "user", "content": [{"type": "text", "text": marker}]}]
    assert hook(is_first_turn=False, conversation_history=weird) is None
    assert hook(is_first_turn=False, conversation_history=[object()]) is not None

    print("hermes bootstrap: 5 cases OK (%d skills registered)" % len(ctx.skills))
    return 0


if __name__ == "__main__":
    sys.exit(main())
