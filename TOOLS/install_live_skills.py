"""Install the canonical skills into the live provider homes.

Deliberately conservative:

  * Backs up each provider's existing skills tree first (only when something
    will actually change).
  * Only touches skill directories the canonical tree actually contains, so
    provider-only extras (e.g. the other-games mega-pack under .codex and
    .hermes) are left completely alone.
  * Never deletes. A skill that stops being scoped to a provider is simply no
    longer written there; removing the existing copy is a human decision.
  * Copies scripts byte-for-byte; a .ps1 keeps its BOM (PS 5.1 needs it) while
    SKILL.md is written BOM-less (a BOM would hide its description).
  * --check reports what WOULD change and writes nothing.

    python install_live_skills.py <canonical-dir> [--check]
"""
import io
import os
import shutil
import stat
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fanout_providers import SCOPED  # noqa: E402  single source of truth

# Keyed by the same provider names fanout_providers.PROVIDERS uses, so SCOPED
# means the same thing in both tools. Hermes was missing here until v7.2.1,
# which is why the bundle's most-used provider silently drifted three whole
# skills behind canonical while the other four reported "up to date".
HOMES = {
    'Claude': r'%USERPROFILE%\.claude\skills',
    'Grok': r'%USERPROFILE%\.grok\skills',
    'Codex': r'%USERPROFILE%\.codex\skills',
    'Kimi': r'%USERPROFILE%\.kimi-code\skills',
    'Hermes': r'%LOCALAPPDATA%\hermes\skills',
}
VERBATIM_EXT = {'.ps1', '.psm1', '.psd1', '.bat', '.cmd'}


def same(a, b):
    try:
        return open(a, 'rb').read() == open(b, 'rb').read()
    except OSError:
        return False


def is_reparse(p):
    """True for a Windows junction or symlink, without following it."""
    try:
        return bool(os.lstat(p).st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT)
    except (OSError, AttributeError):
        return False


def clear_dangling(dst_dir, notes):
    """A junction whose target is gone shadows the real skill and breaks every
    read of it. Observed live: .grok\\skills\\skyrim-memory pointed at a
    non-existent shared .agents directory, so Grok's mandated first skill
    resolved to nothing. Remove the link (never the target) and let real files
    be written in its place."""
    if not is_reparse(dst_dir):
        return False
    target_ok = os.path.isdir(dst_dir)          # follows the link
    if target_ok:
        notes.append('LEFT INTACT (live junction): %s' % os.path.basename(dst_dir))
        return False
    try:
        os.rmdir(dst_dir)                        # removes the link only
        notes.append('replaced DANGLING junction: %s' % os.path.basename(dst_dir))
        return True
    except OSError as e:
        notes.append('could not clear junction %s (%s)' % (os.path.basename(dst_dir), e))
        return False


def install(canon, dest, provider, check, notes):
    added = changed = kept = withheld = 0
    skills = [d for d in sorted(os.listdir(canon))
              if os.path.isdir(os.path.join(canon, d))
              and os.path.exists(os.path.join(canon, d, 'SKILL.md'))]
    for sk in skills:
        if sk in SCOPED and provider not in SCOPED[sk]:
            withheld += 1
            continue
        src_dir = os.path.join(canon, sk)
        dst_dir = os.path.join(dest, sk)
        if is_reparse(dst_dir):
            if check:
                notes.append('%s junction: %s' % (
                    'DANGLING' if not os.path.isdir(dst_dir) else 'live', sk))
            else:
                clear_dangling(dst_dir, notes)
        for dp, _, fs in os.walk(src_dir):
            for f in fs:
                sp = os.path.join(dp, f)
                op = os.path.join(dst_dir, os.path.relpath(sp, src_dir))
                if not os.path.exists(op):
                    added += 1
                elif same(sp, op):
                    kept += 1
                    continue
                else:
                    changed += 1
                if check:
                    continue
                os.makedirs(os.path.dirname(op), exist_ok=True)
                if os.path.splitext(f)[1].lower() in VERBATIM_EXT:
                    shutil.copy2(sp, op)
                else:
                    data = io.open(sp, 'rb').read()
                    io.open(op, 'wb').write(data)
    return added, changed, kept, len(skills) - withheld, withheld


def main():
    canon = sys.argv[1]
    check = '--check' in sys.argv
    stamp = time.strftime('%Y%m%d-%H%M%S')

    for provider, raw in HOMES.items():
        dest = os.path.expandvars(raw)
        if not os.path.isdir(dest):
            print('%-10s (not installed: %s)' % (provider, dest))
            continue
        existing = len([d for d in os.listdir(dest)
                        if os.path.isdir(os.path.join(dest, d))])
        notes = []
        if not check:
            # Dangling junctions must go BEFORE the backup. Python treats a
            # Windows junction as a directory (not a symlink), so copytree
            # recurses into it and aborts the whole backup on a dead target --
            # symlinks=True does not help.
            for d in sorted(os.listdir(dest)):
                p = os.path.join(dest, d)
                if is_reparse(p) and not os.path.isdir(p):
                    clear_dangling(p, notes)
        # Probe before touching anything. Backing up an unchanged tree is pure
        # waste: a run that installs nothing used to still copy ~53 MB per
        # provider, and those stacked up (13 backup trees / ~692 MB observed on
        # one machine). Only spend the copy when there is something to undo.
        pending_a, pending_c = install(canon, dest, provider, True, [])[:2]
        backed_up = False
        if not check and (pending_a or pending_c):
            backup = dest + '.bak-uabs-' + stamp
            if not os.path.exists(backup):
                shutil.copytree(dest, backup, symlinks=True,
                                ignore_dangling_symlinks=True)
                backed_up = True
        a, c, k, n, w = install(canon, dest, provider, check, notes)
        if w:
            held = ', '.join(sorted(s for s, p in SCOPED.items() if provider not in p))
            notes.insert(0, 'withheld (scoped elsewhere): %s' % held)
        print('%-8s %3d skills present -> canonical %d | +%d new, %d updated, %d unchanged%s'
              % (provider, existing, n, a, c, k, '  [CHECK ONLY]' if check else ''))
        for msg in notes:
            print('           ! %s' % msg)
        if not check:
            if backed_up:
                print('           backup: %s' % os.path.basename(dest + '.bak-uabs-' + stamp))
            else:
                print('           backup: skipped (nothing changed)')


if __name__ == '__main__':
    main()
