"""Fan the canonical skill tree out to every provider tree in the pack.

The provider skill trees were verified byte-identical to each other in v5, so
maintaining five copies by hand buys nothing and loses drift-resistance -- that
is how v5 ended up with a corrected `codebase-memory` skill live and a stale one
in the bundle. Canonical is the single source of truth; everything else is
generated.

Per-provider tailoring lives OUTSIDE the skills directory (COPY-MAP.md, and the
provider-home CLAUDE.md / AGENTS.md) and is never touched here. The only
in-skill tailoring is the `provider:` metadata tag, which is rewritten per
target.

    python fanout_providers.py <canonical-dir> <pack-root>
"""
import io
import os
import re
import shutil
import sys

TAILORED = '1-RECOMMENDED-SEPARATE-TAILORED'
GENERIC = '2-OPTIONAL-SHARED-GENERIC'
PROVIDERS = ['Claude', 'Codex', 'Grok', 'Hermes', 'Kimi']
REL = os.path.join('COPY-TO-SKILLS-DIRECTORY', 'skills')

# Canonical skills are distributed to every supported provider. Keep the map so
# a future, genuinely provider-specific skill has one explicit source of truth;
# it is intentionally empty for the current all-provider install policy.
SCOPED = {}


def retag(path, provider_tag):
    """Rewrite `provider:` inside YAML frontmatter and the registry JSON."""
    txt = io.open(path, encoding='utf-8').read()
    if path.lower().endswith('skill.md'):
        m = re.match(r'^(---\s*\n)(.*?)(\n---\s*\n)', txt, re.S)
        if not m:
            return txt
        fm = re.sub(r'^(\s*)provider:\s*\S+\s*$',
                    lambda g: '%sprovider: %s' % (g.group(1), provider_tag),
                    m.group(2), flags=re.M)
        return m.group(1) + fm + m.group(3) + txt[m.end():]
    if os.path.basename(path).upper() == 'ERROR-REGISTRY.JSON':
        return re.sub(r'"provider":\s*"[^"]*"(,\s*\n\s*"provider_display")',
                      '"provider": "%s"\\1' % provider_tag.lower(), txt, count=1)
    return txt


def source_newline(path):
    """The line ending the source file actually uses.

    .gitattributes sets `* -text` so a clone stays byte-identical and
    MANIFEST.json hashes verify. Writing every text file with newline='\\n'
    therefore rewrote CRLF sources to LF on every run -- byte churn in files
    whose content had not changed. Preserve what the source uses instead.
    """
    raw = io.open(path, 'rb').read()
    return '\r\n' if raw.count(b'\r\n') > raw.count(b'\n') - raw.count(b'\r\n') else '\n'


def deploy(canon, dest, provider_tag, provider):
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    n = skipped = 0
    for dp, _, fs in os.walk(canon):
        rel_top = os.path.relpath(dp, canon).split(os.sep)[0]
        if rel_top in SCOPED and provider not in SCOPED[rel_top]:
            skipped += len(fs)
            continue
        for f in fs:
            sp = os.path.join(dp, f)
            op = os.path.join(dest, os.path.relpath(sp, canon))
            os.makedirs(os.path.dirname(op), exist_ok=True)
            if os.path.splitext(f)[1].lower() in ('.md', '.json', '.txt', '.yaml', '.yml'):
                io.open(op, 'w', encoding='utf-8',
                        newline=source_newline(sp)).write(retag(sp, provider_tag))
            else:
                shutil.copy2(sp, op)
            n += 1
    return n, skipped


def main():
    canon, root = sys.argv[1], sys.argv[2]
    total = 0
    for family, tag_of in ((TAILORED, lambda p: p.lower()),
                           (GENERIC, lambda p: 'shared-generic')):
        for prov in PROVIDERS:
            dest = os.path.join(root, family, prov, REL)
            if not os.path.isdir(os.path.dirname(os.path.dirname(dest))):
                print('  skip (no tree): %s/%s' % (family, prov))
                continue
            n, skipped = deploy(canon, dest, tag_of(prov), prov)
            total += n
            note = ''
            if skipped:
                held = ', '.join(sorted(k for k, v in SCOPED.items() if prov not in v))
                note = '  (%d files withheld: %s)' % (skipped, held)
            print('  %-34s %-8s %4d files%s' % (family + '/' + prov, tag_of(prov), n, note))
    print('\n%d files written across provider trees' % total)
    if SCOPED:
        print('scoped skills (not fanned out to every provider): %s'
              % ', '.join('%s -> %s' % (k, '/'.join(sorted(v))) for k, v in SCOPED.items()))


if __name__ == '__main__':
    main()
