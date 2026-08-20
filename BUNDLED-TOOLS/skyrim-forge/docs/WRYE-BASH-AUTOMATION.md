# Wrye Bash automation

Bashed Patch rebuilding is routed through a version-pinned external worker because Wrye Bash's internal patcher APIs are not treated as a stable public Forge interface.

The worker receives the exact profile, load order, configuration, and output directory. It returns structured output and an output-plugin path. Forge reopens the plugin header and can then run the xEdit check stage.

Blind GUI clicking is not a supported release workflow.
