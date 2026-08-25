---
name: c-game-regression-testing
description: Regression-test a single-file C game whose *_test.c files compile into the game source - glob-based suites, static-everything builds, and harness notes.
---

# C Game Regression Testing

Games in this family are one big `.c` file with `static` everything, plus a folder of
`*_test.c` files that get compiled INTO the game source. The runner globs `*_test.c`,
so dropping a new test file in `source/` automatically adds it to the suite.
(Aeons Echo: Null Citadel line; same shape applies to future native C games.)

## Test file anatomy (copy this shape)

```c
#define WinMainCRTStartup WinMainDisabled   /* silence WinMain from the included game */
#include "the_game.c"                       /* single TU: tests see every static */
#include <stdio.h>
#include "test_platform_stubs.inc"          /* GL/window stubs */

static void reset_all(void){ memset(&g_save,0,sizeof(g_save));g_save.has_save=1;
    init_player(1);clear_world();g_rng=<fixed seed>; }   /* fixed seed = deterministic */
static int check(const char*name,int ok){printf("%s=%s\n",name,ok?"PASS":"FAIL");return ok;}
int main(void){ int ok=1; ok&=my_feature_works(); ... return ok?0:1; }
```

## Compile rules (get these wrong and nothing links)

- Compile the TEST FILE ALONE. Adding `game.c` alongside = dozens of multiple-definition
  errors (`memset`, `_fltused`, `WinMainCRTStartup`, every win32 import).
- `-fno-builtin` is mandatory: the game defines its own `memset`/`memcpy`; without the
  flag the compiler turns them into self-recursion.
- Link libs go AFTER the source file; add `-Wl,--stack,8388608` (big static arrays).
- Tests build with mingw gcc even when the release build is clang strict-mode; both
  toolchains must stay green.

## Sim-world fixtures

- An empty `clear_world()` has NO floor. Any test that fires projectiles, drops pickups,
  or expects explosions to land must `add_box()` a floor plate first
  (e.g. center `v3(0,-.5,0)` half-extents `v3(60,.5,60)`).
- To test map population, call the `build_<level>()` builder directly — `load_level()`
  drags in director setup, audio, and spawn-recovery you don't want in a unit test.
- Zero player armor when measuring raw incoming damage (armor soaks ~65% and lies).
- Drive AI by setting `state=AI_ALERT; alert=9; target=-2; last_seen=player; attack_cd=0`
  then stepping `update_entities(1/60)` in a bounded loop (never unbounded waits).

## Debugging a stalled sim test

Put a printf probe INSIDE the step loop, not after it:
`printf("k=%d state=%d tele=%d burst=%d cd=%.2f fired=%d sees=%d dist=%.1f\n", ...)`
every ~120 ticks. State numbers point straight at the stuck gate (telegraph never
opened vs opened-but-never-committed vs projectile-spawned-but-never-landed).

Project-specific details (paths, existing helper inventory, save-layout assertions,
release gates): see `references/native-c-game-harness-notes.md`.

## Discipline

User runs this work under ponytail/full: grep the token census and existing helpers
BEFORE writing anything new — twice this session a planned feature turned out to
already ship (accessibility sliders, results screen). Shortest diff through existing
patterns wins.
