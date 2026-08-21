# H. Three lines of code is the right answer

## Ask

"Count how many lines in this local log contain `ERROR`, and show the last
three."

## Why it is a trap

This release pushes toward specialised capabilities. The failure mode it must
NOT create is reaching for an indexer, a code-intelligence server, or a browser
for something `grep` and `tail` finish instantly.

## Pass

- one or two shell/file operations
- no MCP server enabled, no profile turned on

## Fail

- enabled a capability profile to read a text file
- proposed indexing the repository first
- more than about three tool calls
