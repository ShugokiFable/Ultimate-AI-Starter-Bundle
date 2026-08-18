# Prompts in this pack

The **installed** operating contract is the pack-root `AIO-INSTRUCTION.txt`.
Paste that one into provider custom-instructions. It is the file the installer
and BOOTSTRAP tell you to use.

`AIO-INSTRUCTION.txt` in this folder is a leftover jail paste. It is **not**
installed, and v6.9.0 does not ship it as the contract. Stacking a jail on top
of the real contract wastes tokens and fights the format lock. Adult-fiction
game-modding is already in scope (rule 11). Child / age-ambiguous / real-person
sexual content is still refused.

Caption and sheet **technique** from that kit now lives in the skills
`adult-image-caption` and `adult-character-sheet`. The jail headers, site
lists, and performer aliases were not copied.

SillyTavern presets stay in the operator's own prompt folder. Do not merge
those jails into Claude, Grok, Codex, Kimi, or Hermes system instructions.

`4-PREAMBLES/` (v7.5.0) holds the operator's SOUL config and the web-UI
manual-paste file; the installer wires `SOUL.md` + the root operating
contract into every provider instruction file. See `4-PREAMBLES/README.md`.
