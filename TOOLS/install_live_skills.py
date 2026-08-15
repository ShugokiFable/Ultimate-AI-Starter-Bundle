"""Install the v6 canonical skills into the live provider homes.

Deliberately conservative:

  * Backs up each provider's existing skills tree first.
  * Only touches skill directories the canonical tree actually contains, so
    provider-only extras (e.g. the other-games mega-pack under .codex) are
    left completely alone.
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

HOMES = {
    'claude': r'%USERPROFILE%\.claude\skills',
    'grok': r'%USERPROFILE%\.grok\skills',
    'codex': r'%USERPROFILE%\.codex\skills',
    'kimi-code': r'%USERPROFILE%\.kimi-code\skills',
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
    added = changed = kept = 0
    skills = [d for d in sorted(os.listdir(canon))
              if os.path.isdir(os.path.join(canon, d))]
    for sk in skills:
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
    return added, changed, kept, len(skills)


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
            backup = dest + '.bak-v6-' + stamp
            if not os.path.exists(backup):
                shutil.copytree(dest, backup, symlinks=True,
                                ignore_dangling_symlinks=True)
        a, c, k, n = install(canon, dest, provider, check, notes)
        print('%-10s %3d skills present -> canonical %d | +%d new, %d updated, %d unchanged%s'
              % (provider, existing, n, a, c, k, '  [CHECK ONLY]' if check else ''))
        for msg in notes:
            print('           ! %s' % msg)
        if not check:
            print('           backup: %s' % os.path.basename(dest + '.bak-v6-' + stamp))


if __name__ == '__main__':
    main()
