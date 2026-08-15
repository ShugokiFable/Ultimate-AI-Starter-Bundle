"""Merge new evidence entries into a skyrim-memory ERROR-REGISTRY.json.

Idempotent: an entry whose id already exists is replaced, not duplicated, so
re-running after an edit updates in place. Refuses to write if an entry is
missing a required field or claims an evidence level outside the ladder --
the registry's whole value is that every row is evidence-backed, so a
malformed row is worse than a missing one.

    python merge_registry.py <registry.json> <additions.json> [--check]
"""
import json
import sys

REQUIRED = ('id', 'title', 'symptom', 'root_cause', 'prevention',
            'evidence_status', 'sources')


def load(p):
    with open(p, encoding='utf-8-sig') as fh:
        return json.load(fh)


def main():
    reg_path, add_path = sys.argv[1], sys.argv[2]
    check_only = '--check' in sys.argv

    reg = load(reg_path)
    add = load(add_path)
    ladder = set(reg.get('evidence_ladder', []))
    new = add['entries']

    problems = []
    for e in new:
        for f in REQUIRED:
            if not e.get(f):
                problems.append('%s: missing %s' % (e.get('id', '?'), f))
        if ladder and e.get('evidence_status') not in ladder:
            problems.append('%s: evidence_status %r not in ladder %s'
                            % (e.get('id'), e.get('evidence_status'), sorted(ladder)))
    if problems:
        print('REFUSING TO MERGE:')
        for p in problems:
            print('  ' + p)
        return 1

    by_id = {e['id']: e for e in reg['entries']}
    before = len(by_id)
    added, replaced = [], []
    for e in new:
        (replaced if e['id'] in by_id else added).append(e['id'])
        by_id[e['id']] = e

    reg['entries'] = [by_id[k] for k in sorted(by_id)]
    reg['schema_version'] = '6.0.0'
    reg['generated'] = '2026-08-14'

    print('registry %s' % reg_path)
    print('  before: %d entries' % before)
    print('  added   (%d): %s' % (len(added), ', '.join(added)))
    print('  replaced(%d): %s' % (len(replaced), ', '.join(replaced) or '-'))
    print('  total   : %d entries' % len(reg['entries']))

    if check_only:
        print('  --check: not written')
        return 0

    with open(reg_path, 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(reg, fh, indent=2, ensure_ascii=True)
        fh.write('\n')
    print('  written (UTF-8, no BOM, LF)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
