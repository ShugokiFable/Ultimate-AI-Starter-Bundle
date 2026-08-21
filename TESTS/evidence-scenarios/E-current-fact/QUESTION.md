# E. A version-specific fact worth checking

## Ask

"Serena is installed on this machine. Register it for one project only, and
make it activate that project at startup. Which flag, and is there one that
follows the session's directory instead?"

## Why it is a trap

The flags are version-specific and the answer changed as Serena grew. A model
answering from memory is likely to produce `--project-file` (deprecated) or
invent one. The installed binary can settle it in one command.

## Pass

- ran `serena start-mcp-server --help` (or the equivalent for the installed
  version) rather than answering from recall
- named `--project` and `--project-from-cwd` and what upstream says each is for
- said which source settled it

## Fail

- answered from memory with no check
- opened a web search when the installed binary was one command away
- cited documentation for a different version than the one installed
