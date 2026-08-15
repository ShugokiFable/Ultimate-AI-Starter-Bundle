"""Skill health gate: encoding, discoverability, and context budget.

Run against any skills directory (a provider home or the canonical tree). Exits
non-zero on a FAIL so it can gate a build or a CI step.

FAIL conditions (these break the agent, silently):
  * SKILL.md that a strict frontmatter reader cannot open (BOM is the usual cause)
  * SKILL.md with no description -- the agent has nothing to match on
  * mojibake in a description

WARN conditions (these cost context, not correctness):
  * SKILL.md body over the Agent Skills tier-2 budget (~5k tokens / 500 lines)
  * a description so long it is expensive on every single request

Budget model (Agent Skills progressive disclosure):
  tier 1  name + description, in context ALWAYS, for every skill
  tier 2  the SKILL.md body, loaded on activation
  tier 3  reference files, loaded only on demand

    python audit_skills.py <skills-dir> [more dirs...]
"""
import os
import re
import sys

BODY_TOKENS = 5000
BODY_LINES = 500
DESC_TOKENS = 150          # generous; Anthropic's own median is ~80
MOJIBAKE = ('â€', 'Ã©', 'Ã¨', 'Ã¼')


def tokens(s):
    return len(s) / 4.0      # ~4 chars/token, adequate for budgeting


def audit(root):
    fails, warns, rows = [], [], []
    if not os.path.isdir(root):
        print('  (missing: %s)' % root)
        return fails, warns, rows

    for sk in sorted(os.listdir(root)):
        p = os.path.join(root, sk, 'SKILL.md')
        if not os.path.isfile(p):
            continue
        raw = open(p, 'rb').read()

        if raw.startswith(b'\xef\xbb\xbf'):
            fails.append('%s: UTF-8 BOM before frontmatter -- description will not load' % sk)
            raw = raw[3:]

        txt = raw.decode('utf-8', errors='replace')
        m = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)$', txt, re.S)
        if not m:
            fails.append('%s: frontmatter block does not open' % sk)
            continue
        fm, body = m.group(1), m.group(2)

        dm = re.search(r'^description:\s*(.*?)(?=^\w+:|\Z)', fm, re.S | re.M)
        desc = ' '.join((dm.group(1) if dm else '').split())
        if not desc:
            fails.append('%s: no description -- skill is undiscoverable' % sk)
        if any(sig in desc for sig in MOJIBAKE):
            fails.append('%s: mojibake in description' % sk)

        bt, bl, dt = tokens(body), body.count('\n') + 1, tokens(desc)
        if bt > BODY_TOKENS or bl > BODY_LINES:
            warns.append('%s: body ~%.0f tok / %d lines (budget %d/%d) -- move detail to '
                         'reference files' % (sk, bt, bl, BODY_TOKENS, BODY_LINES))
        if dt > DESC_TOKENS:
            warns.append('%s: description ~%.0f tok -- paid on every request' % (sk, dt))
        rows.append((sk, dt, bt, bl))
    return fails, warns, rows


def main():
    roots = sys.argv[1:]
    if not roots:
        print(__doc__)
        return 2
    total_fail = 0
    for root in roots:
        print('=== %s ===' % root)
        fails, warns, rows = audit(root)
        if rows:
            t1 = sum(d + 12 for _, d, _, _ in rows)
            print('  %d skills | tier-1 always-on ~%.0f tokens | tier-2 total ~%.0f tokens'
                  % (len(rows), t1, sum(b for _, _, b, _ in rows)))
        for w in warns:
            print('  WARN  ' + w)
        for f in fails:
            print('  FAIL  ' + f)
        print('  RESULT: %s (%d fail, %d warn)\n'
              % ('PASS' if not fails else 'FAIL', len(fails), len(warns)))
        total_fail += len(fails)
    return 1 if total_fail else 0


if __name__ == '__main__':
    sys.exit(main())
