# Networking and persistence

Classify every feature as client-only, server-only, logical-side shared, or
network synchronized.

Verify:

- channel/payload registration timing;
- packet IDs and codecs;
- sender authority and validation;
- main-thread handoff;
- login/config/play phase;
- optional-client compatibility;
- dedicated server classloading;
- reconnect and dimension transfer;
- saved-data migrations;
- packet-size and abuse limits.

Test a dedicated server, not only integrated single player.
