# MO2 automation

Forge snapshots the selected profile's `plugins.txt`, `loadorder.txt`, `modlist.txt`, and profile INIs before tool execution.

Tools may be launched through the selected profile using MO2's run command. Forge intentionally prohibits the unsafe multi-instance switch. Output should be directed to a dedicated temporary output mod or Forge workspace, never left unclassified in generic Overwrite.

Applying a load-order plan requires a separate approval and produces a backup.
