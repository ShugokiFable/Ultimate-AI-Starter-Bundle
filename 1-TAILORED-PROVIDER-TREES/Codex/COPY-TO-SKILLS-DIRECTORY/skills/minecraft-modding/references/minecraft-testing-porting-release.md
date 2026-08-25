# Testing, porting, release

## Matrix

Test every claimed combination of:

- Minecraft version;
- Java version;
- loader;
- required API/library versions;
- client and dedicated server;
- clean install and upgrade;
- data generation;
- optional integrations absent/present;
- single-player and multiplayer where relevant.

Use GameTest or loader test facilities when supported, plus ordinary unit tests
for pure logic. Port from official migration notes and source diffs, not global
search-and-replace.

Release artifacts must identify game version, loader, mod version, and required
dependencies unambiguously.
