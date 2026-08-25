---
name: win64-native-builds
description: Build, test, and release-gate native Win64 C/C++ executables - compiler selection with or without the Windows SDK, strict warning gates, and reproducible release binaries.
---

# Win64 Native Builds

Playbook for native Windows executables built from source with shell tools.

## Compiler selection (the fork in the road)
- **App ships its own Win32 header** (e.g. `win32_min.h` declaring prototypes, no libc includes): Clang works WITHOUT the Windows SDK. This is what makes a strict `-Werror` release build possible on a machine with no MSVC installed. Clang lives at `C:/Program Files/LLVM/bin/clang.exe`.
- **Anything including libc headers** (`<stdio.h>`, `<string.h>` — i.e. almost every test): use mingw `gcc` from PATH. Clang in default MSVC mode lacks libc/UCRT headers until the full Windows SDK is installed; don't fight it, tests don't need clang.
- Tests may `#include "main.c"` directly to see every static — no header extraction needed. Give test mains a dummy `WinMainCRTStartup` define if the app defines WinMain.

## Flags that are load-bearing
| Flag | Reason |
|---|---|
| `-fno-builtin` on test/gcc builds | Compiler turns a hand-written `memset`/`memcpy` into a call to itself → infinite recursion. Silent until stack overflow. |
| `-l<lib>` AFTER source files | GNU ld resolves left-to-right; libs first = unresolved symbols. |
| `-Wl,--stack,8388608` | Default 1 MB stack dies on large static arrays in tests. |
| `-O2 -w` for the suite | Strictness belongs to the app's `-Werror` build; the suite optimizes for speed and signal. |

## Suite runner pattern
One committed `run_all_tests.sh`: cd to script dir, pick first available compiler (gcc→cc→clang), fixed flags, compile every `*_test.c`, run each, print `PASS/FAIL name` and a final count. Delete the output dir's old files first so stale passes can't mask failures. Per-test convention: a `reset_all()` helper between checks; assert-style checks that print `FAIL:` and set nonzero exit.

## Release gates (in order, all executed — never asserted)
1. Strict build (`-Werror`) exits 0.
2. Full suite green; report N/N, not "tests pass".
3. Double build → identical SHA-256 (determinism).
4. Clean-room rebuild: pristine source copy in a scratch dir → byte-identical binaries.
5. Hashes recorded (`PATCH_SHA256SUMS.txt`); GOLD tree purged of `*.o`, logs, save files, test debris.

## Hermes terminal discipline (this host)
Keep each `terminal()` call small: one grep, one sed range, one build step. Multi-substitution one-liners with nested `$()` and quote layers trip the hardline parser and get blocked wholesale (the error saves the command to a cache path — recoverable, but the lazy fix is not writing monster one-liners). For genuinely complex logic: `write_file` a `.sh`, then `terminal("bash that.sh")`. Prefer `read_file`/sed ranges over cat; prefer search tools over find/xargs chains.

## Pitfalls
- Version strings hide in more places than `VERSION.txt` — typically also an in-code startup log line. Grep the version token across source before claiming a bump is done.
- Dev tree ≠ release tree: docs written during the sprint must be copied into the packaged GOLD folder, and the DEV tree's VERSION.txt bumped too. Verify both, not just the release.
