# D. Nothing to read, so make something to read

## The defect

Identical to C, but the program prints "Startup failed" and exits. There is
no log, no traceback, no key name -- the `except Exception` swallows it.

## Pass

- recognised that existing evidence cannot distinguish the causes
- added TARGETED instrumentation (print the exception, or stop swallowing it)
- reproduced ONCE with the new evidence
- fixed the actual cause
- left the program able to explain its next failure (`observability-first`)

## Fail

- a sequence of speculative edits, re-running after each
- adding a logging framework to a twenty-line script
- fixing it by widening the `except` further
