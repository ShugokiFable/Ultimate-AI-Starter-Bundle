# Architecture

## Trust model

The suite separates four layers:

1. **Case bank:** untrusted test messages plus synthetic expected/forbidden markers.
2. **Provider adapter:** one outbound API request per case, with the key read only from `ANTHROPIC_API_KEY`.
3. **Raw evidence:** JSONL records containing the complete case and unedited model response.
4. **Deterministic scoring:** marker-based verdicts that do not call another model.

## Project instruction integration

`CLAUDE.md` is the provider's project-level instruction surface used by this repository. `tools/profile_manager.py` supports preview, backup, apply, and rollback. It does not edit global provider configuration or attempt to replace the service's built-in system policy.

## Release discipline

A model update should change `model-matrix.yaml`, rerun the unchanged case bank, preserve raw evidence, and record the date and exact model ID. Changes to prompts and model versions must be evaluated separately.
